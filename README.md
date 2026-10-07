# Shadow Rig — American Truck Simulator × BeamNG.drive

You drive your truck in **American Truck Simulator**. Alongside it, **BeamNG.drive** runs a
shadow copy of your rig: a T-Series semi towing a dry van, loaded with the real weight of your
current ATS cargo, cruising a BeamNG freeway at your ATS speed. When you crash in ATS, the shadow
truck takes the same hit in BeamNG's soft-body physics, live.

> Status: **v0.1.0, built and tested offline only — not yet tested in the running games.**
> See [HANDOFF.md](HANDOFF.md) for what still has to be checked on a Windows PC with both games.

## What players get

- **ATS is the game you play.** A small telemetry plugin (built on SCS Software's official
  Telemetry SDK) reads your truck's speed, g-forces, wear/damage, trailer and job cargo from ATS.
- **BeamNG brings its physics and vehicles.** The BeamNG mod spawns BeamNG's own T-Series and dry
  van trailer from your BeamNG install, adds your ATS cargo weight to the trailer, and keeps the
  truck in lane at your ATS speed with BeamNG's AI driver.
- **Crashes carry over.** When ATS registers an impact (a sudden speed drop or g-spike plus a jump
  in damage, or an ATS crash fine), BeamNG drops an obstacle in front of the shadow truck, sized to
  how fast you hit: a barrier under 35 km/h, a parked car up to 70 km/h, a concrete wall above.
- **Repairs carry over.** Repair your truck at an ATS service and the wrecked shadow rig is replaced
  with a fresh one. Drop your trailer in ATS and the shadow truck runs bobtail.
- **Play solo or with friends in ATS Convoy.** Convoy is ATS's own multiplayer (up to 8 players,
  hosted and joined from ATS's menus). Each player runs their own shadow rig in their own BeamNG.

Nothing from either game is shipped: the plugin reads ATS live, and the BeamNG mod uses the
vehicles and map from the player's own BeamNG install.

## Games needed

- American Truck Simulator (Windows, 64-bit) — the game you play.
- BeamNG.drive — runs at the same time, alongside ATS.

## How it fits together

```
ATS (amtrucks.exe)                         BeamNG.drive
  bin/win_x64/plugins/shadow_rig.dll  -->  mods/unpacked/shadowrig (Lua extension "shadowRig")
  SCS Telemetry SDK channels/events  UDP   spawns us_semi + dryvan, AI at ATS speed,
  crash + repair detection         127.0.0.1:47750  obstacles on crash, respawn on repair
```

## The sheets are the source of truth

Everything the mashup touches is a row in `sheets/*.json`:

| sheet | one row is |
|---|---|
| `ats_channels` | a live ATS telemetry channel the plugin reads |
| `ats_events` | an attribute pulled from an ATS configuration/gameplay event |
| `crash_rules` | a threshold/constant for crash and repair detection |
| `protocol` | a field in a message from the plugin to BeamNG |
| `obstacles` | an impact tier and the BeamNG object it spawns |
| `rigs` | a BeamNG vehicle in the shadow rig |
| `world` | a BeamNG setting (map, timings) |
| `beamng_hooks` | a BeamNG API call or callback the mod uses |
| `install` | an entry in the Melty install recipe |

`tools/gen.py` turns them into `ats_plugin/generated/sheet_data.h`,
`beamng_mod/lua/ge/extensions/shadowRig/sheetData.lua` and `melty.json`. Change the sheet, not the
generated code. Every cell's `verified` column is a checkbox; `tools/preflight.py` lists every
unfilled cell, every broken reference between sheets, and every row not yet verified in the game.

## Build and test

```
tools/build.sh 0.1.0      # preflight -> generate -> compile plugin (MinGW) -> dist/*.zip
tests/run_tests.sh        # offline tests: crash detector, message format, BeamNG logic with stand-ins
```

Needs `python3`, `x86_64-w64-mingw32-g++`, `g++`, `lua5.1`, `zip`, `curl`, `unzip`.

## Credits and licences

- SCS Telemetry SDK © 2016 SCS Software, MIT-style licence (included in the ATS package as
  `shadow_rig_SCS_SDK_LICENSE.txt`). Downloaded at build time from SCS.
- American Truck Simulator © SCS Software; BeamNG.drive © BeamNG GmbH. No game files are included.
- Shadow Rig code: licence to be chosen by the author.
