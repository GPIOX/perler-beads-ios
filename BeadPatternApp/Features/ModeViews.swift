import BeadPatternCore
import Combine
import SwiftUI

struct PreviewModeView: View {
    @ObservedObject var model: WorkspaceModel
    let grid: PatternGrid

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) { canvas; statistics.frame(width: 260) }
            VStack(spacing: 0) { canvas; statistics.frame(height: 220) }
        }
    }

    private var canvas: some View {
        PatternCanvasRepresentable(
            grid: grid,
            colorStore: model.colorStore,
            colorSystem: model.document.project.settings.colorSystem
        ) { _, _ in }
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var statistics: some View {
        List {
            Section("\(model.totalBeads) 颗 · \(model.statistics.count) 种颜色") {
                ForEach(model.statistics) { item in
                    Button { model.toggleExcluded(item.hex, undoManager: nil) } label: {
                        HStack {
                            ColorSwatch(hex: item.hex)
                            VStack(alignment: .leading) {
                                Text(model.colorStore.code(
                                    for: item.hex,
                                    system: model.document.project.settings.colorSystem
                                ) ?? "?")
                                Text(item.hex).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(item.count) 颗").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.inset)
    }
}

struct EditModeView: View {
    @ObservedObject var model: WorkspaceModel
    let grid: PatternGrid
    let undoManager: UndoManager?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("工具", selection: $model.editorTool) {
                    ForEach(EditorTool.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Button("全局替换", systemImage: "arrow.triangle.2.circlepath") {
                    model.showsReplaceSheet = true
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(model.colorStore.palette) { color in
                        Button {
                            model.selectedPaintHex = color.hex
                            model.editorTool = .paint
                        } label: {
                            ColorSwatch(hex: color.hex, selected: model.selectedPaintHex == color.hex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(model.colorStore.code(
                            for: color.hex,
                            system: model.document.project.settings.colorSystem
                        ) ?? color.hex)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)

            PatternCanvasRepresentable(
                grid: grid,
                colorStore: model.colorStore,
                colorSystem: model.document.project.settings.colorSystem,
                drawingEnabled: true
            ) { row, column in
                model.editCell(row: row, column: column, undoManager: undoManager)
            }
            .background(Color(uiColor: .secondarySystemBackground))
        }
    }
}

struct FocusModeView: View {
    @ObservedObject var model: WorkspaceModel
    let grid: PatternGrid
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: FocusProgress { model.document.project.focusProgress }
    private var currentHex: String? { progress.currentColorHex ?? model.statistics.first?.hex }
    private var recommended: Set<Int> {
        guard let currentHex else { return [] }
        return PatternEditing.recommendedRegion(
            grid: grid,
            hex: currentHex,
            completed: progress.completedCellIndices,
            mode: progress.guidanceMode
        ) ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("当前颜色", selection: currentColorBinding) {
                    ForEach(model.statistics) { item in
                        Text("\(model.colorStore.code(for: item.hex, system: model.document.project.settings.colorSystem) ?? "?") · \(item.count)")
                            .tag(Optional(item.hex))
                    }
                }
                Picker("引导", selection: guidanceBinding) {
                    Text("最近").tag(GuidanceMode.nearest)
                    Text("最大").tag(GuidanceMode.largest)
                    Text("边缘优先").tag(GuidanceMode.edgeFirst)
                }
                Button(progress.isPaused ? "继续" : "暂停", systemImage: progress.isPaused ? "play.fill" : "pause.fill") {
                    model.document.objectWillChange.send()
                    model.document.project.focusProgress.isPaused.toggle()
                }
                Text(formattedTime).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            PatternCanvasRepresentable(
                grid: grid,
                colorStore: model.colorStore,
                colorSystem: model.document.project.settings.colorSystem,
                focusHex: currentHex,
                completed: progress.completedCellIndices,
                highlighted: recommended
            ) { row, column in
                if model.document.project.focusProgress.currentColorHex == nil {
                    model.document.project.focusProgress.currentColorHex = currentHex
                }
                model.toggleFocusRegion(row: row, column: column)
            }
            .background(Color(uiColor: .secondarySystemBackground))

            ProgressView(value: completionFraction)
                .padding()
                .accessibilityLabel("当前颜色完成进度")
        }
        .onAppear {
            if model.document.project.focusProgress.currentColorHex == nil {
                model.document.project.focusProgress.currentColorHex = model.statistics.first?.hex
            }
        }
        .onReceive(timer) { _ in model.tickFocusTimer() }
        .overlay {
            if allCompleted {
                ContentUnavailableView("图纸已完成", systemImage: "party.popper", description: Text("总用时 \(formattedTime)"))
                    .background(.regularMaterial)
            }
        }
    }

    private var currentColorBinding: Binding<String?> {
        Binding(get: { currentHex }, set: {
            model.document.objectWillChange.send()
            model.document.project.focusProgress.currentColorHex = $0
        })
    }

    private var guidanceBinding: Binding<GuidanceMode> {
        Binding(get: { progress.guidanceMode }, set: {
            model.document.objectWillChange.send()
            model.document.project.focusProgress.guidanceMode = $0
        })
    }

    private var completionFraction: Double {
        guard let currentHex else { return 0 }
        let indices = Set(grid.cells.indices.filter { !grid.cells[$0].isExternal && grid.cells[$0].hex == currentHex })
        guard !indices.isEmpty else { return 1 }
        return Double(indices.intersection(progress.completedCellIndices).count) / Double(indices.count)
    }

    private var formattedTime: String {
        let seconds = progress.elapsedSeconds
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    private var allCompleted: Bool {
        grid.cells.indices
            .filter { !grid.cells[$0].isExternal }
            .allSatisfy { progress.completedCellIndices.contains($0) }
    }
}

struct ColorSwatch: View {
    let hex: String
    var selected = false

    var body: some View {
        Circle()
            .fill(Color(hex: hex))
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(selected ? Color.accentColor : .secondary.opacity(0.4), lineWidth: selected ? 4 : 1))
            .padding(2)
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
