# AniiStudio

> ⚠️ **Heavily work in progress.** Some functions work, some don't. Any
> contribution really helps — to AniiStudio itself or to any of the three
> modules below; improvements on either side benefit both.

Central hub for the Aniimo ecosystem — monorepo + desktop toolkit for managing
saves pulled from the Aniimo servers, running Serviimo, and driving Apiimo.

## Layout

| Path                  | What                                                        |
| --------------------- | ----------------------------------------------------------- |
| `ans-core`            | Config, save management, process runner                     |
| `ans-apiimo`          | Apiimo CLI integration (save pulls, gate status, dumps)     |
| `ans-ui`              | Desktop app (`aniistudio`, egui)                            |
| `modules/AniiModLoader` | Submodule — universal Unity mod loader (Il2Cpp & Mono)    |
| `modules/Serviimo`    | Submodule — local Aniimo services (gate / office / CDN / world) |
| `modules/Apiimo`      | Submodule — Aniimo network, API & crypto toolkit            |

## Run

```sh
git submodule update --init --recursive
cargo run -p ans-ui
```

The app auto-discovers the Aniimo workspace (game install, Serviimo/Apiimo
checkouts) by walking up from the working directory, or via `$ANII_WORKSPACE`;
everything is overridable in Settings.
