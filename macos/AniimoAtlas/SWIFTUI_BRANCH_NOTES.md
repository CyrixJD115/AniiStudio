# AniiStudio SwiftUI snapshot — 2026-11-01

This branch collects the accumulated macOS SwiftUI work: the redesigned shell, Homeland environment/interaction tools, read-only live roster and additive caught tracker, game-inspired management layout, and fitted creature-model stage.

## Verified locally

- Read-only roster query `home.getBagPets(includeHomeland=true)` with authenticated self-Homeland checks; string instance IDs preserved.
- Observed 230 initial individuals, later 231; 131 forms matched the static catalog and persisted in the tracker after app restart. These are local observations, not account fixtures bundled in the repository.
- Management: real deployed party, individual portrait grid, filters/search, selected model and 15-second refresh while visible. No live release action is implemented.
- Model stage: authored transforms preserved, pose-aware bounds, aspect-aware fitting, centered turntable, cancellation checks, isolated skin bindings and bounded model cache.
- Model export audit: 260/265 catalog forms resolved locally. Missing: Cheekie, Wavwal, Malangel, Malevsera, Irisalis. Irisalis requires modular body/hair/hat/wing resolution; the other four lacked character prefabs in the inspected manifest.
- Seven focused model/roster/build-tier tests passed. Full suite: 207 tests, 7 skipped, zero failures with `PACKAGE_RESOURCE_BUNDLE_PATH` pointing to the installed local resource bundle. Without the excluded extracted assets, artwork/model packaging assertions fail as expected. Jeburst, Fulmintis and Sugartini were checked visually in the installed app.

## Local resources and build boundaries

Extracted game GLBs/textures, game archives, captured account data, tokens, live session manifests, native binaries and generated session-specific headers are intentionally excluded. The repository's existing game/user-material exclusion is preserved. The source exporters and static catalog/bounds metadata are included. Obtain game assets locally from your own installation; model coverage in this source snapshot does not mean binaries are distributed here.

`tools/creature-models/build_bounds.py` generates camera bounds from the GLB joint transforms and weighted vertices. Original game animation clips, particles and proprietary shader effects are not exported: the current animated presentation is a turntable, not a faithful game idle animation.

The installed app used a separately validated October 30 connection-only helper with a fresh November 1 runtime pin check. The legacy bootstrap source in this checkout is not claimed to reproduce that installed helper. It retains its original build guard. Do not simply change its hash or arm generated native code: re-derive and validate the exact build bindings first. Purchase/placement registration is blocked by the current connection-only tier. No automatic reuse of captured account sessions belongs in a public build.

The source scripts still contain developer-local path defaults; configure them for your installation. GameHub/Wine and a supported, explicitly configured local connection are needed for live reads. Offline catalog and UI remain usable without those helpers.
