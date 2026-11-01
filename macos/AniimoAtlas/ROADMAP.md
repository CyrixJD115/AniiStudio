# Aniimo Atlas roadmap

## Next priority — live placement and saved combos (October 25)

Implementation underway; installed progress and remaining acceptance are recorded below:

- Replace the build-only placement preview with the player's actual live 3D scene for each zone: Production, Residential, and Seasonal. Include current furniture, real area transforms, terrain and unlocked boundaries; show capture freshness and missing-model coverage. An offline snapshot must be clearly identified as historical.
- Let the user drag and drop the complete build onto that map, rotate it as one unit, and preview its real scale and footprint. Preserve every relative block position; no coordinate typing or manual block assembly should be necessary.
- Check current ownership, missing-piece prices/materials, area eligibility, capacity, boundaries, and collisions at the chosen location; revalidate immediately before a game change.
- Offer two explicit destinations in the app: **Place in Homeland** or **Save to in-game Combos**. Direct placement must retain whole-build identity so all imported pieces can be selected and moved together.
- Investigate the game's normal saved-combo API to add a generated or selected build directly to the game's build menu without typing a code. This is separate from Atlas local favorites, local layout files, and temporary multi-selection. Do not claim this is implemented or a permanent group merely because selection works.
- Account for the user's reported **15 saved combos at a time**: verify the live limit and how slots are counted, display occupied/available slots, and let the user choose a replacement only when necessary. Never silently delete or overwrite a saved combo. This slot limit is distinct from per-build piece limits.
- Keep the full purchase → placement preview → direct place / saved-combo flow inside Atlas. No website or code entry should be required for the generated Apple design or native import path.
- Acceptance: demonstrate accurate scene context in each supported zone; drag-drop and move a whole build without including nearby items; independently verify placement/group identity and leave-return/restart persistence; demonstrate a genuine game-menu saved combo and full-slot handling. Preserve existing builds and avoid duplicate purchases/imports.

Current verified checkpoint: the 408-block Golden Gate Apple was placed in Residential and all 408 exact block IDs were selected together through the normal editor; Kevin visually confirmed both. A permanent saved-game combo/group has **not** been created. See `Research/2026-10-25/golden-gate-apple/RESULT.md` at the workspace root. Older roadmap status paragraphs below predate this checkpoint.

## Installed placement and combo update — October 25, late evening

- Installed and restarted normal AniimoAtlas.app; deep strict signature verification passed. 125 Swift tests passed with 6 optional skips, zero failures. Log: /tmp/atlas-all-zones-combos-tests.log.
- Requirements sheet now has a sticky action footer and explicit Place in Homeland / Save to in-game Combos destinations. Already-imported Apple no longer invites a duplicate purchase/import. Its receipt restores Residential and offers Select whole build in game.
- Whole-build selection V4 uses exact imported IDs after user movement, supports areas 0/1/2, refuses unrelated selection and requires the normal game Multi-Select panel. Earlier exact Apple408 selection remains user-confirmed; new GUI refuses correctly while panel closed. No new selection/movement dispatched in this update.
- Native live Residential map visibly loaded: 4151/4153 records rendered, 2 models missing, unlocked plot outlines displayed. Initial refresh failed after restart; explicit retry succeeded. Refresh failures need further reliability work; do not describe as continuous live streaming.
- Production/Residential/Seasonal capture, whole-preview drag, coordinate-frame conversion, unlocked boundaries, and suggested anchor implemented. Seasonal normal live checkBatch returned valid for one available block, with NO place call. Seasonal placement itself untested.
- Native combo adapter V2 registered and read-only library verified: 11/15 My combos, 6/15 saved shared, max500 pieces. Native UI displays real counts and Apple name/save action. No combo save sent. Normal own-combo save produces a SHAREABLE game code; explicit app confirmation explains that. Unplaced custom layouts cannot yet save through normal API because it requires existing placed IDs. Shared builds can use an already-revealed code without typing it.
- Combo saves use fresh capacity checks, durable one-shot journal and independent list readback. Full libraries are blocked without overwriting: user must free a chosen slot in game; native replacement chooser remains pending.
- No purchases, duplicate imports, movements, combo deletion, or website publication in this update. Existing Apple journal MUST NOT be resent; its historical anchor may differ from user's current placement.
- Remaining acceptance: all-zone visual coverage, actual saved-combo create/readback and restart persistence. Do not claim these from mock tests or UI availability.

