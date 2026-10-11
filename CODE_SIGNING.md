# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io),
certificate by [SignPath Foundation](https://signpath.org).

The Windows builds of Simple-Golf (the game executable and its installer) are
signed. Only binaries built by this repository's GitHub Actions release
workflow, from this repository's source code, are submitted for signing, and
every signing request is approved by hand.

## Team

| Role | Members |
| --- | --- |
| Committers and reviewers | [Mike Hellyer](https://github.com/mikehellyer) |
| Approvers | [Mike Hellyer](https://github.com/mikehellyer) |

## Privacy

Simple-Golf doesn't collect, store or send any personal information.

- **Update check:** when the game starts, it asks GitHub
  (`api.github.com`) whether a newer release of Simple-Golf exists. Nothing
  about you or your computer is sent apart from what any web request reveals
  (your IP address, to GitHub). You can turn this off in the clubhouse under
  **Settings → Check for updates**.
- **Updating:** an update is downloaded from GitHub and installed only when
  you click **Update**.
- **Online play:** the game connects to another computer only when you
  choose to host or join a game, and only exchanges game data (player names,
  shots and scores) with the players in that game.
- **Your data stays on your computer:** club members, statistics, saved
  courses and settings are stored locally and never uploaded.
