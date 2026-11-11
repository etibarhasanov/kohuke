import AuthenticationServices
import CryptoKit
import UIKit

/// The two ways in that are not a password: Google and Apple.
///
/// Either one ends the same way a password does — the site answers with its
/// session cookie, which `URLSession` keeps — and neither leaves anything on
/// the phone but that cookie. What differs is how the site comes to believe
/// who this is.
///
/// GOOGLE is the website's own round trip (`/api/google`), run in the system's
/// sign-in sheet because Google refuses to sign anybody in inside a web view.
/// The sheet is a browser, though, and the cookie the trip ends in would be
/// the browser's and not the app's. So the app asks for the trip with
/// `?app=<challenge>`, and the site ends it at `tallinntastebuds://signin`
/// carrying a ticket instead of a cookie: sealed by the site, good for two
/// minutes, and worth nothing without the verifier the challenge was made
/// from, which never left this phone. `POST /api/account` with
/// `action: ticket` swaps the pair for the session.
///
/// APPLE is the system's own sheet, which hands back a token Apple signed
/// for this app and nobody else. `POST /api/apple` checks the signature
/// against Apple's keys and that the nonce in it is the one made here, and
/// answers as a sign-in does. Nothing is asked of Apple but who this is: no
/// name and no email, the way the site asks Google for `openid` alone.
@MainActor
final class SocialSignIn: NSObject {
    static let shared = SocialSignIn()

    /// Where the Google trip ends. The system's sheet hands a URL with this
    /// scheme back to the app that opened it and to no other, so the scheme
    /// needs no entry in the Info.plist.
    static let scheme = "tallinntastebuds"

    /// Somebody closed the sheet. Not an error, and nothing is said about it.
    struct Cancelled: Error {}

    private var web: ASWebAuthenticationSession?
    private var appleWaiting: CheckedContinuation<ASAuthorization, Error>?

    // MARK: Google

    /// The ticket the site ended the trip with, and the verifier that makes
    /// it worth something.
    func google() async throws -> (ticket: String, verifier: String) {
        let verifier = Self.random(32)
        let challenge = Self.base64url(Data(SHA256.hash(data: Data(verifier.utf8))))
        let start = API.url("api/google", ["app": challenge])

        let back: URL = try await withCheckedThrowingContinuation { waiting in
            let session = ASWebAuthenticationSession(url: start, callbackURLScheme: Self.scheme) { url, error in
                if let url {
                    waiting.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    waiting.resume(throwing: Cancelled())
                } else {
                    waiting.resume(throwing: API.Refusal(code: "google", status: 0))
                }
            }
            session.presentationContextProvider = self
            // The browser's own cookies, so somebody already signed in to
            // Google in Safari is not asked for their password again.
            session.prefersEphemeralWebBrowserSession = false
            web = session
            if !session.start() {
                waiting.resume(throwing: API.Refusal(code: "google", status: 0))
            }
        }
        web = nil

        let items = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let ticket = items.first(where: { $0.name == "ticket" })?.value, !ticket.isEmpty {
            return (ticket, verifier)
        }
        // Cancel on Google's own screen comes back with nothing at all.
        if items.contains(where: { $0.name == "google" }) {
            throw API.Refusal(code: "google", status: 0)
        }
        throw Cancelled()
    }

    // MARK: Apple

    /// Apple's signed token for this app, and the nonce it was asked for with.
    func apple() async throws -> (token: String, nonce: String) {
        let nonce = Self.random(32)
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()

        let answer: ASAuthorization = try await withCheckedThrowingContinuation { waiting in
            appleWaiting = waiting
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        guard let credential = answer.credential as? ASAuthorizationAppleIDCredential,
              let data = credential.identityToken,
              let token = String(data: data, encoding: .utf8) else {
            throw API.Refusal(code: "apple", status: 0)
        }
        return (token, nonce)
    }

    // MARK: Pieces

    private static func random(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64url(Data(bytes))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private var window: UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first ?? UIWindow()
    }
}

extension SocialSignIn: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { window }
}

extension SocialSignIn: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor { window }
}

extension SocialSignIn: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        appleWaiting?.resume(returning: authorization)
        appleWaiting = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            appleWaiting?.resume(throwing: Cancelled())
        } else {
            appleWaiting?.resume(throwing: API.Refusal(code: "apple", status: 0))
        }
        appleWaiting = nil
    }
}
