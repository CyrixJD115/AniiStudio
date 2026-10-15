//! Integration with the `apiimo` CLI (modules/Apiimo) for save pulls,
//! login-gate status and game dumps.
//!
//! The wrapper is deliberately thin: it builds argument vectors and runs them
//! through `ans_core::runner`, keeping the UI decoupled from Apiimo's Rust
//! API so the submodule can move independently.

use ans_core::config::Config;
use ans_core::runner::Runner;
use std::path::Path;

/// Global args every command gets (`--game` when a game dir is configured).
fn base(cfg: &Config) -> Vec<String> {
    if cfg.game_dir.exists() {
        vec!["--game".into(), cfg.game_dir.display().to_string()]
    } else {
        Vec::new()
    }
}

pub fn gate_status(cfg: &Config) -> Vec<String> {
    let mut a = base(cfg);
    a.push("gate-status".into());
    a
}

pub fn discover(cfg: &Config) -> Vec<String> {
    let mut a = base(cfg);
    a.push("discover".into());
    a
}

pub fn dump(cfg: &Config) -> Vec<String> {
    let mut a = base(cfg);
    a.push("dump".into());
    a
}

pub fn key(cfg: &Config) -> Vec<String> {
    let mut a = base(cfg);
    a.push("key".into());
    a
}

/// `apiimo save-pull <uid> <out>` — download an account's save blob.
pub fn save_pull(cfg: &Config, uid: &str, out: &Path) -> Vec<String> {
    let mut a = base(cfg);
    a.push("save-pull".into());
    a.push(uid.to_string());
    a.push(out.display().to_string());
    a
}

/// Run an argument vector through a runner, labelled `apiimo <args...>`.
pub fn run(cfg: &Config, runner: &Runner, args: &[String]) -> std::io::Result<()> {
    let label = format!("apiimo {}", args.join(" "));
    runner.spawn(&label, &cfg.apiimo_bin.display().to_string(), args, None)
}
