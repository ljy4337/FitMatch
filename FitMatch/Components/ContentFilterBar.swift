import SwiftUI

enum ContentListLayout: String {
    case list
    case grid

    var systemImage: String {
        switch self {
        case .list:
            return "list.bullet"
        case .grid:
            return "square.grid.2x2"
        }
    }

    mutating func toggle() {
        self = self == .list ? .grid : .list
    }
}

struct ContentFilterBar: View {
    let filters: [ContentFilterItem]
    @Binding var layout: ContentListLayout

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { item in
                    Menu {
                        ForEach(item.options) { option in
                            Button {
                                item.onSelect(option.id)
                            } label: {
                                if option.id == item.selectedID {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(item.selectedTitle)
                                .font(.caption.weight(.bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(.primary)
                        .frame(height: 34)
                        .padding(.horizontal, 12)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    layout.toggle()
                } label: {
                    Image(systemName: layout.systemImage)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 34)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("보기 방식 변경")
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(Color(.systemBackground))
    }
}

struct ContentFilterItem: Identifiable {
    let id: String
    let selectedID: String
    let selectedTitle: String
    let options: [ContentFilterOption]
    let onSelect: (String) -> Void
}

struct ContentFilterOption: Identifiable {
    let id: String
    let title: String
}
