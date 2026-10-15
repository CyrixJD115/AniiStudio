//! Saves: pull blobs with apiimo, back them up, restore, trash.

use crate::AniiStudio;
use ans_core::saves;
use ans_core::util;
use egui::Ui;
use std::path::PathBuf;

pub fn show(app: &mut AniiStudio, ui: &mut Ui) {
    ui.heading("Saves");
    ui.horizontal(|ui| {
        ui.label("Account UID:");
        ui.text_edit_singleline(&mut app.uid)
            .on_hover_text("UID the account uses for save pulls");
        if ui.button("⬇ Pull save").clicked() {
            app.pull_save();
        }
        if ui.button("Refresh").clicked() {
            app.refresh_saves();
            app.status = format!("{} saves, {} backups", app.saves.len(), app.backups.len());
        }
    });
    ui.weak(format!("Directory: {}", app.cfg.saves_dir.display()));
    ui.separator();

    let mut to_backup: Vec<PathBuf> = Vec::new();
    let mut to_trash: Vec<PathBuf> = Vec::new();
    egui::ScrollArea::vertical()
        .max_height(220.0)
        .auto_shrink([false, false])
        .show(ui, |ui| {
            egui::Grid::new("saves-table")
                .striped(true)
                .num_columns(4)
                .show(ui, |ui| {
                    ui.strong("Save");
                    ui.strong("Size");
                    ui.strong("Modified");
                    ui.strong("Actions");
                    ui.end_row();
                    for entry in &app.saves {
                        ui.monospace(&entry.name);
                        ui.label(util::fmt_size(entry.size));
                        ui.weak(util::fmt_time(entry.modified));
                        ui.horizontal(|ui| {
                            if ui.button("Backup").clicked() {
                                to_backup.push(entry.path.clone());
                            }
                            if ui.button("Trash").clicked() {
                                to_trash.push(entry.path.clone());
                            }
                        });
                        ui.end_row();
                    }
                });
        });
    if app.saves.is_empty() {
        ui.weak("No saves yet — pull one with a UID above.");
    }
    let had_changes = !(to_backup.is_empty() && to_trash.is_empty());
    for path in to_backup {
        let what = format!("Backup {}", path.display());
        let result = saves::backup(&path, &app.cfg.backups_dir());
        app.report(&what, result);
    }
    for path in to_trash {
        let what = format!("Trash {}", path.display());
        let result = saves::trash(&path, &app.cfg.trash_dir());
        app.report(&what, result);
    }
    if had_changes {
        app.refresh_saves();
    }

    ui.add_space(8.0);
    ui.separator();
    ui.strong("Backups");
    ui.weak(format!("Directory: {}", app.cfg.backups_dir().display()));

    let mut to_restore: Vec<PathBuf> = Vec::new();
    egui::ScrollArea::vertical()
        .max_height(180.0)
        .auto_shrink([false, false])
        .show(ui, |ui| {
            egui::Grid::new("backups-table")
                .striped(true)
                .num_columns(3)
                .show(ui, |ui| {
                    ui.strong("Backup");
                    ui.strong("Size");
                    ui.strong("Actions");
                    ui.end_row();
                    for entry in &app.backups {
                        ui.monospace(&entry.name);
                        ui.label(util::fmt_size(entry.size));
                        if ui.button("Restore").clicked() {
                            to_restore.push(entry.path.clone());
                        }
                        ui.end_row();
                    }
                });
        });
    if app.backups.is_empty() {
        ui.weak("No backups yet.");
    }
    let had_restores = !to_restore.is_empty();
    for path in to_restore {
        let what = format!("Restore {}", path.display());
        let result = saves::restore(&path, &app.cfg.saves_dir, &app.cfg.backups_dir());
        app.report(&what, result);
    }
    if had_restores {
        app.refresh_saves();
    }

    super::console(ui, &app.out, 180.0);
}
