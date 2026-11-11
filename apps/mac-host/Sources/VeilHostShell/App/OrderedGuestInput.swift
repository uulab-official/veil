import Foundation

/// Sends text input one message at a time, in the order the keys were pressed.
///
/// Each keystroke of an IME composition corrects what the previous one typed in the guest (`input.text` with
/// `replaceLength`), so two messages applied out of order would delete the wrong characters. A separate
/// `Task` per message did not guarantee that order.
@MainActor
final class OrderedTextInput {
    static let shared = OrderedTextInput()

    private var tail: Task<Void, Never>?

    func enqueue(_ send: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await send()
        }
    }
}
