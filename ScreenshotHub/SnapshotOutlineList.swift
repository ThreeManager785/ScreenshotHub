import AppKit
import SwiftUI

struct SnapshotOutlineList: NSViewRepresentable {
    static let pasteboardType = NSPasteboard.PasteboardType("com.memz233.screenshothub.snapshot")
    
    @Binding var document: ScreenshotHubDocument
    @Binding var selection: Set<SnapshotList.SnapshotSelection>
    @Binding var collapsedGroups: Set<UUID>
    var isPreparingExport: Bool
    var onRenameGroup: (ScreenshotGroup) -> Void
    var onExportSnapshot: (ScreenshotSnapshot) -> Void
    var onExportSnapshots: ([ScreenshotSnapshot]) -> Void
    var onDeleteSnapshots: (Set<UUID>) -> Void
    var onDeleteSelection: () -> Void
    
    func makeCoordinator() -> Coordinator { .init(self) }
    
    func makeNSView(context: Context) -> NSScrollView {
        let outline = OutlineView()
        let column = NSTableColumn(identifier: .init("Snapshots"))
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.style = .sourceList
        outline.allowsMultipleSelection = true
        outline.allowsEmptySelection = true
        outline.autoresizingMask = [.width]
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.indentationPerLevel = 16
        outline.intercellSpacing = .init(width: 0, height: 2)
        outline.dataSource = context.coordinator
        outline.delegate = context.coordinator
        outline.coordinator = context.coordinator
        outline.registerForDraggedTypes([Self.pasteboardType])
        outline.setDraggingSourceOperationMask(.move, forLocal: true)
        outline.setDraggingSourceOperationMask([], forLocal: false)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = outline
        context.coordinator.outline = outline
        context.coordinator.update(self)
        return scroll
    }
    
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(self)
    }
    
    final class Coordinator: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {
        var parent: SnapshotOutlineList
        weak var outline: OutlineView?
        private var items: [Kind: Item] = [:]
        private var snapshots: [ScreenshotSnapshot] = []
        private var groups: [ScreenshotGroup] = []
        private var isUpdating = false
        
        init(_ parent: SnapshotOutlineList) { self.parent = parent }
        
        func update(_ parent: SnapshotOutlineList) {
            self.parent = parent
            guard let outline else { return }
            outline.isEnabled = !parent.isPreparingExport
            isUpdating = true
            defer { isUpdating = false }
            if snapshots != parent.document.snapshots || groups != parent.document.groups || outline.numberOfRows == 0 {
                snapshots = parent.document.snapshots
                groups = parent.document.groups
                outline.reloadData()
            }
            for group in parent.document.groups {
                let item = item(.group(group.id))
                if parent.collapsedGroups.contains(group.id) { outline.collapseItem(item) }
                else { outline.expandItem(item) }
            }
            let indices = IndexSet((0..<outline.numberOfRows).filter { row in
                guard let item = outline.item(atRow: row) as? Item, let selection = item.selection else { return false }
                return parent.selection.contains(selection)
            })
            if outline.selectedRowIndexes != indices {
                outline.selectRowIndexes(indices, byExtendingSelection: false)
            }
        }
        
        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            children(of: item as? Item).count
        }
        
        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            children(of: item as? Item)[index]
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? Item)?.groupID != nil
        }
        
        func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
            (item as? Item)?.snapshotID == nil ? 32 : 68
        }
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? Item else { return nil }
            if let id = item.snapshotID, let snapshot = parent.document.snapshots.first(where: { $0.id == id }) {
                let identifier = NSUserInterfaceItemIdentifier("Snapshot")
                let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? SnapshotCell ?? SnapshotCell()
                cell.identifier = identifier
                cell.host.rootView = .init(snapshot: snapshot,
                                           frameImages: parent.document.frames[snapshot.configuration.frameID],
                                           watchFrameImages: parent.document.frames[snapshot.configuration.watch.frameID])
                return cell
            }
            let identifier = NSUserInterfaceItemIdentifier("Folder")
            let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? FolderCell ?? FolderCell()
            cell.identifier = identifier
            if let id = item.groupID, let group = parent.document.groups.first(where: { $0.id == id }) {
                cell.textField?.stringValue = group.name
                cell.imageView?.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                cell.count.stringValue = String(parent.document.snapshots(in: id).count)
            } else {
                cell.textField?.stringValue = "Draft"
                cell.imageView?.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
                cell.count.stringValue = ""
            }
            return cell
        }
        
        func outlineView(_ outlineView: NSOutlineView, selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet) -> IndexSet {
            guard !parent.isPreparingExport else { return outlineView.selectedRowIndexes }
            let selectable = proposedSelectionIndexes.filter { (outlineView.item(atRow: $0) as? Item)?.selection != nil }
            let snapshots = selectable.filter { (outlineView.item(atRow: $0) as? Item)?.snapshotID != nil }
            return IndexSet(snapshots.isEmpty ? selectable : snapshots)
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let outline else { return }
            parent.selection = Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? Item)?.selection })
        }
        
        func outlineViewItemDidExpand(_ notification: Notification) {
            guard !isUpdating, let item = notification.userInfo?["NSObject"] as? Item, let id = item.groupID else { return }
            parent.collapsedGroups.remove(id)
        }
        
        func outlineViewItemDidCollapse(_ notification: Notification) {
            guard !isUpdating, let item = notification.userInfo?["NSObject"] as? Item, let id = item.groupID else { return }
            parent.collapsedGroups.insert(id)
        }
        
        func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard !parent.isPreparingExport, let id = (item as? Item)?.snapshotID,
                  let data = try? JSONEncoder().encode([id]) else { return nil }
            let writer = NSPasteboardItem()
            writer.setData(data, forType: SnapshotOutlineList.pasteboardType)
            return writer
        }
        
        func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard !parent.isPreparingExport, let ids = draggedIDs(from: info.draggingPasteboard),
                  let destination = destination(item: item as? Item, index: index),
                  destination.beforeID.map({ !ids.contains($0) }) ?? true else { return [] }
            let target = item as? Item
            if target?.groupID == nil || index != NSOutlineViewDropOnItemIndex {
                let group = destination.groupID.map { self.item(.group($0)) }
                let children = children(of: group)
                let position = destination.beforeID.flatMap { id in children.firstIndex { $0.snapshotID == id } }
                    ?? (group == nil ? parent.document.snapshots(in: nil).count + 1 : children.count)
                outlineView.setDropItem(group, dropChildIndex: position)
            }
            return .move
        }
        
        func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard !parent.isPreparingExport, let ids = draggedIDs(from: info.draggingPasteboard),
                  let destination = destination(item: item as? Item, index: index),
                  parent.document.moveSnapshots(ids: ids, to: destination.groupID, before: destination.beforeID) else { return false }
            if let id = destination.groupID { parent.collapsedGroups.remove(id) }
            update(parent)
            return true
        }
        
        func menu(for item: Item) -> NSMenu? {
            guard !parent.isPreparingExport else { return nil }
            let menu = NSMenu()
            menu.autoenablesItems = false
            if let id = item.groupID, let group = parent.document.groups.first(where: { $0.id == id }) {
                add("Rename Group…", to: menu) { self.parent.onRenameGroup(group) }
                let snapshots = parent.document.snapshots(in: id)
                add("Export Group…", to: menu, enabled: !snapshots.isEmpty) { self.parent.onExportSnapshots(snapshots) }
                add("Delete Group", to: menu) {
                    self.parent.document.deleteGroup(id: id)
                    self.parent.collapsedGroups.remove(id)
                }
            } else if let id = item.snapshotID, let snapshot = parent.document.snapshots.first(where: { $0.id == id }) {
                let snapshots = parent.selection.contains(.snapshot(id))
                    ? parent.document.orderedSnapshots.filter { parent.selection.contains(.snapshot($0.id)) } : [snapshot]
                let ids = Set(snapshots.map(\.id))
                add(snapshots.count > 1 ? "Export Selected Snapshots…" : "Export PNG…", to: menu) {
                    if snapshots.count == 1 { self.parent.onExportSnapshot(snapshot) }
                    else { self.parent.onExportSnapshots(snapshots) }
                }
                let move = NSMenuItem(title: "Move to Group", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                add("Top Level", to: submenu) { self.parent.document.moveSnapshots(ids: ids, to: nil) }
                for group in parent.document.groups {
                    add(group.name, to: submenu) { self.parent.document.moveSnapshots(ids: ids, to: group.id) }
                }
                move.submenu = submenu
                menu.addItem(move)
                add(snapshots.count > 1 ? "Delete Selected Snapshots" : "Delete Snapshot", to: menu) { self.parent.onDeleteSnapshots(ids) }
            }
            return menu.items.isEmpty ? nil : menu
        }
        
        private func add(_ title: String, to menu: NSMenu, enabled: Bool = true, action: @escaping () -> Void) {
            let handler = MenuAction(action)
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            item.target = handler
            item.representedObject = handler
            item.isEnabled = enabled
            menu.addItem(item)
        }
        
        private func item(_ kind: Kind) -> Item {
            if let item = items[kind] { return item }
            let item = Item(kind)
            items[kind] = item
            return item
        }
        
        private func children(of item: Item?) -> [Item] {
            if let id = item?.groupID { return parent.document.snapshots(in: id).map { self.item(.snapshot($0.id)) } }
            guard item == nil else { return [] }
            return [self.item(.draft)] + parent.document.snapshots(in: nil).map { self.item(.snapshot($0.id)) }
                + parent.document.groups.map { self.item(.group($0.id)) }
        }
        
        private func draggedIDs(from pasteboard: NSPasteboard) -> Set<UUID>? {
            var ids: Set<UUID> = []
            for item in pasteboard.pasteboardItems ?? [] {
                guard let data = item.data(forType: SnapshotOutlineList.pasteboardType),
                      let values = try? JSONDecoder().decode([UUID].self, from: data) else { return nil }
                ids.formUnion(values)
            }
            return !ids.isEmpty && ids.isSubset(of: Set(parent.document.snapshots.map(\.id))) ? ids : nil
        }
        
        private func destination(item: Item?, index: Int) -> Destination? {
            if let id = item?.snapshotID {
                guard let snapshot = parent.document.snapshots.first(where: { $0.id == id }) else { return nil }
                return .init(groupID: snapshot.groupID, beforeID: id)
            }
            if let id = item?.groupID {
                guard parent.document.groups.contains(where: { $0.id == id }) else { return nil }
                let snapshots = parent.document.snapshots(in: id)
                return .init(groupID: id, beforeID: snapshots.indices.contains(index) ? snapshots[index].id : nil)
            }
            let snapshots = parent.document.snapshots(in: nil)
            let position = item == nil && index != NSOutlineViewDropOnItemIndex ? max(0, index - 1) : snapshots.count
            return .init(groupID: nil, beforeID: snapshots.indices.contains(position) ? snapshots[position].id : nil)
        }
    }
    
    final class OutlineView: NSOutlineView {
        weak var coordinator: Coordinator?
        
        override func menu(for event: NSEvent) -> NSMenu? {
            let row = row(at: convert(event.locationInWindow, from: nil))
            guard row >= 0, let item = item(atRow: row) as? Item else { return nil }
            return coordinator?.menu(for: item)
        }
        
        override func selectAll(_ sender: Any?) {
            selectRowIndexes(IndexSet((0..<numberOfRows).filter { (item(atRow: $0) as? Item)?.snapshotID != nil }),
                             byExtendingSelection: false)
        }
        
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 {
                if coordinator?.parent.isPreparingExport == false { coordinator?.parent.onDeleteSelection() }
            } else { super.keyDown(with: event) }
        }
    }
    
    final class Item: NSObject {
        let kind: Kind
        
        init(_ kind: Kind) { self.kind = kind }
        
        var groupID: UUID? { if case .group(let id) = kind { id } else { nil } }
        var snapshotID: UUID? { if case .snapshot(let id) = kind { id } else { nil } }
        var selection: SnapshotList.SnapshotSelection? {
            switch kind {
            case .draft: .draft
            case .snapshot(let id): .snapshot(id)
            case .group: nil
            }
        }
    }
    
    enum Kind: Hashable {
        case draft
        case group(UUID)
        case snapshot(UUID)
    }
    
    private struct Destination {
        var groupID: UUID?
        var beforeID: UUID?
    }
    
    private final class MenuAction: NSObject {
        let action: () -> Void
        
        init(_ action: @escaping () -> Void) { self.action = action }
        
        @objc func run() { action() }
    }
    
    private final class PassiveHostingView: NSHostingView<SnapshotRow> {
        // Keep selection and drag initiation in the outline view.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    
    private final class SnapshotCell: NSTableCellView {
        let host = PassiveHostingView(rootView: .init(snapshot: .init(name: "", configuration: .init(), screenshotData: .init(), sourceName: ""),
                                                    frameImages: nil))
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            host.sizingOptions = []
            host.translatesAutoresizingMaskIntoConstraints = false
            addSubview(host)
            NSLayoutConstraint.activate([
                host.leadingAnchor.constraint(equalTo: leadingAnchor),
                host.trailingAnchor.constraint(equalTo: trailingAnchor),
                host.topAnchor.constraint(equalTo: topAnchor),
                host.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }
        
        required init?(coder: NSCoder) { nil }
    }
    
    private final class FolderCell: NSTableCellView {
        let count = NSTextField(labelWithString: "")
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let image = NSImageView()
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            count.textColor = .secondaryLabelColor
            imageView = image
            textField = label
            for view in [image, label, count] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            NSLayoutConstraint.activate([
                image.leadingAnchor.constraint(equalTo: leadingAnchor),
                image.centerYAnchor.constraint(equalTo: centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 18),
                image.heightAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -6),
                count.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
                count.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
        
        required init?(coder: NSCoder) { nil }
    }
}
