# Offline Homeland world research tooling

Authored Python source for bounded source-stream parsing, original geometry/material extraction, an offline numerical terrain-compute reference, native material derivatives and regression checks. No game archives, shader disassemblies, textures, models, captured player state, credentials or compiled tools are distributed here.

These tools are research utilities, not an automatic world exporter or game-patch compatibility guarantee. Most require explicitly supplied, locally extracted evidence under the research directory expected by each script. Artifact tests may require those private inputs; they are separate from the native app's Swift test suite. Read each script's usage and input/schema checks before running it. Python dependencies used locally include UnityPy, NumPy, Pillow, zstandard and texture2ddecoder; dependencies are not vendored.

Original world meshes/placements and shipped terrain atlases were checked independently. The bounded DXBC reference evaluates source instructions offline, with explicit sampling/uniform settings validated against three source atlases. Numerical approximations, source shader gaps and unresolved visual differences remain; the output is not claimed identical to a live engine frame. These tools never dispatch a game RPC or modify a save/server.

See [the October 24 findings](../../docs/homeland-progress-2026-10-24.md) and [the native app](../../macos/AniimoAtlas/README.md). Sol / Sol 6.1 implemented this tooling under Kevin's direction; Astra assisted with prior protocol/data research and technical review/writeups. Third-party game-asset rights remain with their owners.
