import SwiftUI
#if canImport(UIKit)
import UIKit

public struct MarkdownTextView: UIViewRepresentable {
    @Binding public var text: String
    public var onSlashTrigger: (() -> Void)?

    public init(text: Binding<String>, onSlashTrigger: (() -> Void)? = nil) {
        self._text = text
        self.onSlashTrigger = onSlashTrigger
    }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.alwaysBounceVertical = true
        return view
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSlashTrigger: onSlashTrigger)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        let onSlashTrigger: (() -> Void)?

        init(text: Binding<String>, onSlashTrigger: (() -> Void)?) {
            self._text = text
            self.onSlashTrigger = onSlashTrigger
        }

        public func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            if textView.text.last == "/" {
                onSlashTrigger?()
            }
        }
    }
}
#else
public struct MarkdownTextView: View {
    @Binding public var text: String
    public var onSlashTrigger: (() -> Void)?

    public init(text: Binding<String>, onSlashTrigger: (() -> Void)? = nil) {
        self._text = text
        self.onSlashTrigger = onSlashTrigger
    }

    public var body: some View {
        TextEditor(text: $text)
            .onChange(of: text) { _, newValue in
                if newValue.last == "/" {
                    onSlashTrigger?()
                }
            }
    }
}
#endif
