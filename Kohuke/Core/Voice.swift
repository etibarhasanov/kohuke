import AVFoundation
import Observation

/// The Estonian, said aloud.
///
/// The sound is nobody's file. The website's `/api/say` asks the University
/// of Tartu's Estonian voice for the words and Cloudflare keeps what comes
/// back, so the second person to press Tere hears it from the edge. It will
/// say exactly what the site's decks, lessons, songs and conversations hold
/// and nothing else, which is why a deck somebody typed has no speaker.
///
/// One voice for the whole app: a press on the one that is sounding stops
/// it, and a press on another starts that one instead. Whatever goes wrong —
/// the voice is down, the phone is offline — ends the same way: quiet, and
/// `failed` set for the screen to say one line about. Nothing waits on this.
@MainActor
@Observable
final class Voice: NSObject, AVAudioPlayerDelegate {
    static let shared = Voice()

    enum Now { case quiet, loading, playing }

    /// What is being said, and whether it is still on its way.
    private(set) var text = ""
    private(set) var now = Now.quiet
    /// Set when the voice did not answer; the screen that shows it clears it.
    var failed = false

    /// Which recording of a word to ask for: `SAY_TAKE` in the website's
    /// `assets/flashcard.js`, which goes up whenever the voice or its pace
    /// changes so that a month of cache does not keep the old one.
    private static let take = "2"

    private var player: AVAudioPlayer?
    private var token = 0

    func saying(_ words: String) -> Now { words == text ? now : .quiet }

    func say(_ words: String) {
        if text == words && now != .quiet { hush(); return }
        hush()
        text = words
        now = .loading
        token += 1
        let mine = token
        Task {
            do {
                let data = try await API.data("api/say", ["take": Self.take, "text": words])
                guard mine == token else { return }
                // Heard even with the ringer off: somebody who pressed a
                // speaker in a language app wants the sound.
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                let player = try AVAudioPlayer(data: data)
                player.delegate = self
                self.player = player
                guard player.play() else { throw API.Failure.status(0) }
                now = .playing
            } catch {
                guard mine == token else { return }
                hush()
                failed = true
            }
        }
    }

    func hush() {
        token += 1
        player?.stop()
        player = nil
        text = ""
        now = .quiet
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player { self.hush() }
        }
    }
}
