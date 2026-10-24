# Aniimo Atlas roadmap

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
