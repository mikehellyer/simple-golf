# Simple-Golf

A modern re-imagining of MicroProse Golf (aka *David Leadbetter's Greens*, 1991),
part of the Simple-* family. Built with [Godot 4](https://godotengine.org) and
released for Linux, macOS and Windows through GitHub Releases, with an in-game
update check.

## Playing

The game opens in the **clubhouse**, a lounge behind the first tee with a
window looking down the hole. From there you can:

- **Members & stats:** join the club (just your name), and look up any
  member's record: rounds and holes played, scoring average, best 18- and
  9-hole rounds, fairways hit, greens in regulation, putts per hole, average
  and longest drive, birdies and eagles, match wins, losses and halves,
  skins won, and their recent rounds. The members' board on the wall ranks
  everyone by scoring average, and the trophy cabinet gains a cup for every
  round a member wins.
- **New round:** pick the format and course, and fill each player slot with
  a club member or a computer golfer.

Stats are kept on each computer (in online games each player's own computer
records their round), and they're saved after every hole.

Up to four players share one computer, taking turns as on a real course.
Everyone tees off in honour order (best score on the previous hole first),
then the ball farthest from the hole plays next. Any player can be a human
or a computer golfer (easy, medium or hard). The computer reads each shot by
simulating it, then mistimes the swing meter and misreads putts like a person.

| Format | Players | How it works |
| --- | --- | --- |
| Stroke play | 1–4 | Fewest strokes over 18 holes |
| Match play | 2 | Win holes; ends early when one player can't be caught (e.g. "3 & 2") |
| Skins | 2–4 | Each hole is worth a skin; ties carry the skin over |
| Fourball | 4 | Two teams of two, own balls, best score counts, match play |
| Foursomes | 4 | Two teams of two sharing a ball, alternate shots, match play |

The setup screen remembers your last line-up. Rounds can be 18, 9 or 3 holes (3 is handy for a quick test).

### Local club and online society

- The **local club** lives on this computer: its members, stats and saved
  courses never leave it.
- The **online society** is a club on a small server, shared with friends.
  Sign in from the clubhouse's **Online society** tab, then create a society
  or join one with an invite code. In each society:
  - **Tournaments:** admins set up an event with a course, a length (18, 9 or
    3 holes), a date window (for example a week) and a rule: either one
    round counts, or the best of any number of rounds. Members play it on
    their own computer whenever suits them, and their card goes straight to
    the leaderboard.
  - **Practice:** solo rounds that count towards practice stats only.
  - **Members & stats:** every member's record, with tournament and
    practice stats kept apart.
  - **Scorecards:** every card is kept and can be viewed again later.
  If the server can't be reached when a round finishes, the card is kept
  and sent the next time you open the society.

To run a society server, see [server/DEPLOY.md](server/DEPLOY.md). It sets up
a free Oracle Cloud machine in about half an hour.

### Courses

Every course is generated from a seed, so a whole course fits in a short code.

- **Real courses:** **Ponte Vedra Stadium** is the real layout of the
  Stadium Course at Sawgrass, Ponte Vedra Beach, Florida: every hole's
  shape, its greens, bunkers and lakes, and the island green on 17. It's
  built from OpenStreetMap data (see below).
- **Random course** gives a fresh course every time.
- **Course of the day** is the same for everyone in the world on a given
  (UTC) date, so you can compare scores with friends.
- **Course codes:** the scorecard at the end of a round shows the course's
  code (`SG-…`). Paste it into the menu's code box to replay that course.
- **Course editor** (Edit… on the menu): step through the holes and change
  each one's par, length, dogleg, green position and size, fairway width,
  hills, water, bunkers, trees and pin position, or roll a new layout. The
  hole updates from above as you edit. Every change sits on top of the
  generated hole, so "Reset hole" always restores it. **Save** keeps the
  course on this computer, and **Copy code** gives you an `SGX-…` code with
  your edits for others to paste in. Saved courses can also be chosen in the
  online lobby.

### Playing online

One player chooses **Host a game**. The lobby shows the address the others
should type into **Join** (port 24680). The host picks the format, adds any
computer players and tees off. In team formats the first two players in the
lobby play the last two.

- On a home network (LAN) it works out of the box.
- Over the internet, the host needs to forward UDP port 24680 on their router
  to their computer.
- Everyone must run the same version; the host turns away mismatches.
- If someone drops out mid-round, the computer takes over their player.

How it works: the host is authoritative. It runs the turn order and the
computer golfers, and checks every shot request. A shot travels as its inputs
(club, aim, power, timing) plus the host's verdict on where the ball finished.
Every machine replays the swing on its meter and simulates the flight locally,
which costs almost no bandwidth, then places the ball exactly where the host
says, so tiny floating-point differences between platforms can never split
the game.

| Key | Action |
| --- | --- |
| ← / → | Aim (hold Shift for fine aim) |
| ↑ / ↓ | Change club |
| Space or left click | Swing: start, set power, set accuracy |
| C | Flight view: Behind, TV, Side, Green or Overhead (each player keeps their own) |
| T / B / [ ] | Tee height, ball position in the stance, move the ball along the tee |
| M | Isometric hole map: click to aim (right-click aims at the flag), Q/E rotate, Space or Proceed to the shot |
| Tab | Scorecard |
| G | Green slope grid on/off (shown when putting) |
| N | Sound on/off |
| R | Re-aim at the pin |
| F | Fullscreen |
| Esc | Cancel a swing; press twice to leave the round |
| U | Open the download page when an update is available |

**The swing meter** works like the original. The first click starts the
backswing. The second click sets power; going past 100% into the red adds
distance but magnifies any timing error. The third click, on the downswing,
should land on the white line. Clicking early pushes and slices the ball to
the right; clicking late pulls and hooks it to the left.

**The hole map:** as in the original, each full shot starts on an
isometric view of the hole. Click where you want to aim and a white arc shows
where a full, pure strike with your club would go; the info panel gives the
"Aim" distance. You can turn this off in **Settings**, and **M** opens the map
at any time.

**Lies:** as in the original, an icon shows how the ball is sitting:
good, fluffy (sitting up in the rough: it flies and runs), poor, very poor,
in a divot, or in the sand (good, poor or plugged after a steep landing).
Each lie changes the strike.

The ball model includes drag, Magnus lift from backspin and sidespin, wind,
bounce and spin-bite on landing, and slope-driven roll. Greens run at about
stimp 10. When you are putting, the HUD reads the green's slope for you, and
an animated grid of dots drifts downhill across the green, coloured from
white-blue (flat) through yellow and orange to red (steep). Trees have solid
trunks as well as canopies, so a ball can rattle around in them.

Every sound (strikes, bounces, the cup rattle, splashes, applause and the
occasional bird out on the course) is synthesised at startup, so there are no
audio assets.

Run with `-- --demo` to watch four computer golfers play a fourball.

### Adding real courses

`tools/import_osm_course.py` turns any golf course that's well mapped in
[OpenStreetMap](https://www.openstreetmap.org) into a course file in
`courses/`. A course is well mapped when each hole is drawn as a line with
its number and par, with greens, tees, bunkers and water as shapes. Fairways
are filled in automatically where they're missing.

```bash
tools/import_osm_course.py --bbox SOUTH,WEST,NORTH,EAST --holes "Course name prefix" \
    --name "Name in the game" --description "Based on ..." --out courses/my-course.json
```

Real courses can't be edited in the course editor, but they work everywhere
else, including online games and society tournaments (everyone's game has
the same course file).

## Licence, privacy and code signing

Simple-Golf is free software under the [MIT licence](LICENSE). The real
course layouts in `courses/` are derived from OpenStreetMap: © OpenStreetMap
contributors, available under the
[Open Database Licence](https://opendatacommons.org/licenses/odbl/). Course
names are neutral; they describe the real course they're based on without
using its trademarks. It collects no
personal data. The only automatic network request is a check with GitHub for
a newer version when the game starts, which you can turn off in **Settings**.
Windows builds are code-signed; see [CODE_SIGNING.md](CODE_SIGNING.md) for the
signing policy and the full privacy statement.

## Installing

Download the latest version from the
[Releases page](https://github.com/mikehellyer/simple-golf/releases):

| Platform | Download |
| --- | --- |
| Linux (Debian, Ubuntu, Pop!_OS…) | `simple-golf_<version>_amd64.deb`, or the `.tar.gz` for other distributions |
| macOS | `Simple-Golf-<version>-macOS.dmg`; drag the app to Applications |
| Windows | `Simple-Golf-<version>-Windows-Setup.exe`, or the portable `.zip` |

The macOS and Windows builds aren't code-signed yet. The first time you open
the game on macOS, right-click it and choose **Open**. On Windows, choose
**More info → Run anyway** in SmartScreen.

## Development

You need Godot 4.7.2. Download the editor from
<https://godotengine.org/download> and open `project.godot`.

Run the tests headlessly:

```bash
godot --headless --import
godot --headless --script res://tests/run_tests.gd
```

The network test starts a host and a client on localhost, lets them play two
holes against a computer golfer, and checks that both logs agree on every shot.
`MODE`, `CPUS` and `PLAYERS` pick other formats; for example, `MODE=4
CPUS=2,3 PLAYERS=4` plays foursomes.

```bash
tests/net_test.sh godot
```

### Layout

- `scripts/core/` holds the game rules, with no rendering code. The ball
  simulation is deterministic, so multiplayer only needs to share each shot's
  launch.
  - `ball_physics.gd`: flight, bounce, roll and cup capture
  - `clubs.gd`: the bag, and turning swing-meter results into launches
  - `scorecard.gd`: one player's card (totals, score relative to par, score names)
  - `competition.gd`: formats, teams, honours, match standing and skins
  - `aim.gd`: club choice, lay-up targets and default aim, shared by humans and the computer
  - `cpu_player.gd`: the computer golfer (plans by simulation, errs by skill level)
  - `player_profiles.gd`: club members and their career stats (`user://members.json`)
  - `hole.gd`: procedural hole generation from a seed (terrain, fairway,
    green, bunkers, water, trees)
  - `surface.gd`: per-surface bounce, friction and roll constants
  - `updater.gd`: GitHub release check (autoload)
- `scripts/game/` holds the presentation: course mesh (`course_view.gd`, with
  a high-resolution green complex), green slope grid, HUD, scorecard view,
  the clubhouse (`clubhouse.gd` builds the room; `clubhouse_menu.gd`,
  `setup_menu.gd` and `members_panel.gd` are its screens), swing meter,
  synthesised sound (`sfx.gd`), and the game loop and cameras.
- `scripts/net/net_session.gd` handles hosting and joining over ENet, plus the
  lobby. The in-game messages are the `net_*` functions in `golf_game.gd`.
- `scripts/net/society_client.gd` talks to the society server, and
  `scripts/game/society_panel.gd` is the Online society tab.
- `server/` is the society server: a small Python (FastAPI + SQLite) web
  service with its own tests (`server/tests`) and deployment files
  (`server/deploy`, `server/DEPLOY.md`).
- `tests/run_tests.gd` is the headless test runner, `tests/net_test.sh` is
  the two-machine network test, and `tests/society_test.sh` runs the game's
  society client against a throwaway local server.

### Releasing

To build every installer without publishing anything, run **Actions →
Release → Run workflow**; the installers appear as downloadable artifacts.

To publish, bump `config/version` in `project.godot`, commit, then tag and push:

```bash
git tag v0.1.0 && git push origin main --tags
```

The release workflow exports all three platforms, builds the .deb, .dmg and
Windows installer (`packaging/`) on their native runners, and attaches them to
the GitHub release. App icons are generated from `icon.svg` by
`tools/generate_icons.gd`.

## Roadmap

1. ~~Single player: terrain, swing meter, ball physics, cameras~~
2. ~~Full scorecard, tree trunks, nicer greens with a slope grid, sound~~
3. ~~Hot-seat for 1–4 players; stroke, match, skins, foursomes and fourball~~
4. ~~Network play: host/join over ENet with a lobby, host-authoritative shots,
   computer takeover when a player drops~~
5. ~~Course editor, course of the day and share codes; .deb/.dmg/Windows
   installer packaging~~
