import Foundation

/// Sends keyboard input, text, pastes, and clicks one message at a time, in the order the user made them.
///
/// Each keystroke of an IME composition corrects what the previous one typed in the guest (`input.text` with
/// `replaceLength`), and every message travels on its own connection. Sent from separate tasks, a Backspace
/// or a click could overtake a pending correction, which then deleted characters the user had already typed.
@MainActor
final class OrderedGuestInput {
    static let shared = OrderedGuestInput()

    private var tail: Task<Void, Never>?

    func enqueue(_ send: @escaping @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await send()
        }
    }
}
