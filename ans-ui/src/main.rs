//! AniiStudio — desktop hub for the Aniimo ecosystem.
//!
//! Monorepo layout:
//! - `ans-core`    config, save management, process runner
//! - `ans-apiimo`  apiimo CLI integration
//! - `ans-ui`      this egui app (binary: `aniistudio`)

mod views;

use ans_core::config::Config;
use ans_core::runner::Runner;
use ans_core::saves::{self, SaveEntry};
use views::dashboard::{EnvRow, ModuleStatus};
use views::settings::EditBuffers;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Tab {
    Dashboard,
    Saves,
    Serviimo,
    Apiimo,
    Settings,
}

const TABS: [(Tab, &str, &str); 5] = [
    (Tab::Dashboard, "Dashboard", "⌂"),
    (Tab::Saves, "Saves", "⬇"),
    (Tab::Serviimo, "Serviimo", "🛰"),
    (Tab::Apiimo, "Apiimo", "🧰"),
    (Tab::Settings, "Settings", "⚙"),
];

pub struct AniiStudio {
    pub cfg: Config,
    pub tab: Tab,
    /// Shared console for apiimo commands and one-shot actions.
    pub out: Runner,
    /// The Serviimo server process.
    pub serviimo: Runner,
    pub uid: String,
    pub saves: Vec<SaveEntry>,
    pub backups: Vec<SaveEntry>,
    pub modules: Vec<ModuleStatus>,
    pub env: Vec<EnvRow>,
    pub status: String,
    pub edit: EditBuffers,
}

/// Where the monorepo submodules live (`<workspace>/AniiStudio_src/modules`).
pub fn modules_dir(cfg: &Config) -> std::path::PathBuf {
    let candidates = [
        cfg.workspace.join("AniiStudio_src").join("modules"),
        cfg.workspace.join("modules"),
    ];
    candidates
        .iter()
        .find(|p| p.is_dir())
        .cloned()
        .unwrap_or_else(|| candidates[0].clone())
}

impl AniiStudio {
    pub fn new() -> Self {
        let cfg = ans_core::config::load();
        let mut app = Self {
            edit: EditBuffers::from(&cfg),
            cfg,
            tab: Tab::Dashboard,
            out: Runner::new(),
            serviimo: Runner::new(),
            uid: String::new(),
            saves: Vec::new(),
            backups: Vec::new(),
            modules: Vec::new(),
            env: Vec::new(),
            status: "Welcome to AniiStudio".to_string(),
        };
        app.refresh_modules();
        app.refresh_env();
        app.refresh_saves();
        app
    }

    pub fn refresh_saves(&mut self) {
        self.saves = saves::scan(&self.cfg.saves_dir);
        self.backups = saves::scan(&self.cfg.backups_dir());
    }

    pub fn refresh_modules(&mut self) {
        self.modules = views::dashboard::probe_modules(&modules_dir(&self.cfg));
    }

    pub fn refresh_env(&mut self) {
        self.env = views::dashboard::probe_env(&self.cfg, self.saves.len(), self.backups.len());
    }

    pub fn sync_edit_buffers(&mut self) {
        self.edit = EditBuffers::from(&self.cfg);
    }

    pub fn report(&mut self, what: &str, result: std::io::Result<std::path::PathBuf>) {
        match result {
            Ok(path) => self.status = format!("{what}: {}", path.display()),
            Err(err) => self.status = format!("{what} failed: {err}"),
        }
    }

    pub fn pull_save(&mut self) {
        let uid = self.uid.trim().to_string();
        if uid.is_empty() {
            self.status = "Enter an account UID first.".to_string();
            return;
        }
        if let Err(err) = std::fs::create_dir_all(&self.cfg.saves_dir) {
            self.status = format!("saves dir: {err}");
            return;
        }
        let out = self
            .cfg
            .saves_dir
            .join(format!("save-{uid}-{}.bin", ans_core::util::timestamp()));
        let args = ans_apiimo::save_pull(&self.cfg, &uid, &out);
        match ans_apiimo::run(&self.cfg, &self.out, &args) {
            Ok(()) => {
                self.status = format!("Pulling save for {uid} — hit Refresh when it finishes.");
            }
            Err(err) => {
                self.status =
                    format!("apiimo failed to start: {err} (check the binary path in Settings)");
            }
        }
    }
}

impl eframe::App for AniiStudio {
    fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {
        if self.out.is_running() || self.serviimo.is_running() {
            ui.ctx()
                .request_repaint_after(std::time::Duration::from_millis(250));
        }

        egui::Panel::left("nav")
            .resizable(false)
            .default_size(150.0)
            .show(ui, |ui| {
                ui.add_space(8.0);
                ui.heading("AniiStudio");
                ui.weak("Aniimo toolkit");
                ui.add_space(10.0);
                ui.separator();
                for (tab, name, icon) in TABS {
                    if ui
                        .selectable_label(self.tab == tab, format!("{icon}  {name}"))
                        .clicked()
                    {
                        self.tab = tab;
                    }
                }
            });

        egui::Panel::bottom("status")
            .resizable(false)
            .default_size(26.0)
            .show(ui, |ui| {
                ui.horizontal(|ui| {
                    if self.out.is_running() || self.serviimo.is_running() {
                        ui.spinner();
                    }
                    ui.weak(&self.status);
                });
            });

        egui::CentralPanel::default_margins().show(ui, |ui| {
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| match self.tab {
                    Tab::Dashboard => views::dashboard::show(self, ui),
                    Tab::Saves => views::saves::show(self, ui),
                    Tab::Serviimo => views::serviimo::show(self, ui),
                    Tab::Apiimo => views::apiimo::show(self, ui),
                    Tab::Settings => views::settings::show(self, ui),
                });
        });
    }
}

fn main() -> eframe::Result<()> {
    env_logger::init();
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1080.0, 720.0])
            .with_title("AniiStudio"),
        ..Default::default()
    };
    eframe::run_native(
        "AniiStudio",
        options,
        Box::new(|_cc| Ok(Box::new(AniiStudio::new()))),
    )
}
