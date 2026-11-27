# Forever Snapshot

Saves character context for offline advice and shows time since UI load.
Version 1.1.0 adds profession levels and recipe books to snapshot schema 2.

## Capture professions

1. Use `/reload` after installing the update.
2. Open Alchemy and each other crafting profession you want recorded.
   Let the recipe list finish loading.
3. Use `/reload` again to write the collected data to disk.

Profession levels refresh with the ordinary five-second in-memory snapshot and
skill events, including populated secondary-profession slots.
Recipe books refresh when opened or updated while open.
`/fsnap` also attempts to capture the currently open book.
It does not flush SavedVariables to disk.
The game writes the saved file on reload or logout.

The addon does not open windows, change recipe filters, craft items, train skills
or alter professions.
It uses `GetAllRecipeIDs`, so search and category filters do not limit the scan.
Linked, guild and NPC crafting books are rejected.

## Saved fields

Each character snapshot has a `professions` table.

| Field | Meaning |
| --- | --- |
| `levelsCapturedAt` | Unix time of the last successful profession roster |
| `levelsCheckedAt`, `levelsAvailable`, `levelsStatus` | Latest roster attempt and whether it succeeded |
| `entries[skillLineID]` | Profession name, rank, maximum rank, skill modifier and primary/secondary flag |
| `books[skillLineID]` | Last successful scan of this profession's recipe book |
| `lastRecipeScan` | Time and status of the last attempted open-book scan |

Each book records `capturedAt`, `rankAtCapture`, its API source, learned and
unlearned counts, and `recipes[recipeID]`.
Recipe records distinguish `learned = true` from `learned = false` and include
name, difficulty, skill-up eligibility, disabled status and a material-limited
craftable count when the client exposes them.
Optional output IDs, quantities and reagent alternatives are retained when
available; missing schematic data does not invalidate recipe ownership.
The `craftable` API flag is separate from `craftableCount`.
Neither should be interpreted as a live promise after the capture time.

`enumerationComplete` means every ID returned by the client was read.
It does not claim to list every recipe obtainable on the server.
Difficulty enum values are 0 optimal, 1 medium, 2 easy and 3 trivial.
A closed or unopened book is not an empty recipe collection.
Incomplete, empty or failed scans preserve the previous book and its timestamp.
Failed or temporarily empty rosters retain previous levels with
`levelsAvailable = false`; those retained values are stale evidence.
A successful nonempty roster removes books for professions no longer present,
so relearning a profession cannot revive its former recipe collection.
Saved recipe caches are recovered by character GUID across reloads.

## Validation and sources

The local `forever-snapshot-test.lua` mock suite passed before publication.
The mock test covers existing character fields, sparse profession slots,
learned and unlearned recipes, incomplete scans, foreign-book guards, reload
persistence and profession removal.
Live validation requires the reload/open/reload sequence above.

The API choices match the installed TSM and
[`ForeverBags/Character.lua`](https://github.com/Rational-addons-forever/ForeverBags/blob/main/ForeverBags/Character.lua).
Signatures and recipe fields were checked against the
[Forever client API export](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua)
and [Forever profession types](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua).
