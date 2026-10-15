//! Dashboard: monorepo submodule status + environment overview.

use crate::AniiStudio;
use ans_core::config::{marked_exists, Config};
use egui::{Color32, Ui};
use std::path::{Path, PathBuf};

pub struct ModuleStatus {
    pub name: String,
    pub path: PathBuf,
    pub exists: bool,
    pub branch: String,
    pub head: String,
    pub dirty: Option<usize>,
}

pub struct EnvRow {
    pub label: String,
    pub value: String,
    pub ok: bool,
}

pub fn probe_modules(modules_dir: &Path) -> Vec<ModuleStatus> {
    const NAMES: [&str; 3] = ["AniiModLoader", "Serviimo", "Apiimo"];
    NAMES
        .iter()
        .map(|&name| {
            let path = modules_dir.join(name);
            let exists = path.is_dir();
            ModuleStatus {
                name: name.to_string(),
                branch: git_out(&path, &["rev-parse", "--abbrev-ref", "HEAD"]).unwrap_or_else(|| "—".into()),
                head: git_out(&path, &["rev-parse", "--short", "HEAD"]).unwrap_or_else(|| "—".into()),
                dirty: dirty_count(&path),
                exists,
                path,
            }
        })
        .collect()
}

pub fn probe_env(cfg: &Config, save_count: usize, backup_count: usize) -> Vec<EnvRow> {
    let mut rows = Vec::new();
    let mut row = |label: &str, value: String, ok: bool| {
        rows.push(EnvRow { label: label.to_string(), value, ok });
    };

    row(
        "Game install",
        cfg.game_dir.display().to_string(),
        cfg.game_dir.join("GameAssembly.dll").exists(),
    );
    row(
        "apiimo CLI",
        cfg.apiimo_bin.display().to_string(),
        marked_exists(&cfg.apiimo_bin).unwrap_or(true),
    );
    let serviimo_bin = cfg.serviimo_dir.join("target/release/serviimo");
    row(
        "Serviimo binary",
        serviimo_bin.display().to_string(),
        serviimo_bin.exists(),
    );
    row(
        "Serviimo data",
        cfg.serviimo_dir.join("serviimo-data").display().to_string(),
        cfg.serviimo_dir.join("serviimo-data/serviimo.sqlite3").exists(),
    );
    row(
        "Saves",
        format!("{} ({save_count} files)", cfg.saves_dir.display()),
        cfg.saves_dir.exists(),
    );
    row(
        "Backups",
        format!("{} ({backup_count} files)", cfg.backups_dir().display()),
        cfg.backups_dir().exists(),
    );
    if let Some(cp) = ans_core::config::config_path() {
        row("Config file", cp.display().to_string(), cp.exists());
    }
    rows
}

pub fn show(app: &mut AniiStudio, ui: &mut Ui) {
    ui.heading("Dashboard");
    ui.horizontal(|ui| {
        if ui.button("Refresh").clicked() {
            app.refresh_modules();
            app.refresh_env();
        }
        ui.weak(format!("workspace: {}", app.cfg.workspace.display()));
    });
    ui.add_space(6.0);

    ui.strong("Monorepo modules");
    if app.modules.is_empty() {
        ui.weak(format!(
            "No modules probed yet — click Refresh (expects {}).",
            crate::modules_dir(&app.cfg).display()
        ));
    } else {
        egui::Grid::new("modules")
            .striped(true)
            .num_columns(5)
            .show(ui, |ui| {
                ui.strong("Module");
                ui.strong("Branch");
                ui.strong("Head");
                ui.strong("Dirty");
                ui.strong("Path");
                ui.end_row();
                for m in &app.modules {
                    ui.strong(&m.name);
                    if m.exists {
                        ui.monospace(&m.branch);
                        ui.monospace(&m.head);
                        let dirty = match m.dirty {
                            Some(0) => "clean".to_string(),
                            Some(n) => format!("{n} files"),
                            None => "?".to_string(),
                        };
                        ui.label(dirty);
                    } else {
                        ui.weak("missing");
                        ui.weak("—");
                        ui.weak("—");
                    }
                    ui.monospace(m.path.display().to_string());
                    ui.end_row();
                }
            });
    }

    ui.add_space(10.0);
    ui.strong("Environment");
    egui::Grid::new("env")
        .striped(true)
        .num_columns(3)
        .show(ui, |ui| {
            for r in &app.env {
                ui.strong(&r.label);
                ui.monospace(&r.value);
                badge(ui, r.ok);
                ui.end_row();
            }
        });
}

fn badge(ui: &mut Ui, ok: bool) {
    let (color, text) = if ok {
        (Color32::from_rgb(110, 200, 110), "✓")
    } else {
        (Color32::from_rgb(230, 110, 110), "✗")
    };
    ui.colored_label(color, text);
}

fn git_out(dir: &Path, args: &[&str]) -> Option<String> {
    std::process::Command::new("git")
        .current_dir(dir)
        .args(args)
        .output()
        .ok()
        .filter(|o| o.status.success())
        .map(|o| String::from_utf8_lossy(&o.stdout).trim().to_string())
        .filter(|s| !s.is_empty())
}

fn dirty_count(dir: &Path) -> Option<usize> {
    let out = std::process::Command::new("git")
        .current_dir(dir)
        .args(["status", "--porcelain"])
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    Some(
        String::from_utf8_lossy(&out.stdout)
            .lines()
            .filter(|l| !l.trim().is_empty())
            .count(),
    )
}
