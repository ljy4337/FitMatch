import SwiftUI

struct SatisfactionPicker: View {
    @Binding var value: Int

    var body: some View {
        HStack {
            Text("만족도")
            Spacer()
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        value = score
                    } label: {
                        Image(systemName: score <= value ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(score <= value ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(score)점")
                }
            }
        }
    }
}
