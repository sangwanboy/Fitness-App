import Foundation
import Combine

/// Cross-screen channel for queueing a prompt that should be sent to Astra
/// as soon as Coach becomes active. Used by the Predictions card's action
/// chips: tap a chip → bus.queue(prompt) + switch to Coach tab → ChatView
/// consumes it on appearance.
///
/// Singleton because ChatView owns its own ChatViewModel via @StateObject —
/// callers outside Coach can't reach the view model directly.
@MainActor
public final class ChatPrefillBus: ObservableObject {
    public static let shared = ChatPrefillBus()

    /// Set when a chip is tapped; ChatView reads + clears on appearance and
    /// auto-sends the prompt. nil while no prompt is pending.
    @Published public var pendingPrompt: String? = nil

    /// Set when the user taps "Continue in Coach" — pre-fills the composer
    /// WITHOUT auto-sending so the user can review / edit before submitting.
    /// nil while nothing is pending.
    @Published public var composerSeed: String? = nil

    private init() {}

    public func queue(_ prompt: String) {
        pendingPrompt = prompt
    }

    /// Returns the queued prompt and clears the bus atomically so re-renders
    /// of ChatView don't fire the prompt twice.
    public func consume() -> String? {
        let p = pendingPrompt
        pendingPrompt = nil
        return p
    }

    /// Queue text into the composer (no auto-send). ChatView reads + clears.
    public func queueComposerSeed(_ text: String) {
        composerSeed = text
    }

    public func consumeComposerSeed() -> String? {
        let s = composerSeed
        composerSeed = nil
        return s
    }
}
