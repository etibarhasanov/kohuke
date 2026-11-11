import Foundation

/// The one door to tallinntastebuds.ee.
///
/// Kohuke has no server of its own. It is the flashcards of Tallinn Tastebuds
/// (`tallinntastebuds.ee/flashcard`) drawn natively, and everything it shows
/// is an answer from the Functions that page itself calls: `/api/flashcard`
/// for the decks, the lessons, the songs, the conversations and what somebody
/// knows of them, `/api/say` for the voice, and `/api/account`, `/api/google`
/// and `/api/apple` for who is asking. A deck added on the site is in the app
/// the moment the site deploys, with nothing submitted to Apple.
///
/// Requests go through one `URLSession` whose cookie store is the system's.
/// The website's session is an HttpOnly cookie (`ttb_s`), and a native
/// session keeps and sends it by itself, so an account here is the website's
/// account and what it knows on one is known on the other.
enum API {
    static let base = URL(string: "https://tallinntastebuds.ee")!

    enum Failure: Error {
        case status(Int)
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// A URL on the site, with an optional query.
    static func url(_ path: String, _ query: [String: String] = [:]) -> URL {
        var parts = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return parts.url!
    }

    /// The bytes of a path and the status they came with. A 404 from
    /// `/api/flashcard` still carries a body worth reading, so the status is
    /// handed back rather than thrown.
    static func fetch(_ path: String, _ query: [String: String] = [:]) async throws -> (Data, Int) {
        var request = URLRequest(url: url(path, query))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 200)
    }

    /// The bytes of a path, or a thrown error for anything but a 2xx.
    static func data(_ path: String, _ query: [String: String] = [:]) async throws -> Data {
        let (data, status) = try await fetch(path, query)
        guard (200..<300).contains(status) else { throw Failure.status(status) }
        return data
    }

    /// What a Function said when it refused: its `error` word ("taken",
    /// "no-match", "signed-out") and the status it came with.
    struct Refusal: Error {
        let code: String
        let status: Int
    }

    /// A JSON POST, the way the website's own pages send one. Answers the
    /// bytes that came back, or throws a `Refusal` carrying the route's own
    /// word for what went wrong, which the screens turn into the site's own
    /// sentence.
    @discardableResult
    static func post(_ path: String, _ body: [String: Any]) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            throw Refusal(code: object["error"] as? String ?? "status-\(http.statusCode)", status: http.statusCode)
        }
        return data
    }

    /// The same, read as a loose object, for the account routes whose answers
    /// are two or three fields.
    static func postObject(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        let data = try await post(path, body)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    // The addresses the website shares, so a link opened from the app lands
    // on the same thing in a browser.
    static let site = URL(string: "https://flashcard.tallinntastebuds.ee")!
    static let privacy = base.appendingPathComponent("privacy")
}
