# Packaging Kohuke

Two workflows, two jobs:

| Workflow | Runs | Makes |
| --- | --- | --- |
| `build` (`.github/workflows/ios.yml`) | every push to `main` or `claude/**`, every pull request | a simulator build and the screenshots — proof it compiles, nothing installable |
| `package` (`.github/workflows/release.yml`) | only when asked | a signed `.ipa`, sent to TestFlight unless told not to |

A push never makes a package. There are two ways to ask for one.

**From the Actions tab.** Actions → **package** → **Run workflow**, pick the
branch, and leave **Send the build to TestFlight** ticked. Untick it for an
`.ipa` that stays on the run as an artifact for 30 days and goes nowhere
else. This is the way to put a build from a branch on your own phone before
it lands.

**With a tag.** A tag that starts with `v` packages that commit and sends it
to TestFlight, and the tag becomes the version people see:

```bash
git tag v1.2
```

```bash
git push origin v1.2
```

The build number is `BUILD_NUMBER_BASE` (100, at the top of the workflow)
plus the run number, so it only goes up. Without a tag, the version is the
`MARKETING_VERSION` in the project.

## The four secrets, once

The workflow signs with Xcode's automatic signing and an App Store Connect
API key, so there is no certificate or profile to export or renew. It needs
four repository secrets — GitHub → the repository → **Settings → Secrets and
variables → Actions → New repository secret**. The same four values work in
all three app repositories (Tallinn Taste Buds, Kohuke and Rattatee).

1. **`APPLE_TEAM_ID`** — the ten characters under **Membership details** at
   <https://developer.apple.com/account>.
2. In App Store Connect → **Users and Access → Integrations → App Store
   Connect API → Team Keys**, press **+**, name it `GitHub`, give it the
   **Admin** role (automatic signing has to be allowed to create the
   distribution certificate; App Manager cannot), and **Generate**.
   - **`ASC_ISSUER_ID`** — the Issuer ID shown above the list of keys.
   - **`ASC_KEY_ID`** — the new key's Key ID.
   - **`ASC_KEY_P8`** — press **Download API Key**, open the `.p8` file in a
     text editor, and paste the whole of it, the `BEGIN` and `END` lines
     included. Apple lets you download it once.

The app's record has to exist in App Store Connect before the first upload
(bundle id `ee.tallinntastebuds.kohuke`); `docs/` says how where it covers the listing.

If the run stops at **Check the signing secrets are set**, one of the four
is missing, and the error names it.
