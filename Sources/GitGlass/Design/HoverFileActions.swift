import SwiftUI
import GitCore

/// 文件行尾的悬停操作（GitHub Desktop 风格）：
/// 平时隐身，悬停该行时浮现「暂存/取消暂存 + 丢弃」，带危险色区分。
struct HoverFileActions: View {
    let file: FileChange
    @Environment(AppState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var confirmDiscard = false

    var body: some View {
        HStack(spacing: 4) {
            if file.isStaged && !file.isUntracked {
                hoverIcon(icon: "minus.circle", tint: GlassPalette.amber,
                          help: "取消暂存 \(file.fileName)") {
                    Task { await state.unstageFile(file) }
                }
            } else {
                hoverIcon(icon: "plus.circle", tint: GlassPalette.mint,
                          help: "暂存 \(file.fileName)") {
                    Task { await state.stageFile(file) }
                }
            }
            if !file.isUntracked {
                hoverIcon(icon: "arrow.uturn.backward", tint: GlassPalette.rose,
                          help: "丢弃 \(file.fileName) 的改动（危险）") {
                    confirmDiscard = true
                }
            }
        }
        .opacity(hovering ? 1 : 0)
        .scaleEffect(hovering ? 1 : 0.85)
        .animation(reduceMotion ? nil : Motion.snappy, value: hovering)
        .onHover { hovering = $0 }
        .confirmationDialog("丢弃「\(file.fileName)」的改动？",
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("丢弃改动", role: .destructive) {
                Task { await state.discardFile(file) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会还原到最近提交/暂存的状态，无法撤销。")
        }
    }

    private func hoverIcon(icon: String, tint: Color, help: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .background(tint.opacity(hovering ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 6))
        .help(help)
    }
}
