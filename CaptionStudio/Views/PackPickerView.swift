import SwiftUI

/// Horizontal pack picker shown in the editor chrome / export panel.
struct PackPickerView: View {
    @EnvironmentObject private var editor: EditorViewModel
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            HStack {
                Text("Shorts Pack")
                    .font(.custom("AvenirNext-DemiBold", size: compact ? 11 : 13))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                if let pack = editor.selectedPack {
                    Text(pack.name)
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(pack.accent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    packChip(nil, title: "None", icon: "circle.slash", accent: .white.opacity(0.45))
                    ForEach(editor.packs.packs) { pack in
                        packChip(pack.id, title: pack.name, icon: pack.icon, accent: pack.accent)
                    }
                }
            }
        }
    }

    private func packChip(_ id: String?, title: String, icon: String, accent: Color) -> some View {
        let selected = editor.project.packId == id
        return Button {
            editor.selectPack(id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: compact ? 11 : 12))
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 7 : 9)
            .background(
                selected ? accent.opacity(0.95) : Color.white.opacity(0.08),
                in: Capsule()
            )
            .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(.plain)
    }
}
