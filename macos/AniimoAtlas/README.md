# Aniimo Atlas — native macOS Homeland companion

SwiftPM macOS 14+ app with native SceneKit/GLTFKit2 Homeland rendering, an installed-content index, capture inspection and local editing drafts. This is an unofficial personal companion, not affiliated with Aniimo or Aniidex.

## Build and test

```sh
swift test --scratch-path /tmp/aniimo-atlas-tests
./script/build_and_run.sh --verify
```

The build script stages clean resources, signs a local-use app, installs it in `~/Applications/AniimoAtlas.app`, and packages `dist/AniimoAtlas.app.zip`. `--build` installs without launching; `--verify` checks signature and launch/process presence. These checks do not prove a particular view or game integration works. This is an ad hoc development signature, not a notarized public release. Set `ANII_BUILD_DIR` to reuse an explicitly selected SwiftPM cache. Read-only capture helper sources are included under `tools/aniimo-memory-capture` and built into the app; macOS may require permission to inspect another process.

## Current Homeland implementation

- Build Library uses server-specific public Aniidex listing data and clean GLB placement manifests. Native layout rendering does not embed the listing webpage or its advertisements. Community source views remain attributed external content.
- Content Index explicitly indexes an owned game installation, fingerprints relevant files, and caches bounded `pmdata.bin` BDD object/zone data. Cached browsing does not automatically rescan Documents or removable volumes.
- The capture importer validates compact ornament records, resolves template/prefab identities, and retains recovered owning-map keys. Captured Areas exposes Production, Residential and Seasonal reconstructions.
- Selected instances support local transform previews, persistent identity/source-bound drafts, undo/redo and reset. The green-outline implementation targets an individual instance, including thin adjacent floor tiles.
- Recovered terrain/scenery context is a separate checksum-bound local package with embedded textures and exact transform restoration. Only an explicitly calibrated captured residential scene can attach this context; an arbitrary community layout is not treated as a verified world alignment. Original materials, foliage density, lighting, water and weather are not fully reproduced.
- A detached translation candidate edits integer-centimetre position bytes while preserving the rest of the original record. It rejects missing identity and out-of-range coordinates and checks source identity for staleness. It is not connected to transport or a server.

**No game/server writeback, cloud-save editing, purchases, currency changes, Aniimo/egg injection or complete save synchronization is implemented or verified.** A local ClientInfo cache is not the authoritative Homeland layout. A rendered reference scene or saved preview does not prove a game modification. Fresh complete-map acquisition, owning entity/property binding, rejection/conflict behavior and persistent official-client updates remain research work.

## Verification snapshot — October 24, 2026

The private local owning-map fixture contains 3,964 unique keyed records. After targeted acquisition of 19 additional public models, native coverage is 740/743 Production, 3,118/3,119 Residential, and 101/102 Seasonal records. Missing objects remain explicit. Counts describe that saved fixture and asset cache, not a current fresh session or a guarantee for other accounts/builds.

The full local Swift suite reported 57 tests, six optional tests skipped, zero failures when the installed-data fixture was explicitly supplied. Without private fixtures, additional integration tests skip. Separate opt-in tests exercised actual native Production/Seasonal GPU renders and five recovered-world checks, including all 3,118 residential matrices, 11,273 world-node transforms and 513,788 terrain triangles. Tests use synthetic records where possible; live captures and game assets are not distributed.

Optional inputs include `ANII_PMDATA_PATH` for a user-supplied installed-data fixture, `ANII_WORLD_CONTEXT_QA_DIR` for recovered scenery, `ANII_WORLD_CONTEXT_RENDER_DIR` for a native integration preview, `ANII_AREA_RENDER_DIR` for captured-area rendering, and `ANII_HOMELAND_QA_EXPORT_DIR` for an offline content export. Capture-dependent tests skip when local evidence is absent. Game patches can invalidate the snapshot's expected counts and mappings.

## Other companion features and data

Bundled Aniilog/appearance catalog, local collection/favorites, field guides, recipes/material planning and source-attributed optimizer resources remain available. Catalog data are dated snapshots, not continuously synchronized game progress. Local community-build favorites and exact localized item-name/price/purchase-location navigation are still planned. See [ROADMAP.md](ROADMAP.md).

Catalog/appearance data and source links come from [Aniidex](https://aniidex.com/), [AniimoGuide](https://aniimoguide.com/), and sources recorded in bundled notices/data. Third-party notices are retained under `Sources/AniimoAtlas/Resources/Notices`. Code licenses do not grant ownership or redistribution rights to third-party game models, textures, artwork or other assets. Native GLBs and recovered world packages are acquired locally and excluded from this source contribution.

## Attribution

Under Kevin's direction, **Sol / Sol 6.1** implemented the native macOS capture/index/editor/rendering work and tests. **Astra** assisted with protocol/BDD/Plot 16 analysis and technical review/writeups. Astra did not implement the overnight native changes. The research remains incomplete; attribution is not a compatibility or writeback claim.
