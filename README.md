# ForeverSnapshot

Save character, equipment and profession snapshots for offline use.

Targets WoW Forever interface 16001.

## Install

1. Download the addon ZIP from the [latest release](https://github.com/Rational-addons-forever/ForeverSnapshot/releases/latest).
2. Extract the addon folder into `Interface/AddOns` in your Forever client.
3. Enable the addon in the AddOns list and reload the UI.

The ZIP contains ready-to-install folders. GitHub's automatic source archive
also includes repository documentation; copy only the addon folders from it.

## Use

The HUD shows time since the UI loaded. `/fsnap hide` and `/fsnap show` toggle it.
Snapshots update in memory every five seconds. `/reload` or logout saves them
to `ForeverSnapshot.lua` in your account's SavedVariables directory.
`/fsnap` captures in memory but does not write to disk.

Open each profession you want recorded, allow its recipes to load, then reload.
See the [snapshot format](ForeverSnapshot/README.md) for fields and freshness.
The addon records data locally and has no upload service.
