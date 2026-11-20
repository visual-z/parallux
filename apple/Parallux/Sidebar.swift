import ParalluxKit
import SwiftUI

/// The main window's sidebar as design v0.2 draws it: accent-coloured icons
/// and an accent-tinted background on the selected item. Values and a
/// binding only, so it can be rendered on its own.
///
/// The list itself stays the system's sidebar list (glass, section headers,
/// scrolling). The selection is drawn here because the system's sidebar
/// highlight is grey and cannot be tinted;
/// arrow keys are wired back with onMoveCommand.
struct SidebarList: View {
    @Binding var selection: SidebarItem?
    let badge: (SidebarItem) -> Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { section in
                if let title = section.title {
                    Section(title) { rows(section) }
                } else {
                    Section { rows(section) }
                }
            }
        }
        .listStyle(.sidebar)
        .focusable()
        .focusEffectDisabled()
        .onMoveCommand(perform: move)
    }

    private func rows(_ section: SidebarSection) -> some View {
        ForEach(section.items) { item in
            let selected = item == selection
            Button {
                selection = item
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.symbol).foregroundStyle(.tint).frame(width: 20)
                    Text(item.title)
                    Spacer(minLength: 4)
                    let count = badge(item)
                    if count > 0 {
                        Text("\(count)").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .padding(.horizontal, 8).frame(height: 28)
                // The design's `--sel`: 14% of the accent on light, 26% on dark.
                .background(selected ? AnyShapeStyle(.tint.opacity(scheme == .dark ? 0.26 : 0.14)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            .listRowSeparator(.hidden)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    /// Up and down move through the items in display order, stopping at the ends.
    private func move(_ direction: MoveCommandDirection) {
        let items = SidebarItem.allCases
        guard let current = selection, let index = items.firstIndex(of: current) else { return selection = items.first }
        switch direction {
        case .up where index > 0: selection = items[index - 1]
        case .down where index < items.count - 1: selection = items[index + 1]
        default: break
        }
    }
}
