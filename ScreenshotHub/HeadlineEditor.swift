import AppKit
import SwiftUI
    
struct HeadlineEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    
    @Environment(\.colorScheme) private var colorScheme
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        let editor = scrollView.documentView as! NSTextView
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.font = .systemFont(ofSize: 14)
        editor.textColor = .labelColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = .init(width: 9, height: 10)
        editor.autoresizingMask = [.width]
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        updateSelectionAppearance(editor, context: context)
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scrollView.documentView as? NSTextView else { return }
        // Preserve composition unless a different bound headline replaces the committed text.
        if editor.hasMarkedText(), text == context.coordinator.synchronizedText { return }
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }
        if editor.hasMarkedText() {
            editor.inputContext?.discardMarkedText()
            editor.unmarkText()
        }
        updateSelectionAppearance(editor, context: context)
        if editor.string != text { editor.string = text }
        context.coordinator.synchronizedText = text
        if selection.location <= (text as NSString).length,
           selection.length <= (text as NSString).length - selection.location,
           editor.selectedRange() != selection {
            editor.setSelectedRange(selection)
        }
    }
    
    func makeCoordinator() -> Coordinator { .init(parent: self) }
    
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        // Text wrapping changes the document size, but must not resize the scroll viewport.
        proposal.viewportSize(idealSize: .init(width: 280, height: 108))
    }
    
    private func updateSelectionAppearance(_ editor: NSTextView, context: Context) {
        guard context.coordinator.appliedColorScheme != colorScheme else { return }
        editor.selectedTextAttributes = [
            .backgroundColor: colorScheme == .dark
                ? NSColor(srgbRed: 0.24, green: 0.43, blue: 0.76, alpha: 1)
                : NSColor.selectedTextBackgroundColor,
            .foregroundColor: colorScheme == .dark ? NSColor.white : NSColor.selectedTextColor
        ]
        context.coordinator.appliedColorScheme = colorScheme
    }
    
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HeadlineEditor
        var synchronizedText: String
        
        init(parent: HeadlineEditor) {
            self.parent = parent
            synchronizedText = parent.text
        }
        
        var isUpdating = false
        var appliedColorScheme: ColorScheme?
        
        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let editor = notification.object as? NSTextView, !editor.hasMarkedText() else { return }
            synchronizedText = editor.string
            parent.text = editor.string
            parent.selection = editor.selectedRange()
        }
        
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, let editor = notification.object as? NSTextView, !editor.hasMarkedText(),
                  editor.string == synchronizedText, parent.text == synchronizedText else { return }
            parent.selection = editor.selectedRange()
        }
    }
}
