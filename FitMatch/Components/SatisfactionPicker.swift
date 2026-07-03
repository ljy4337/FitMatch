import SwiftUI

struct SatisfactionPicker: View {
    @Binding var value: Int

    var body: some View {
        Picker("만족도", selection: $value) {
            ForEach(1...5, id: \.self) { score in
                Text("\(score)").tag(score)
            }
        }
        .pickerStyle(.segmented)
    }
}
