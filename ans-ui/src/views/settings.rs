//! Settings: editable path configuration, persisted to config.json.

use crate::AniiStudio;
use ans_core::config::Config;
use egui::Ui;
use std::path::PathBuf;

pub struct EditBuffers {
    pub workspace: String,
    pub game_dir: String,
    pub saves_dir: String,
    pub serviimo_dir: String,
    pub apiimo_bin: String,
}

impl EditBuffers {
    pub fn from(cfg: &Config) -> Self {
        Self {
            workspace: cfg.workspace.display().to_string(),
            game_dir: cfg.game_dir.display().to_string(),
            saves_dir: cfg.saves_dir.display().to_string(),
            serviimo_dir: cfg.serviimo_dir.display().to_string(),
            apiimo_bin: cfg.apiimo_bin.display().to_string(),
        }
    }
}

pub fn show(app: &mut AniiStudio, ui: &mut Ui) {
    ui.heading("Settings");
    ui.add_space(4.0);

    egui::Grid::new("settings")
        .striped(true)
        .num_columns(2)
        .show(ui, |ui| {
            field(ui, "Workspace root", &mut app.edit.workspace);
            field(ui, "Game install", &mut app.edit.game_dir);
            field(ui, "Saves directory", &mut app.edit.saves_dir);
            field(ui, "Serviimo directory", &mut app.edit.serviimo_dir);
            field(ui, "apiimo binary", &mut app.edit.apiimo_bin);
        });

    ui.add_space(8.0);
    ui.horizontal(|ui| {
        if ui.button("Save").clicked() {
            app.cfg = Config {
                workspace: PathBuf::from(app.edit.workspace.trim()),
                game_dir: PathBuf::from(app.edit.game_dir.trim()),
                saves_dir: PathBuf::from(app.edit.saves_dir.trim()),
                serviimo_dir: PathBuf::from(app.edit.serviimo_dir.trim()),
                apiimo_bin: PathBuf::from(app.edit.apiimo_bin.trim()),
            };
            match ans_core::config::save(&app.cfg) {
                Ok(path) => app.status = format!("Saved {}", path.display()),
                Err(err) => app.status = format!("Config save failed: {err}"),
            }
            app.refresh_modules();
            app.refresh_env();
            app.refresh_saves();
        }
        if ui.button("Reset to discovered defaults").clicked() {
            app.cfg = Config::default();
            app.sync_edit_buffers();
            app.status = "Defaults restored (not yet saved)".to_string();
            app.refresh_modules();
            app.refresh_env();
            app.refresh_saves();
        }
    });

    if let Some(path) = ans_core::config::config_path() {
        ui.weak(format!("Config file: {}", path.display()));
    }
    ui.weak(
        "Paths are auto-discovered by walking up from the working directory for the \
         Aniimo workspace markers; override anything here or with $ANII_WORKSPACE.",
    );
}

fn field(ui: &mut Ui, label: &str, buf: &mut String) {
    ui.strong(label);
    ui.add(egui::TextEdit::singleline(buf).desired_width(f32::INFINITY));
    ui.end_row();
}
