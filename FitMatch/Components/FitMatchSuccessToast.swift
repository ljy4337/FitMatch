import SwiftUI

struct FitMatchSuccessToast: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 48)
            .background(Color.black.opacity(0.88), in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
            .accessibilityAddTraits(.isStaticText)
    }
}
