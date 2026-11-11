import SwiftUI
import GitCore

/// UI 层统一文件节点，可同时用于「工作区变更」与「某条提交里的变更」。
struct FileTreeNode: Identifiable, Hashable {
    var path: String
    var status: String
    var oldPath: String? = nil

    var id: String { status + ":" + path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String {
        let dir = (path as NSString).deletingLastPathComponent
        return dir.isEmpty || dir == "." ? "仓库根目录" : dir
    }
    var badge: String {
        switch status {
        case "A", "?": return "新增"
        case "M": return "修改"
        case "D": return "删除"
        case "R": return "重命名"
        case "C": return "复制"
        default: return status
        }
    }
    var tint: Color {
        switch status {
        case "A", "?": return GlassPalette.mint
        case "D": return GlassPalette.rose
        case "R", "C": return GlassPalette.violet
        default: return GlassPalette.blue
        }
    }
}

extension ChangedFile {
    var treeNode: FileTreeNode { FileTreeNode(path: path, status: status, oldPath: oldPath) }
}

extension FileChange {
    var treeNode: FileTreeNode {
        let code = isUntracked ? "?" : (isStaged ? indexStatus : worktreeStatus)
        return FileTreeNode(path: path, status: code.trimmingCharacters(in: .whitespaces).isEmpty ? "M" : code,
                            oldPath: oldPath)
    }
}

/// 按目录折叠的文件树：路径层级一眼可见，比平铺列表更适合大仓库。
struct FileTreeView: View {
    let nodes: [FileTreeNode]
    var selectedPath: String? = nil
    var compact = false
    var onSelect: ((FileTreeNode) -> Void)? = nil

    @State private var collapsed: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [(key: String, items: [FileTreeNode])] {
        let dictionary = Dictionary(grouping: nodes, by: \.directory)
        return dictionary.keys.sorted().map { key in
            (key, (dictionary[key] ?? []).sorted { $0.fileName < $1.fileName })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 6) {
            ForEach(groups, id: \.key) { group in
                DisclosureGroup(isExpanded: expansion(for: group.key)) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.items) { node in
                            fileRow(node)
                        }
                    }
                    .padding(.leading, 4)
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(GlassPalette.blue.opacity(0.85))
                        Text(group.key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text("\(group.items.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
                .animation(reduceMotion ? nil : Motion.snappy, value: collapsed)
            }
        }
        .onChange(of: nodes.map(\.id).joined(separator: "|")) { _, _ in
            collapsed = []
        }
    }

    private func expansion(for key: String) -> Binding<Bool> {
        Binding(
            get: { !collapsed.contains(key) },
            set: { expanded in
                withComfortableAnimation(reduceMotion) {
                    if expanded { collapsed.remove(key) } else { collapsed.insert(key) }
                }
            }
        )
    }

    private func fileRow(_ node: FileTreeNode) -> some View {
        let selected = selectedPath == node.path
        return Button {
            onSelect?(node)
        } label: {
            HStack(spacing: 7) {
                Text(node.badge)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(node.tint)
                    .frame(width: 32, alignment: .leading)
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.fileName)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                    if let oldPath = node.oldPath, oldPath != node.path {
                        Text("原：\((oldPath as NSString).lastPathComponent)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(GlassPalette.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, compact ? 4 : 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            selected ? GlassPalette.accent.opacity(0.10) : Color.primary.opacity(0.025),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .help(node.path)
        .animation(Motion.snappy, value: selected)
    }
}
