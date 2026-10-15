//! Serviimo: start/stop the local server via run.sh, watch its output.

use crate::AniiStudio;
use egui::{Color32, Ui};

pub fn show(app: &mut AniiStudio, ui: &mut Ui) {
    ui.heading("Serviimo");
    let dir = app.cfg.serviimo_dir.clone();
    ui.weak(format!("Directory: {}", dir.display()));
    ui.add_space(4.0);

    let facts = [
        (
            "server binary",
            dir.join("target/release/serviimo").exists(),
        ),
        ("run.sh", dir.join("run.sh").exists()),
        (
            "serviimo.sqlite3",
            dir.join("serviimo-data/serviimo.sqlite3").exists(),
        ),
        (
            "tls-key.pem",
            dir.join("serviimo-data/tls-key.pem").exists(),
        ),
        (
            "gate-key.pem",
            dir.join("serviimo-data/gate-key.pem").exists(),
        ),
        (
            "serviimo-ca.pem",
            dir.join("serviimo-data/serviimo-ca.pem").exists(),
        ),
    ];
    ui.horizontal(|ui| {
        for (label, ok) in facts {
            let (color, mark) = if ok {
                (Color32::from_rgb(110, 200, 110), "✓")
            } else {
                (Color32::from_rgb(230, 110, 110), "✗")
            };
            ui.colored_label(color, format!("{label} {mark}"));
        }
    });
    ui.separator();

    let running = app.serviimo.is_running();
    ui.horizontal(|ui| {
        if running {
            ui.spinner();
            ui.label("Serviimo is running.");
            if ui.button("■ Stop").clicked() {
                if app.serviimo.stop() {
                    app.status = "Serviimo stop issued.".to_string();
                }
            }
        } else if ui.button("▶ Start (run.sh)").clicked() {
            let args = vec!["run.sh".to_string()];
            match app.serviimo.spawn("serviimo via run.sh", "sh", &args, Some(&dir)) {
                Ok(()) => app.status = "Serviimo starting…".to_string(),
                Err(err) => app.status = format!("Serviimo failed to start: {err}"),
            }
        }
    });
    ui.weak(
        "run.sh reapplies CAP_NET_BIND_SERVICE and the vanilla-IP loopback routes \
         (passwordless sudo), syncs the CA anchor, then execs the server.",
    );
    ui.weak(format!("Data lives in {}", dir.join("serviimo-data").display()));

    super::console(ui, &app.serviimo, 280.0);
}
