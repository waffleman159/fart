# Handoff: continue Shadow Rig on the Windows PC

The plan, design sheets, ATS plugin, BeamNG mod, build and offline tests were made in a cloud
session that could not reach the games. Everything below needs the real games on Windows.
Work through it in order; when a sheet row is confirmed in-game, set its `verified` cell to the
final value (`game`, `tuned`, or `installed`) so `tools/preflight.py` stops listing it.

## Agreed design (from the interview)

- **Mashup:** "ATS Crash Replay" as a **live shadow truck**. The player drives in ATS (primary);
  BeamNG (companion, runs at the same time) keeps a shadow rig at the player's ATS speed.
- **Impact:** when ATS reports a crash, BeamNG places a **matched obstacle** sized by impact speed.
- **Players:** **ATS Convoy friendly** — each Convoy player runs their own shadow rig. No link
  between players' BeamNG copies.
- **First version must have:** **matching rig & load** (T-Series + trailer with ATS cargo weight).
- Not chosen for v1: slow-mo crash cam, crash report card, auto-reset timer (repair-in-ATS respawn
  was added because without it the shadow only works for one crash per session).

## Already confirmed

- Melty: both games exist (`american-truck-simulator`, `beamng-drive`); no loaders for either;
  no existing mashups for either; no anti-cheat/account risk flagged.
- `validate_recipe`: valid, 6 files placed, 0 unmapped. `one_click_check`: **yes** (recipe level).
- SCS SDK 1.15 channel/event names checked against its headers; plugin compiles (MinGW, no warnings),
  exports `scs_telemetry_init` / `scs_telemetry_shutdown`, depends only on KERNEL32, msvcrt, WS2_32.
- Offline tests (`tests/run_tests.sh`) pass: crash/repair detection, JSON messages, BeamNG logic
  against stand-ins.

## Melty listing (agreed with the user)

- Draft created: modId `0fbb62ba-7e3b-4dbd-8253-19939b7e8b62`, slug `shadow-rig`, linked to
  `waffleman159/fart`. Studio: https://melty.gg/studio/0fbb62ba-7e3b-4dbd-8253-19939b7e8b62
- Title **Shadow Rig**; tagline "Crash in American Truck Simulator and your rig wrecks live in
  BeamNG.drive."; description set (update it if testing changes behaviour); licence **MIT**;
  remix **allowed**. No uploads or releases yet; reuse this modId, do not create another draft.

## To check on the PC (open checkboxes)

1. **Find both game folders** (Steam library folders). Confirm ATS has `bin/win_x64/amtrucks.exe`
   and BeamNG has `BeamNG.drive.exe` at its root (`sheets/install.json` → `with_beamng`).
2. **BeamNG user folder.** Find where BeamNG keeps `mods/` on this PC (in-game: Options → Other →
   "Open user folder", or `%LOCALAPPDATA%\BeamNG.drive\`). The recipe currently assumes
   `{localappdata}/BeamNG.drive/current/mods/unpacked/shadowrig` (`install.map_beamng`) — this is the
   riskiest guess. If the folder is versioned (e.g. `0.3x`), find a stable route (a fixed path,
   or launching BeamNG with `-userpath` into a mashup-owned folder) and update the sheet.
3. **Manual install first:** `tools/build.sh`, then unzip `dist/ShadowRig-ATS-*.zip` into
   `<ATS>/bin/win_x64/plugins/` and `dist/ShadowRig-BeamNG-*.zip` into
   `<BeamNG user folder>/mods/unpacked/shadowrig/`.
4. **BeamNG side** (`sheets/beamng_hooks.json`, `rigs.json`, `obstacles.json`, `world.json`):
   start BeamNG, open the console (`~`), check the log has `shadowRig ... listening for ATS`.
   Then verify each hook row: `us_semi` / `dryvan` / `barrier` / `etk800` / `blockwall` spawn,
   `beamstate.activateAutoCoupling()` hitches the trailer, `ai.setSpeed` holds speed in traffic
   mode, `obj:setNodeMass` changes trailer weight, the West Coast USA level path loads.
5. **ATS side** (`ats_channels.json`, `ats_events.json`): start ATS. It shows an
   "advanced SDK features" notice when a plugin is present — note whether it needs a click every
   start (tell the user; it affects the one-click claim). `Documents/American Truck Simulator/game.log.txt`
   should show `[ShadowRig] ready, sending to 127.0.0.1:47750`.
6. **Together:** drive in ATS with BeamNG open; the shadow rig should appear and follow speed.
   Crash at ~25, ~50 and ~90 km/h; confirm barrier / car / wall. Tune `crash_rules.json`
   (thresholds) and mark rows `tuned`. Repair at a service → fresh rig.
7. **Melty install test:** using the draft above, upload both zips, `submit_release`
   with `melty.json` (fileName `*` → version), then press Play in the Melty app and confirm Melty
   installs both parts, starts BeamNG and ATS, and the shadow rig works. Mark `install` rows `installed`.
8. **Convoy:** host a Convoy with a second PC/account, join, confirm each player's shadow rig works.
   Confirm the Convoy player limit for the current ATS version (recipe says 8). Convoy is joined from
   ATS's menus, so the recipe has no `connect` section unless the game log turns out to show an address.
9. **Media:** capture a real screenshot/clip of ATS + BeamNG side by side during a crash
   (game windows only), upload with `add_screenshot` / `finish_screenshot`.
10. Summarise for the user and ask before `publish`.

The Melty token comes from the user's Publish prompt; never write it into this repo.