## Homeland build library

- Native Aniidex browser for Americas, Europe and Asia-Pacific with server-safe filtering.
- Interactive source detail pages with the real Aniidex GLB-backed 3D scene, furniture details and code reveal.
- Live community source desk for Aniidex, AniimoShare, curated roundups, Reddit and Americas-focused X search.
- Next: source-specific import adapters, duplicate detection, creator attribution, code health checks and local favorites.

### Local build favorites — requested October 23

- Add a heart/save action to build cards and build details.
- Persist favorites locally on this Mac across app restarts and catalog refreshes.
- Add a Favorites filter/view in the Build Library so saved builds are easy to revisit.
- Identify each favorite by source, server and layout code; preserve its creator, title and preview so identical codes on different servers cannot collide.
- Keep these build favorites separate from the Aniimo collection's existing favorites. No external account or source-site login is required.

## Local save and direct Homeland editing

### Kevin's next priorities — October24

1. Finalize the shared outdoor environments first, preserving the approved grass/daylight look while recovering actual terrain, vegetation and background scenery.
2. Reconstruct the player's exact production area zone by zone, with actual captured object identities, facility levels, placements and unlocked-zone state. Preserve the residential reconstruction too.
3. Hovering or clicking a3D piece shows its exact in-game localized name and purchase cost/currency, sourced from indexed game data. Never show prefab identifiers as if they were game names or invent a price for unavailable data.
4. Make the hover/click item card actionable: open that exact item's in-app Items/Objects detail, including where the player can purchase it in the game and any known unlock requirements. This navigation is informational; it does not itself buy an item.
5. Selecting one object highlights only that instance with a thin bright green outline matching the game, including an individual floor tile among adjacent tiles. Do not highlight every instance sharing its prefab or replace the outline with a whole-scene tint. Keep the effect attached to the object's transform as it is edited and clear it when deselected.

The user-supplied game reference shows a thin green selected-piece border. Its large yellow rectangle is a screenshot annotation, not the requested UI effect. The source outline prototype traces actual thin-floor top boundaries, addressing adjacency occlusion in native QA with real cached models. Complex cutouts, animation, nonuniform geometry and installed interactive acceptance still need validation.

This work is intentionally staged so a discovery mistake cannot corrupt a player's progress.

1. Discover Steam and GameHub/Wine install, account and save locations without opening or changing file contents.
2. Identify which files are authoritative saves versus caches, logs or server-synchronized mirrors.
3. Document container, compression, serialization, checksums, encryption and game-version compatibility.
4. Build a read-only decoder with fixtures and byte-for-byte round-trip tests.
5. Visualize the player's real Homeland and inventory without writing to the save.
6. Add explicit export and automatic timestamped backups, plus restore and corruption detection.
7. Add edits in a detached working copy and validate that an encode/decode round trip preserves unknown fields.
8. Determine the authoritative write path with account/server/build checks and rollback. A closed-game local-file edit cannot be assumed to update server-owned Homeland state; official-client dispatch remains unimplemented.
9. Convert or inject a community build only after item ownership, area limits, RV requirements and placement bounds pass validation.

Current boundary: Atlas decodes installed static data and reconstructs captured live placement records with recovered owning-map identities. Local drafts and detached byte-preserving translation candidates are implemented; game/server writeback, progression editing and save synchronization remain unimplemented. See the source README for current validation and artifact boundaries.


## Verified direct storage — October 26

- Completed: six matching white entrance tiles placed for 36 Bud Tickets; two original paving pieces returned to inventory through the normal Store RPC without opening Multi-Select or clicking Store in the game. Planters and other placements preserved.
- Native Store requires exact instance/template/area/transform checks, normal game eligibility, a durable nonce claim, successful callback, inventory returns, and unchanged surrounding placements. Uncertain operations are never automatically resent.
- Installed controls: Store in inventory in the live inspector and Store whole build for imported builds. Ownership-bound registration refreshes for a new Homeland context; old transaction records remain preserved.
- Validation: 126 Swift tests, 6 optional skips, no failures; storage and library Lua mocks passed; installed app passed strict signing verification. Runtime storage and six-tile import independently read back.
- Follow-up: update assembly membership when a build's original pieces are deliberately replaced; retain original purchase/import audit records. Fix the existing intermittent SwiftUI placement-sheet layout stall.
