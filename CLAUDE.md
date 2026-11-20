# Working on Kohuke

## Branches: develop is where the work goes, main is what was released

- **`develop` is where all ordinary work lands.** Branch from it, open pull
  requests into it, rebase onto it. A session's own branch is cut from
  `develop`, never from `main`.
- **`main` is the default branch and holds only releases.** Nothing is
  committed to it directly and no feature branch is merged into it. When the
  owner says a version is ready and names its number, `MARKETING_VERSION` in
  `Kohuke.xcodeproj/project.pbxproj` (Debug and Release both) is set to that
  number and committed on `develop`, `develop` is merged into `main`
  (`git merge --no-ff develop -m "Release <number>"`), and the merge is
  tagged `v<number>`. The version number is the owner's to choose; a session
  does not pick one.
- How to make the bundle in Xcode and send it to Apple: `docs/RELEASING.md`.
- `main` and `develop` both started from `main`'s last commit on 2026-11-20.
