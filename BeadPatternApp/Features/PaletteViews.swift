import BeadPatternCore
import SwiftUI

struct PaletteManagerView: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var colors: [PaletteColor] {
        guard !search.isEmpty else { return model.colorStore.palette }
        return model.colorStore.palette.filter { color in
            color.hex.localizedCaseInsensitiveContains(search)
                || (model.colorStore.code(for: color.hex, system: model.document.project.settings.colorSystem) ?? "")
                    .localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92))], spacing: 12) {
                    ForEach(colors) { color in
                        let selected = model.document.project.settings.selectedHexColors.contains(color.hex)
                        Button {
                            model.document.objectWillChange.send()
                            if selected {
                                model.document.project.settings.selectedHexColors.remove(color.hex)
                            } else {
                                model.document.project.settings.selectedHexColors.insert(color.hex)
                            }
                        } label: {
                            VStack(spacing: 5) {
                                ColorSwatch(hex: color.hex, selected: selected)
                                Text(model.colorStore.code(
                                    for: color.hex,
                                    system: model.document.project.settings.colorSystem
                                ) ?? "?")
                                .font(.caption.bold())
                                Text(color.hex).font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .searchable(text: $search, prompt: "搜索色号或 Hex")
            .navigationTitle("色板管理")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("批量操作") {
                        Button("全选") {
                            model.document.project.settings.selectedHexColors = Set(model.colorStore.palette.map(\.hex))
                            model.document.objectWillChange.send()
                        }
                        Button("全不选", role: .destructive) {
                            model.document.project.settings.selectedHexColors.removeAll()
                            model.document.objectWillChange.send()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        model.saveGlobalPaletteDefault()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ColorReplaceView: View {
    @ObservedObject var model: WorkspaceModel
    let undoManager: UndoManager?
    @Environment(\.dismiss) private var dismiss
    @State private var source: String?
    @State private var target: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("源颜色", selection: $source) {
                    Text("请选择").tag(String?.none)
                    ForEach(model.statistics) { item in
                        Text(label(item.hex)).tag(Optional(item.hex))
                    }
                }
                Picker("目标颜色", selection: $target) {
                    Text("请选择").tag(String?.none)
                    ForEach(model.colorStore.palette) { color in
                        Text(label(color.hex)).tag(Optional(color.hex))
                    }
                }
            }
            .navigationTitle("全局替换颜色")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("替换") {
                        if let source, let target {
                            model.replaceColor(sourceHex: source, targetHex: target, undoManager: undoManager)
                            dismiss()
                        }
                    }
                    .disabled(source == nil || target == nil || source == target)
                }
            }
        }
    }

    private func label(_ hex: String) -> String {
        "\(model.colorStore.code(for: hex, system: model.document.project.settings.colorSystem) ?? "?")  \(hex)"
    }
}
