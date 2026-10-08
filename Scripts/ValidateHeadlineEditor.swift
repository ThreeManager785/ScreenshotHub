import AppKit
import SwiftUI
import Observation
    
@Observable
@MainActor
private final class EditorState {
    var text = "截图🙂 "
    var selection = NSRange(location: 5, length: 0)
    var revision = 0
    var isDark = false
}
    
private struct EditorFixture: View {
    @Bindable var state: EditorState
    
    var body: some View {
        VStack {
            HeadlineEditor(text: $state.text, selection: $state.selection)
            Text("Revision \(state.revision)")
        }
        .environment(\.colorScheme, state.isDark ? .dark : .light)
    }
}
    
@main
struct ValidateHeadlineEditor {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let state = EditorState()
        let host = NSHostingView(rootView: EditorFixture(state: state))
        host.sizingOptions = []
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 160),
                              styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = host
        func refresh() {
            state.revision += 1
            host.rootView = .init(state: state)
            window.layoutIfNeeded()
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        func textView(in view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView { return editor }
            return view.subviews.lazy.compactMap { textView(in: $0) }.first
        }
        refresh()
        let editor = textView(in: host)!
        window.makeFirstResponder(editor)
        let unspecified = NSRange(location: NSNotFound, length: 0)
        let original = state.text
        let originalSelection = state.selection
        precondition(editor.string == original && editor.selectedRange() == originalSelection)
        editor.setMarkedText("zhong", selectedRange: .init(location: 5, length: 0), replacementRange: unspecified)
        editor.didChangeText()
        precondition(editor.hasMarkedText() && state.text == original && state.selection == originalSelection,
                     "Unconfirmed pinyin and its temporary selection must not enter the screenshot model.")
        let marked = editor.markedRange()
        let composingSelection = editor.selectedRange()
        state.isDark = true
        refresh()
        precondition(editor.string == original + "zhong" && editor.hasMarkedText()
                     && editor.markedRange() == marked && editor.selectedRange() == composingSelection,
                     "SwiftUI and appearance updates must preserve the IME composition and candidate selection.")
        editor.setMarkedText("zhongwen", selectedRange: .init(location: 8, length: 0), replacementRange: unspecified)
        window.setContentSize(.init(width: 480, height: 180))
        refresh()
        precondition(editor.string == original + "zhongwen" && editor.hasMarkedText() && state.text == original)
        editor.insertText("中文", replacementRange: unspecified)
        refresh()
        precondition(!editor.hasMarkedText() && state.text == original + "中文" && editor.string == state.text,
                     "Confirming a Chinese candidate must publish the committed text exactly once.")
        precondition(state.selection == .init(location: (state.text as NSString).length, length: 0),
                     "The committed cursor must use UTF-16 positions, including the preceding emoji.")
        state.selection = (state.text as NSString).range(of: "中文")
        refresh()
        precondition(editor.selectedRange() == state.selection)
        let selectedText = state.text
        let selectedRange = state.selection
        editor.setMarkedText("wenben", selectedRange: .init(location: 6, length: 0), replacementRange: unspecified)
        refresh()
        precondition(editor.hasMarkedText() && state.text == selectedText && state.selection == selectedRange,
                     "Composing over selected text must preserve the committed highlight until confirmation.")
        editor.insertText("文本", replacementRange: unspecified)
        refresh()
        precondition(state.text == original + "文本" && editor.string == state.text)
        editor.setMarkedText(NSAttributedString(string: "你好"), selectedRange: .init(location: 1, length: 1),
                             replacementRange: unspecified)
        refresh()
        precondition(editor.hasMarkedText() && state.text == original + "文本")
        editor.unmarkText()
        refresh()
        precondition(state.text == original + "文本你好" && !editor.hasMarkedText(),
                     "Finishing composition through unmarkText must also publish the candidate.")
        let beforeCancellation = state.text
        editor.setMarkedText("quxiao", selectedRange: .init(location: 6, length: 0), replacementRange: unspecified)
        refresh()
        editor.insertText("", replacementRange: unspecified)
        refresh()
        precondition(state.text == beforeCancellation && editor.string == beforeCancellation && !editor.hasMarkedText(),
                     "Discarding unconfirmed input must not leave pinyin in the model.")
        editor.insertText("\n下一行ABC", replacementRange: unspecified)
        refresh()
        precondition(state.text == beforeCancellation + "\n下一行ABC" && editor.string == state.text)
        editor.setMarkedText("jiu", selectedRange: .init(location: 3, length: 0), replacementRange: unspecified)
        state.text = "新截图 🧑🏽‍💻"
        state.selection = (state.text as NSString).range(of: "新截图")
        refresh()
        precondition(editor.string == "新截图 🧑🏽‍💻" && state.text == editor.string && !editor.hasMarkedText()
                     && editor.selectedRange() == state.selection,
                     "Switching the bound screenshot must discard old composition without committing into the new screenshot.")
        editor.insertText("标题", replacementRange: unspecified)
        refresh()
        precondition(state.text == "标题 🧑🏽‍💻")
        state.selection = (state.text as NSString).range(of: "🧑🏽‍💻")
        refresh()
        precondition(editor.selectedRange() == state.selection && state.selection.length == 7)
        window.contentView = nil
        print("Validated native IME composition across SwiftUI updates, appearance and resize changes, candidate confirmation, selected-text replacement, unmarking, cancellation, multiline editing, screenshot switching, and UTF-16 highlights.")
    }
}
