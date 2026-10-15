//! Tab views and shared widgets.

pub mod apiimo;
pub mod dashboard;
pub mod saves;
pub mod serviimo;
pub mod settings;

use ans_core::runner::Runner;
use egui::Ui;

/// Read-only monospace console bound to a runner's captured output.
pub fn console(ui: &mut Ui, runner: &Runner, max_height: f32) {
    ui.add_space(6.0);
    ui.horizontal(|ui| {
        ui.strong("Output");
        if runner.is_running() {
            ui.spinner();
            ui.weak(format!("'{}' running…", runner.label()));
        } else if !runner.log().is_empty() {
            ui.weak("idle");
        }
        if ui.button("Clear").clicked() {
            runner.clear_log();
        }
    });
    let mut log = runner.log();
    egui::ScrollArea::vertical()
        .max_height(max_height)
        .auto_shrink([false, false])
        .stick_to_bottom(true)
        .show(ui, |ui| {
            ui.add(
                egui::TextEdit::multiline(&mut log)
                    .font(egui::TextStyle::Monospace)
                    .desired_width(f32::INFINITY),
            );
        });
}
