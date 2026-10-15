//! Configuration: paths into the Aniimo workspace, persisted as JSON.

use serde::{Deserialize, Serialize};
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Root of the Aniimo workspace (the folder holding the game install,
    /// Serviimo/Apiimo checkouts, dumps, ...).
    pub workspace: PathBuf,
    /// Steam game install root (contains GameAssembly.dll).
    pub game_dir: PathBuf,
    /// Where pulled save blobs live.
    pub saves_dir: PathBuf,
    /// Serviimo checkout (contains run.sh, serviimo-data, target/).
    pub serviimo_dir: PathBuf,
    /// apiimo CLI binary (absolute path, or a name on PATH).
    pub apiimo_bin: PathBuf,
}

/// Walk up from the CWD (or `$ANII_WORKSPACE`) looking for a directory that
/// contains one of the known workspace markers.
pub fn discover_workspace() -> Option<PathBuf> {
    if let Ok(ws) = std::env::var("ANII_WORKSPACE") {
        let p = PathBuf::from(ws);
        if p.is_dir() {
            return Some(p);
        }
    }
    let mut dir = std::env::current_dir().ok()?;
    loop {
        for marker in [".Aniimo_Steam", "Serviimo_src", "Apiimo_src", "AniiStudio_src"] {
            if dir.join(marker).exists() {
                return Some(dir);
            }
        }
        if !dir.pop() {
            return None;
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        let ws = discover_workspace().unwrap_or_else(|| PathBuf::from("."));
        Self {
            game_dir: ws.join(".Aniimo_Steam"),
            saves_dir: ws.join("saves"),
            serviimo_dir: ws.join("Serviimo_src"),
            apiimo_bin: ws.join("Apiimo_src").join("target/release/apiimo"),
            workspace: ws,
        }
    }
}

impl Config {
    pub fn backups_dir(&self) -> PathBuf {
        self.saves_dir.join("_backups")
    }

    pub fn trash_dir(&self) -> PathBuf {
        self.backups_dir().join("trash")
    }

    pub fn is_apiimo_available(&self) -> bool {
        let s = self.apiimo_bin.to_string_lossy();
        !s.contains(std::path::MAIN_SEPARATOR) || self.apiimo_bin.exists()
    }
}

pub fn config_path() -> Option<PathBuf> {
    directories::ProjectDirs::from("", "", "aniistudio").map(|d| d.config_dir().join("config.json"))
}

pub fn load() -> Config {
    config_path()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save(cfg: &Config) -> Result<PathBuf, String> {
    let path = config_path().ok_or("no config directory available")?;
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    let json = serde_json::to_string_pretty(cfg).map_err(|e| e.to_string())?;
    std::fs::write(&path, json).map_err(|e| e.to_string())?;
    Ok(path)
}

/// True when the path points at something concrete — used to render
/// found/missing badges without failing on PATH-relative binaries.
pub fn marked_exists(p: &Path) -> Option<bool> {
    let s = p.to_string_lossy();
    if s.contains(std::path::MAIN_SEPARATOR) {
        Some(p.exists())
    } else {
        None // PATH lookup; unknown here
    }
}
