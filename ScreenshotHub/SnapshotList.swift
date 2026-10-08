import AppKit
import SwiftUI

struct SnapshotList: View {
    @Binding var document: ScreenshotHubDocument
    @Binding var selection: Set<SnapshotSelection>
    var isPreparingExport: Bool
    var onExportSnapshot: (ScreenshotSnapshot) -> Void
    var onExportSnapshots: ([ScreenshotSnapshot]) -> Void
    var onDeleteSnapshots: (Set<UUID>) -> Void
    var onDeleteSelection: () -> Void
    
    @State private var collapsedGroups: Set<UUID> = []
    @State private var editedGroupID: UUID?
    @State private var groupName = ""
    @State private var showsGroupEditor = false
    
    var body: some View {
        VStack(spacing: 0) {
            SnapshotOutlineList(
                document: $document,
                selection: $selection,
                collapsedGroups: $collapsedGroups,
                isPreparingExport: isPreparingExport,
                onRenameGroup: editGroup,
                onExportSnapshot: onExportSnapshot,
                onExportSnapshots: onExportSnapshots,
                onDeleteSnapshots: onDeleteSnapshots,
                onDeleteSelection: onDeleteSelection
            )
            Divider()
            Button("New Group", systemImage: "folder.badge.plus") { editGroup(nil) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .disabled(isPreparingExport)
        .alert(editedGroupID == nil ? "New Group" : "Rename Group", isPresented: $showsGroupEditor) {
            groupEditorActions
        }
    }
    
    @ViewBuilder
    private var groupEditorActions: some View {
        TextField("Group Name", text: $groupName)
        Button("Cancel", role: .cancel) {}
        Button("Save", action: saveGroup)
            .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    private func saveGroup() {
        if let editedGroupID { document.renameGroup(id: editedGroupID, to: groupName) }
        else { document.createGroup(named: groupName) }
    }
    
    private func editGroup(_ group: ScreenshotGroup?) {
        editedGroupID = group?.id
        groupName = group?.name ?? "Group"
        showsGroupEditor = true
    }
    
    enum SnapshotSelection: Hashable {
        case draft
        case snapshot(UUID)
    }
}
