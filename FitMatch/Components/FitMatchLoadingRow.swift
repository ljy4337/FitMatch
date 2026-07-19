import SwiftUI

enum FitMatchLoadingState {
    case done
    case loading
    case waiting
}

struct FitMatchLoadingRow: View {
    let title: String
    let state: FitMatchLoadingState

    var body: some View {
        HStack(spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.primary)
                case .loading:
                    ProgressView()
                case .waiting:
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(state == .waiting ? .secondary : .primary)
        }
    }
}
