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

## Legal notice

- **Not affiliated.** This is a personal, fan-made project. It is not
  affiliated with, endorsed by, or sponsored by the developers or publishers
  of Aniimo. All game names, trademarks, and assets belong to their
  respective owners.
- **No game content is distributed.** Neither this repository nor any of its
  submodules ships any part of the game — no binaries, assets, code, or data.
- **Bring your own game.** Every tool in this ecosystem expects you to
  provide your own game files, obtained through your own legitimate Steam
  account.
- **Acceptable use.** Mods are strictly for use with your own private
  [Serviimo](https://github.com/CyrixJD115/Serviimo) server. Cheating, or
  tampering with the official Aniimo servers or any other online service, is
  prohibited — see AniiModLoader's
  [acceptable-use section](https://github.com/CyrixJD115/AniiModLoader#purpose-and-acceptable-use--read-this-first).
- **Rights holders.** If you believe something in this repository or its
  submodules infringes your rights, please open an issue describing it;
  legitimate reports will be reviewed and resolved promptly.
- **No warranty.** Everything is provided "as is", without warranty of any
  kind. You are responsible for how you use this software and for complying
  with the game's terms of service and the laws that apply to you.
