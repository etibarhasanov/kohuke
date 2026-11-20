# Sending Kohuke to the App Store

There is no packaging workflow here: the bundle Apple takes is made and sent
from Xcode, on a Mac, by the owner. A release is first a merge of `develop`
into `main`, tagged (`CLAUDE.md`, **Branches**); the archive is made from
`main` after that.

**Needs:** a Mac with Xcode 16 or later, and the paid Apple Developer
Program (99 USD a year) on the Apple ID signed into Xcode. The Release
build asks for Sign in with Apple, which a free personal team cannot sign.

---

## Once: the app's record

1. <https://developer.apple.com/account/resources/identifiers/list> → **+** →
   App IDs → App. Description `Kohuke`, Bundle ID explicit,
   `ee.tallinntastebuds.kohuke`, and tick **Sign in with Apple**. (Xcode
   can do this by itself in step 2 below with automatic signing; doing it
   here first means no surprises.)
2. <https://appstoreconnect.apple.com> → **Apps** → **+** → **New App**:

   | Field | What to put |
   | --- | --- |
   | Platforms | iOS |
   | Name | Kohuke (must be free on the whole store; 30 characters at most) |
   | Primary language | English |
   | Bundle ID | `ee.tallinntastebuds.kohuke` from the dropdown |
   | SKU | anything private, e.g. `kohuke-ios` |
   | User access | Full Access |

3. **The website must know this app.** Sign in with Apple hands the site a
   token made for the bundle id `ee.tallinntastebuds.kohuke`; the site
   refuses a token made for an app it was not told about. Check the site's
   Apple setting (`APPLE_APP_ID`, or the list it keeps) includes it before
   the first build reaches anybody.

---

## Each version: make the bundle and send it

1. **Get `main`.** In GitHub Desktop or Terminal, on the `main` branch, after
   the release merge. (Downloading the ZIP of `main` from GitHub also works.)
2. Open `Kohuke.xcodeproj`. Click the blue **Kohuke** project at the top of
   the left column → target **Kohuke** → **Signing & Capabilities**.
   - **Automatically manage signing**: on.
   - **Team**: your paid team — not "(Personal Team)".
   - Xcode shows **Sign in with Apple** under the Release tab; leave it.
3. Still on the target → **General**:
   - **Version** is `MARKETING_VERSION`, the number people see. It was set
     on `develop` before the release merge; leave it.
   - **Build** is `CURRENT_PROJECT_VERSION`. **Every upload needs a higher
     build than the last** — 1, 2, 3 — even for the same version. If an
     upload is refused for a used build number, raise it here and archive
     again. (Commit that change on `develop` afterwards, so the next one
     starts above it.)
4. In the toolbar, set the run destination to **Any iOS Device (arm64)**.
   Archive is greyed out while a simulator is chosen.
5. **Product → Archive.** A few minutes. This is the bundle: an
   `.xcarchive`, signed with the Release configuration.
6. The **Organizer** opens on it. **Distribute App** → **App Store Connect**
   → **Upload** → keep every default → **Upload**.

   If you only want the `.ipa` file to send somewhere: **Distribute App** →
   **App Store Connect** → **Export** instead of Upload, and pick a folder.
   Apple's **Transporter** app (Mac App Store) uploads that file later.

Five to fifteen minutes later the build is in App Store Connect under the
app's **TestFlight** tab, "Processing", then ready. Apple emails if it
refused anything.

---

## Before review: try it through TestFlight

App Store Connect → **TestFlight** → **Internal Testing** → add yourself.
Install **TestFlight** on the iPhone and open the invitation. It is the
build reviewers get. Check on the phone, and once on an iPad, since the app
is offered on both:

- the first open shows **Tere**, and a deck runs to the end;
- a lesson and a song play their sound, with the phone on silent too;
- signing in with Apple, with Google and with a username and password,
  and that progress made on the website shows here;
- Me → **Delete account** works (Apple requires it; say where it is in the
  review notes);
- English, Azerbaijani and Russian all read correctly.

---

## The listing (first time; afterwards only what changed)

On the app's page in App Store Connect, under the version:

- **Screenshots**: the largest iPhone and the largest iPad sizes. Take them
  in the simulator with ⌘S; App Store Connect states the pixel sizes beside
  the upload box. The `screens` artifact of the build workflow is a start.
- **Description, keywords, subtitle, promotional text.**
- **Support URL**: `https://tallinntastebuds.ee/flashcard`.
- **Privacy policy URL**: `https://tallinntastebuds.ee/privacy` — required;
  the app opens the same page from Me → Privacy. Read it first: if it does
  not yet speak of this app, have it say so before submitting.
- **Category**: Education; Reference as secondary.
- **Age rating** questionnaire: answer honestly. Song lyrics and phrases
  at a restaurant (alcohol on a menu) are the questions worth reading twice.
- **App Privacy** questionnaire — it must match
  `Kohuke/PrivacyInfo.xcprivacy`:
  - **Identifiers → User ID**: collected, linked to the user, App
    Functionality. The username, and the number Apple or Google gives the
    site.
  - **User Content → Other User Content**: collected, linked, App
    Functionality. Decks somebody writes, and which words they know.
  - **Tracking**: none. No analytics or advertising in the app.
  - The language and the style stay on the phone and are not collected.
- **Export compliance** is answered in the app
  (`ITSAppUsesNonExemptEncryption = NO`), so it asks nothing.
- **Sign-in for review**: give Apple a username and password of a test
  account on tallinntastebuds.ee, so the reviewer can see the signed-in
  screens.

Then attach the build under **Build**, and **Add for Review** → **Submit**.
Review is usually a day or two.
