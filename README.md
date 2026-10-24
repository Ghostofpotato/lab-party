# Lab Party

A grim little party game by **Grim Intern**. Up to 8 test subjects go through a
rotation of short, lethal minigames in a run-down facility. You score by
placement, and the first subject to reach the target score survives the program.

Built with **Godot 4.5**. Runs on Windows and Linux; LAN multiplayer plus bots.

## Download
Grab the latest build from [Releases](../../releases/latest):
- `LabParty-Windows.exe` (Windows 10/11, 64-bit)
- `LabParty-Linux.x86_64` (`chmod +x` it first)

The game updates itself: when a new release is out, the main menu offers
**UPDATE NOW**.

## Play
- **Practice:** you + 5 bots.
- **Host a lab:** others pick **Join** and type the host's LAN IP. The host chooses
  the test rotation and points to win, then presses **Begin testing**.
- WASD to move, SPACE to act, mouse where a test needs aiming. F11 toggles
  fullscreen, F3 shows FPS. The **Graphics** button sets the quality level.
- **Wardrobe:** customise your subject. Common, rare, epic and legendary items
  unlock from wins and challenges.

## 21 tests
Minefield, Duck Hunt, Duck Hunt Classic, Firearm Factory, Table Manners, Tunnel
Hazard, Inside Job, Smoke Break, Chisel Gauntlet, The Filter, Forklift Certified,
Stable Footing, Quick Draw, Lethal Rebound, Wrong Way, Spine Breaker, Seat
Assignment, Roomba Rampage, Short Fuse, Live Wire, Gas Chamber.

## Build from source
1. Install Godot 4.5 (standard build) and its export templates.
2. `godot --path .` to run, or open the folder in the editor.
3. Export: `godot --headless --path . --export-release "Windows Desktop" build/LabParty.exe`
   (presets in `export_presets.cfg`).

## Layout
```
autoloads/   globals, game manager, fx, graphics quality, updater, profile
net/         NetworkManager + swappable transport backends (ENet)
framework/   minigame base classes, round director
minigames/   one folder per test
player/      networked player body and the animated character
ui/          menus, lobby, wardrobe
intro/       studio intro
tools/       test harnesses and release scripts
```

## Code signing policy
Windows builds are signed. Free code signing provided by [SignPath.io](https://about.signpath.io),
certificate by [SignPath Foundation](https://signpath.org) (application in review; until then
builds carry the project's own Grim Intern signature).
- Committers and approvers: [Ghostofpotato](https://github.com/Ghostofpotato)
- Builds come straight from this repository through GitHub Actions.

## Privacy
The game sends no personal data anywhere. It only contacts GitHub to check for a newer
release, and the other players you choose to host or join over your network.

## License
Code: MIT (see `LICENSE`). Third-party assets keep their own licenses, see `CREDITS.md`.
