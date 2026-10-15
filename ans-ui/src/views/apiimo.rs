//! Apiimo toolbox: one-click CLI actions with captured output.

use crate::AniiStudio;
use egui::Ui;

pub fn show(app: &mut AniiStudio, ui: &mut Ui) {
    ui.heading("Apiimo");
    ui.weak(format!("Game: {}", app.cfg.game_dir.display()));
    ui.weak(format!("Binary: {}", app.cfg.apiimo_bin.display()));
    ui.separator();

    ui.horizontal(|ui| {
        if ui.button("Gate status").clicked() {
            run(app, ans_apiimo::gate_status);
        }
        if ui.button("Discover").clicked() {
            run(app, ans_apiimo::discover);
        }
        if ui.button("Key").clicked() {
            run(app, ans_apiimo::key);
        }
        if ui.button("Dump").clicked() {
            run(app, ans_apiimo::dump);
        }
    });
    ui.weak(
        "Dump decrypts/rebuilds global-metadata and writes <game>/.dump — it can take a while. \
         Save pulls live in the Saves tab.",
    );

    super::console(ui, &app.out, 340.0);
}

fn run(app: &mut AniiStudio, build: fn(&ans_core::config::Config) -> Vec<String>) {
    let args = build(&app.cfg);
    match ans_apiimo::run(&app.cfg, &app.out, &args) {
        Ok(()) => app.status = "apiimo running…".to_string(),
        Err(err) => app.status = format!("apiimo failed to start: {err}"),
    }
}
