# Kohuke

Estonian, one card at a time. The iPhone and iPad app for the flashcards of
[Tallinn Tastebuds](https://tallinntastebuds.ee/flashcard), for people who
read English, Azerbaijani or Russian.

A kohuke is the chocolate-glazed curd bar every shop in Estonia sells: small,
sweet, and gone in three bites, which is about the size of a sitting here.

SwiftUI, iOS 17 and later, no third-party dependencies.

---

## What it is, and what it is not

**It is an interface.** Kohuke has no server and no database of its own. It
asks tallinntastebuds.ee for everything it shows, through the same Functions
the website's own flashcards page calls, so:

- a deck, a lesson, a song or a conversation added on the website is in the
  app the next time it is opened, with nothing submitted to Apple;
- an account is the website's account. Somebody who signed up on
  tallinntastebuds.ee signs in here with the same name, and the words they
  know on one are known on the other;
- the words on every screen are the website's own strings, in the language
  being read, so a sentence fixed there is fixed here.

**It is a different application** from the Tallinn Tastebuds app
(`etibarhasanov/TallinnTasteBudsApp`), which is the map. That one is about
where to eat; this one is about being able to read the menu when you get
there. They share a backend and nothing else: a different bundle id
(`ee.tallinntastebuds.kohuke`), a different icon, a different listing.

## What it does

Five tabs.

- **Words.** The decks, under the site's four headings. *First words* and
  *At a restaurant* are open to everybody; *Getting by* opens at a hundred
  words known and *Going deeper* at four hundred, and a stage that has not
  opened is its heading and one line saying how far off it is. **Start** at
  the top goes back to whatever was left half done — a deck, a lesson, a
  song or a conversation — and otherwise to the first deck with cards
  waiting. Above the headings, once there is anything in them, stand the two
  decks that are gathered rather than written: *Words you missed* and *Words
  you know*. Below them, signed in, the decks you wrote yourself and a field
  to name a new one. Signed in, a deck's row says how many cards are due, in
  the accent, or how many are known, with a rule under its name filled to
  that; within each heading the decks with cards due go first and a finished
  one sinks. Anything added in the last fortnight says **New**. The shelf
  opens with *Welcome back*, or how many days in a row, or how long it has
  been.
- **The first time**, the Words tab is not a shelf. It is **Tere**, the first
  card of *Hello and goodbye*, the way the website greets a stranger: one
  card shows what the app does better than forty decks to choose from.
- **Grammar.** Short lessons on why the words change, each followed by its
  own deck where it has one, and the cases one by one under a heading of
  their own. A lesson is prose, tables of forms and example sentences; every
  form and every sentence can be heard.
- **Songs.** An Estonian song with its recording, then every line with what
  it means under it. Any word can be pressed for what it means, its
  dictionary form, and which deck teaches it. Each song is followed by the
  deck of its own words.
- **Conversations.** Sheets from a language course: a question and the turns
  that answer it, a sentence at a time, translated, every word pressable and
  every sentence spoken.
- **Share**, at the top of any deck, lesson, song or conversation the site
  ships, sends its address on the website, so whoever gets it can open it in
  a browser without the app.
- **Me.** Signing in or making an account — Apple, Google, or a username and
  a password — signing out, deleting the account; the language the cards are
  turned over into; the colour, which is one of the website's four styles.

### A deck

The card shows the Estonian. A tap turns it over to what it means, with the
three forms where the word is a noun, how a case form is built where the card
teaches one, and the word in a sentence where it has one. Then it is one of
two answers, by button or by pushing the card off to the side: **Knew it** to
the right, **Show me again** to the left. A card got wrong comes round once
more before the run ends. **Give me a hint** shows the first letters of the
meaning; **Undo** takes the last answer back; **Hear it** says the word, and
on the back the sentence too; **Something is wrong here** reports a card to
the site.

The rules of a run are the website's, kept in `Core/Run.swift` so a deck goes
the same way on the phone as on the page.

### Signed out

Anybody can read the shelves, the lessons, the songs and the conversations.
The first five cards a phone answers are kept on the phone; after that the
run asks for an account, because flashcards only work if something remembers
which ones you knew. Signing in sends the five along.

### Off the network

The shelf and everything that has been opened are kept on the phone, so a
deck opened once can be read on a plane. Answers given there are not kept
for later: what a lost answer costs is the card coming round again.

---

## What it asks the website for

All of it is in `Kohuke/Core/API.swift`, `Store.swift`, `Account.swift` and
`Voice.swift`. These are promises the website keeps to an installed app that
cannot be updated in a day, and they are listed in the website repository's
`CLAUDE.md` under **What the app reads**.

| | |
|---|---|
| `GET /api/flashcard?lang=&ui=<prefixes>` | the shelf: decks, lessons, songs, conversations, how many words are known, who is asking, and the strings the app prints (`ui`, only the keys starting with `Store.uiPrefixes`) |
| `GET /api/flashcard?lang=&deck=<id>&ui=` | one deck with its cards, or one lesson, song or conversation, whole, and no strings |
| `POST /api/flashcard` | `knew`, `again`, `reset`, `report`, and for a deck of your own `deck`, `rename`, `drop`, `card`, `editcard`, `uncard` |
| `GET /api/say?take=&text=` | the Estonian voice, as a WAV |
| `GET /api/account` | who the session is, and `appGoogle` / `appApple` |
| `POST /api/account` | `login`, `create`, `ticket`, `logout`, `delete` |
| `GET /api/google?app=<challenge>` | the Google round trip, ending at `tallinntastebuds://signin` |
| `POST /api/apple` | Apple's token and its nonce, answered as a sign-in |

**It asks for what it shows, when it shows it.** The shelf is one request
and carries only counts — how many cards a deck has, not the cards. A deck,
a lesson, a song or a conversation is asked for when it is opened, and not
before; nothing downloads the whole of the website's decks. The strings come
with the shelf and only the ones the app prints, two hundred of the site's
twelve hundred — `?ui=` on the route, whose list of key prefixes is
`Store.uiPrefixes` — and a deck comes with none. That made the shelf a third
of the size it was and a deck four KB instead of seventy. A screen that
starts printing a key outside those prefixes shows its English until the
prefix is added.

**Sign in with Apple needs the website to know this app.** Apple signs its
token for a bundle id, and the website refuses one made for an app it does
not name. `functions/api/_apple.js` there lists the ids it accepts; this
app's is `ee.tallinntastebuds.kohuke`.

---

## The code

```
Kohuke/
  App/      KohukeApp.swift     the app and its five tabs
            LaunchScript.swift  launch arguments, for CI's screenshots
  Core/     API.swift           the one door to the website
            Store.swift         who, which language, the shelf, the answers
            Account.swift       signing in and out
            SocialSignIn.swift  Google and Apple
            Run.swift           one sitting with one deck
            Voice.swift         the speaker
            Disk.swift          what is kept between launches
  Models/   Flash.swift         the shapes /api/flashcard answers in
  Views/    Shelves.swift       the four shelves
            RunView.swift       a deck, one card at a time
            DeckEditor.swift    the words of a deck of your own
            Reading.swift       a lesson, a song, a conversation
            MeTab.swift         the account, the language, the colour
            SignInView.swift    the sign-in sheet
            Pieces.swift        rows, the speaker, a line of pressable words
            Theme.swift         the website's four styles
  Seed/     app-strings.json    the few strings only an app needs, en/az/ru
```

`Kohuke/` is a synchronised group: a file put in the folder is in the build,
with nothing to add to the project.

**The strings.** A screen asks for a sentence by the website's key with the
English beside it — `store.t("flashKnew", "Knew it")`. The website's answer
carries its strings for the language being read; the English is what shows
before the first answer arrives. A string the website does not have goes in
`Seed/app-strings.json`, in all three languages, and CI checks that.

## Building it

Open `Kohuke.xcodeproj` in Xcode 16 or later and press Run. The simulator
needs no Apple account. On a phone, choose your team under Signing &
Capabilities; the Debug configuration asks for no capabilities, so a free
personal team will do. Sign in with Apple is in the Release configuration
only, which needs a paid developer account.

There is nothing to install and nothing to configure: the app talks to the
live website.

### CI

`.github/workflows/ios.yml` builds for the simulator on every push, then
launches the app on each screen worth seeing and photographs it. The
pictures are the run's `screens` artifact, and for a `claude/` branch they
are also pushed, shrunk, to the `ci-screens` branch, which is how a session
with no Mac sees what it built.

### The icon

`docs/icon.html` is the icon, drawn. Photograph it at 1024 × 1024 with any
headless browser and save it over
`Kohuke/Assets.xcassets/AppIcon.appiconset/icon-1024.png`.
