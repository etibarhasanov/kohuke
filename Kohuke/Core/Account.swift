import Foundation

/// Signing in and out.
///
/// An account here is the website's account and nothing else: a username and
/// a password, checked by `/api/account`, and a session the site hands back
/// as its HttpOnly cookie. `URLSession`'s shared cookie store keeps that
/// cookie across launches the way a browser would, so the app holds no token
/// of its own, and somebody with an account on tallinntastebuds.ee already
/// has one here.
///
/// Google and Apple are the other two ways in, and end in the same cookie:
/// `SocialSignIn` says how. Their buttons are drawn only where the site says
/// it can answer them (`appGoogle` and `appApple` on `GET /api/account`).
///
/// Whichever way somebody comes in, the answers the phone was holding go
/// with them and the shelf is asked for again, since it is theirs now.
extension Store {
    /// Ask the site who this cookie belongs to, and which doors it offers.
    func whoAmI() async {
        if let data = try? await API.data("api/account"),
           let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            user = object["user"] as? String
            googleOffered = object["appGoogle"] as? Bool ?? false
            appleOffered = object["appApple"] as? Bool ?? false
            #if DEBUG
            if LaunchScript.doors { googleOffered = true; appleOffered = true }
            #endif
        }
        // Offline, whoever the last shelf said this was is still believed, so
        // a signed-in reader on a train is not shown a sign-in form.
        checked = true
    }

    /// Sign in, or make the account first. Throws the route's refusal.
    func enter(username: String, password: String, create: Bool) async throws {
        let answer = try await API.postObject("api/account", [
            "action": create ? "create" : "login",
            "username": username,
            "password": password
        ])
        await arrive(answer)
    }

    /// Sign in through Google, making the account if this Google account has
    /// never been here. Throws `SocialSignIn.Cancelled` for a closed sheet.
    func enterWithGoogle() async throws {
        let trip = try await SocialSignIn.shared.google()
        let answer = try await API.postObject("api/account", [
            "action": "ticket",
            "ticket": trip.ticket,
            "verifier": trip.verifier
        ])
        await arrive(answer)
    }

    /// The same through Apple.
    func enterWithApple() async throws {
        let proof = try await SocialSignIn.shared.apple()
        let answer = try await API.postObject("api/apple", ["token": proof.token, "nonce": proof.nonce])
        await arrive(answer)
    }

    private func arrive(_ answer: [String: Any]) async {
        user = answer["user"] as? String
        await sendKept()
        await refresh()
    }

    func signOut() async {
        _ = try? await API.post("api/account", ["action": "logout"])
        await leave()
    }

    /// Delete the account for good. The site asks for the password again, or,
    /// for an account that never had one, the username typed out.
    func deleteAccount(confirmation: String) async throws {
        try await API.post("api/account", ["action": "delete", "current": confirmation, "username": confirmation])
        await leave()
    }

    private func leave() async {
        user = nil
        if let cookies = HTTPCookieStorage.shared.cookies(for: API.base) {
            for cookie in cookies where cookie.name == "ttb_s" { HTTPCookieStorage.shared.deleteCookie(cookie) }
        }
        Disk.forget()
        await refresh()
    }
}
