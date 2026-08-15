import SwiftUI
import UIKit
import Combine

#if DEBUG
@MainActor
final class ScrollPerformanceMonitor: NSObject, ObservableObject {
    private let screen: String
    private var displayLink: CADisplayLink?
    private var startedAt = ProcessInfo.processInfo.systemUptime
    private var lastFrameTimestamp: CFTimeInterval?
    private var lastOffset: CGFloat?
    private var lastOffsetTimestamp: TimeInterval?
    private var lastSampleTimestamp: TimeInterval = 0
    private var activeUntil: TimeInterval = 0
    private var geometryEventsThisFrame = 0
    private var frameCount = 0
    private var longFrameCount = 0
    private var severeFrameCount = 0
    private var duplicateUpdateFrames = 0
    private var worstFrameMilliseconds: Double = 0

    init(screen: String) {
        self.screen = screen
    }

    func start() {
        guard displayLink == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        lastFrameTimestamp = nil
        frameCount = 0
        longFrameCount = 0
        severeFrameCount = 0
        duplicateUpdateFrames = 0
        worstFrameMilliseconds = 0
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        let maximumFPS = UIScreen.main.maximumFramesPerSecond
        link.preferredFrameRateRange = CAFrameRateRange(
            minimum: 60,
            maximum: Float(maximumFPS),
            preferred: Float(maximumFPS)
        )
        link.add(to: .main, forMode: .common)
        displayLink = link
        log("monitor_started", "requested_fps=\(maximumFPS)")
    }

    func stop() {
        guard displayLink != nil else { return }
        log(
            "monitor_summary",
            String(
                format: "frames=%d long_frames=%d severe_frames=%d duplicate_update_frames=%d worst_frame_ms=%.1f",
                frameCount,
                longFrameCount,
                severeFrameCount,
                duplicateUpdateFrames,
                worstFrameMilliseconds
            )
        )
        displayLink?.invalidate()
        displayLink = nil
    }

    func record(offset: CGFloat, contentHeight: CGFloat, containerHeight: CGFloat) {
        guard displayLink != nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        activeUntil = now + 0.25
        geometryEventsThisFrame += 1

        if geometryEventsThisFrame == 2 {
            duplicateUpdateFrames += 1
        }

        let velocity: Double
        if let lastOffset, let lastOffsetTimestamp, now > lastOffsetTimestamp {
            velocity = Double(offset - lastOffset) / (now - lastOffsetTimestamp)
        } else {
            velocity = 0
        }
        self.lastOffset = offset
        self.lastOffsetTimestamp = now

        guard now - lastSampleTimestamp >= 0.25 else { return }
        lastSampleTimestamp = now
        log(
            "scroll_sample",
            String(
                format: "offset=%.1f velocity=%.1f content=%.1f container=%.1f events_in_frame=%d",
                offset,
                velocity,
                contentHeight,
                containerHeight,
                geometryEventsThisFrame
            )
        )
    }

    func recordPhase(from oldPhase: String, to newPhase: String) {
        guard displayLink != nil else { return }
        activeUntil = ProcessInfo.processInfo.systemUptime + 0.25
        log("phase", "from=\(oldPhase) to=\(newPhase)")
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        defer {
            lastFrameTimestamp = link.timestamp
            geometryEventsThisFrame = 0
        }
        guard let lastFrameTimestamp else { return }

        frameCount += 1
        let frameMilliseconds = (link.timestamp - lastFrameTimestamp) * 1_000
        worstFrameMilliseconds = max(worstFrameMilliseconds, frameMilliseconds)
        guard ProcessInfo.processInfo.systemUptime <= activeUntil else { return }

        if frameMilliseconds >= 40 {
            severeFrameCount += 1
            log("severe_frame", String(format: "frame_ms=%.1f estimated_60hz_frames=%.1f", frameMilliseconds, frameMilliseconds / 16.67))
        } else if frameMilliseconds >= 24 {
            longFrameCount += 1
            log("long_frame", String(format: "frame_ms=%.1f estimated_60hz_frames=%.1f", frameMilliseconds, frameMilliseconds / 16.67))
        }
    }

    private func log(_ event: String, _ metadata: String = "") {
        let elapsed = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        let suffix = metadata.isEmpty ? "" : " \(metadata)"
        print(String(format: "[ScrollPerformance] screen=%@ event=%@ elapsed_ms=%.1f%@", screen, event, elapsed, suffix))
    }

}

private struct ScrollPerformanceDiagnosticsModifier: ViewModifier {
    @StateObject private var monitor: ScrollPerformanceMonitor

    init(screen: String) {
        _monitor = StateObject(wrappedValue: ScrollPerformanceMonitor(screen: screen))
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: ScrollPerformanceGeometry.self) { geometry in
                    ScrollPerformanceGeometry(
                        offset: geometry.contentOffset.y + geometry.contentInsets.top,
                        contentHeight: geometry.contentSize.height,
                        containerHeight: geometry.containerSize.height
                    )
                } action: { _, geometry in
                    monitor.record(
                        offset: geometry.offset,
                        contentHeight: geometry.contentHeight,
                        containerHeight: geometry.containerHeight
                    )
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    monitor.recordPhase(from: String(describing: oldPhase), to: String(describing: newPhase))
                }
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    monitor.start()
                }
                .onDisappear { monitor.stop() }
        } else {
            content
                .task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    monitor.start()
                }
                .onDisappear { monitor.stop() }
        }
    }
}

@available(iOS 18.0, *)
private struct ScrollPerformanceGeometry: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let containerHeight: CGFloat
}
#endif

extension View {
    @ViewBuilder
    func diagnosesScrollPerformance(screen: String) -> some View {
        #if DEBUG
        modifier(ScrollPerformanceDiagnosticsModifier(screen: screen))
        #else
        self
        #endif
    }
}
