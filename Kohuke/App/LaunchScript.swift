import Foundation

/// Opens the app on a given tab and screen, for the screenshots CI takes.
///
/// Nobody can look at a simulator from a cloud session, so the build workflow
/// launches the app several times with launch arguments and photographs what
/// it draws — `-kTab 2 -kOpen song:naera-naera` opens the Songs tab with that
/// song pushed. Launch arguments land in UserDefaults' argument domain, so
/// nothing is stored and nothing here runs for a reader, who never launches
/// the app with arguments. `-lang az` and `-style plum` are the keys the app
/// keeps those two choices under, so they need nothing here.
enum LaunchScript {
    static var tab: Int { UserDefaults.standard.integer(forKey: "kTab") }

    /// The screens to push onto the given tab's stack at launch.
    static func routes(tab index: Int) -> [Route] {
        guard index == tab, let open = UserDefaults.standard.string(forKey: "kOpen") else { return [] }
        return open.split(separator: ",").compactMap { part in
            let bits = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard bits.count == 2 else { return nil }
            switch bits[0] {
            case "deck": return .deck(bits[1])
            case "lesson": return .lesson(bits[1])
            case "song": return .song(bits[1])
            case "talk": return .talk(bits[1])
            default: return nil
            }
        }
    }

    /// `-kTurned YES` opens a deck on the back of its first card.
    static var turned: Bool { UserDefaults.standard.bool(forKey: "kTurned") }
    /// `-kWord <word>` presses that word in a song or a conversation.
    static var word: String? { UserDefaults.standard.string(forKey: "kWord") }
    /// `-kSheet signin` opens the sign-in sheet over the first screen.
    static var sheet: String? { UserDefaults.standard.string(forKey: "kSheet") }
    /// `-kDoors YES` draws the Apple and Google buttons on the sign-in sheet
    /// whatever the site says it offers, so they can be photographed. Debug
    /// builds only; pressing one still asks the site, which answers as it does.
    #if DEBUG
    static var doors: Bool { UserDefaults.standard.bool(forKey: "kDoors") }
    #endif
}
