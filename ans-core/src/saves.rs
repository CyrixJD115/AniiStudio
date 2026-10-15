//! Save blob management: scan, backup, restore, safe delete.

use crate::util;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

#[derive(Debug, Clone)]
pub struct SaveEntry {
    pub name: String,
    pub path: PathBuf,
    pub size: u64,
    pub modified: SystemTime,
}

/// List the top-level save files in `dir`, newest first. Returns an empty
/// vector when the directory does not exist (nothing scanned yet).
pub fn scan(dir: &Path) -> Vec<SaveEntry> {
    let Ok(rd) = std::fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut entries: Vec<SaveEntry> = rd
        .flatten()
        .filter_map(|e| {
            let md = e.metadata().ok()?;
            if !md.is_file() {
                return None;
            }
            let name = e.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                return None;
            }
            Some(SaveEntry {
                name,
                path: e.path(),
                size: md.len(),
                modified: md.modified().unwrap_or(SystemTime::UNIX_EPOCH),
            })
        })
        .collect();
    entries.sort_by(|a, b| b.modified.cmp(&a.modified));
    entries
}

/// Copy a save into `backups_dir` with a timestamp suffix. Names are made
/// unique so two backups in the same second never overwrite each other.
pub fn backup(path: &Path, backups_dir: &Path) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(backups_dir)?;
    let name = file_name(path);
    let stem = format!("{name}.bak-{}", util::timestamp());
    let target = unique_path(backups_dir, &stem);
    std::fs::copy(path, &target)?;
    Ok(target)
}

/// Restore a backup into `saves_dir`. An existing live save is safety-backed
/// up first, so restores never destroy data.
pub fn restore(backup_path: &Path, saves_dir: &Path, backups_dir: &Path) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(saves_dir)?;
    let name = file_name(backup_path);
    let original = name
        .split_once(".bak-")
        .map(|(orig, _)| orig.to_string())
        .unwrap_or(name);
    let target = saves_dir.join(&original);
    if target.exists() {
        backup(&target, backups_dir)?;
    }
    std::fs::copy(backup_path, &target)?;
    Ok(target)
}

/// Move a file into a trash folder instead of deleting it outright.
pub fn trash(path: &Path, trash_dir: &Path) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(trash_dir)?;
    let name = file_name(path);
    let target = unique_path(trash_dir, &format!("{}-{name}", util::timestamp()));
    match std::fs::rename(path, &target) {
        Ok(()) => Ok(target),
        // Cross-device move: fall back to copy + remove.
        Err(_) => {
            std::fs::copy(path, &target)?;
            std::fs::remove_file(path)?;
            Ok(target)
        }
    }
}

/// `<dir>/<stem>`, suffixed `-2`, `-3`, … when it already exists.
fn unique_path(dir: &Path, stem: &str) -> PathBuf {
    let mut target = dir.join(stem);
    let mut n = 1;
    while target.exists() {
        n += 1;
        target = dir.join(format!("{stem}-{n}"));
    }
    target
}

fn file_name(path: &Path) -> String {
    path.file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmp(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("ans-core-test-{tag}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn backup_and_restore_round_trip() {
        let dir = tmp("roundtrip");
        std::fs::write(dir.join("save.bin"), b"v1").unwrap();
        let backups = dir.join("_backups");

        // Overwrite, then back the new version up.
        std::fs::write(dir.join("save.bin"), b"v2").unwrap();
        let bak = backup(&dir.join("save.bin"), &backups).unwrap();
        assert!(bak.to_string_lossy().contains(".bak-"));

        // Losing the live file and restoring the backup brings v2 back.
        std::fs::remove_file(dir.join("save.bin")).unwrap();
        let restored = restore(&bak, &dir, &backups).unwrap();
        assert_eq!(restored, dir.join("save.bin"));
        assert_eq!(std::fs::read(&restored).unwrap(), b"v2");
        assert_eq!(scan(&backups).len(), 1);
    }

    #[test]
    fn restore_safety_backs_up_existing_target() {
        let dir = tmp("safety");
        std::fs::write(dir.join("save.bin"), b"old").unwrap();
        let backups = dir.join("_backups");
        let bak = backup(&dir.join("save.bin"), &backups).unwrap();

        std::fs::write(dir.join("save.bin"), b"new").unwrap();
        restore(&bak, &dir, &backups).unwrap();
        // "old" is back in place, and "new" was preserved as a safety copy.
        assert_eq!(std::fs::read(dir.join("save.bin")).unwrap(), b"old");
        assert_eq!(scan(&backups).len(), 2);
    }

    #[test]
    fn scan_lists_files_newest_first() {
        let dir = tmp("scan");
        std::fs::write(dir.join("b.bin"), b"old").unwrap();
        std::thread::sleep(std::time::Duration::from_millis(10));
        std::fs::write(dir.join("a.bin"), b"newer and larger data").unwrap();
        std::fs::create_dir(dir.join("subdir")).unwrap();
        let names: Vec<String> = scan(&dir).into_iter().map(|e| e.name).collect();
        assert_eq!(names, vec!["a.bin".to_string(), "b.bin".to_string()]);
    }
}
