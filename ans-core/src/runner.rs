//! Long-running child processes with a shared, capped output log.

use std::io::Read;
use std::path::Path;
use std::process::{Child, Command, Stdio};
use std::sync::{Arc, Mutex};

const LOG_CAP: usize = 128 * 1024;

struct RunnerState {
    child: Option<Child>,
    label: String,
}

/// Cloneable handle to one spawned process and its captured output.
#[derive(Clone)]
pub struct Runner {
    state: Arc<Mutex<RunnerState>>,
    log: Arc<Mutex<String>>,
}

impl Default for Runner {
    fn default() -> Self {
        Self::new()
    }
}

impl Runner {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(RunnerState { child: None, label: String::new() })),
            log: Arc::new(Mutex::new(String::new())),
        }
    }

    /// Spawn a process, capturing merged stdout/stderr into the log.
    /// Fails if a previous process from this runner is still running.
    pub fn spawn(
        &self,
        label: &str,
        program: &str,
        args: &[String],
        cwd: Option<&Path>,
    ) -> std::io::Result<()> {
        if self.is_running() {
            return Err(std::io::Error::other(format!(
                "'{}' is still running",
                self.label()
            )));
        }
        let mut cmd = Command::new(program);
        cmd.args(args)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .stdin(Stdio::null());
        if let Some(dir) = cwd {
            cmd.current_dir(dir);
        }
        let mut child = cmd.spawn()?;
        let stdout = child.stdout.take().expect("piped stdout");
        let stderr = child.stderr.take().expect("piped stderr");
        {
            let mut st = self.state.lock().unwrap();
            st.label = label.to_string();
            st.child = Some(child);
        }
        {
            let mut log = self.log.lock().unwrap();
            log.clear();
            log.push_str(&format!("$ {label}\n"));
        }
        read_into(stdout, &self.log);
        read_into(stderr, &self.log);
        Ok(())
    }

    pub fn is_running(&self) -> bool {
        let mut st = self.state.lock().unwrap();
        match &mut st.child {
            Some(child) => child.try_wait().map(|exit| exit.is_none()).unwrap_or(false),
            None => false,
        }
    }

    pub fn label(&self) -> String {
        self.state.lock().unwrap().label.clone()
    }

    /// Kill the running process, if any. Returns whether a kill was issued.
    pub fn stop(&self) -> bool {
        let mut st = self.state.lock().unwrap();
        if let Some(child) = &mut st.child {
            match child.try_wait() {
                Ok(Some(_)) => false,
                Ok(None) => child.kill().is_ok(),
                Err(_) => false,
            }
        } else {
            false
        }
    }

    pub fn log(&self) -> String {
        self.log.lock().unwrap().clone()
    }

    pub fn clear_log(&self) {
        self.log.lock().unwrap().clear();
    }
}

fn read_into<R: Read + Send + 'static>(mut reader: R, log: &Arc<Mutex<String>>) {
    let log = Arc::clone(log);
    std::thread::spawn(move || {
        let mut buf = [0u8; 4096];
        loop {
            match reader.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    let chunk = String::from_utf8_lossy(&buf[..n]).into_owned();
                    let mut log = log.lock().unwrap();
                    log.push_str(&chunk);
                    if log.len() > LOG_CAP {
                        let cut = log.len() - LOG_CAP;
                        let mut i = cut;
                        while i < log.len() && !log.is_char_boundary(i) {
                            i += 1;
                        }
                        log.drain(..i);
                        log.insert_str(0, "…\n");
                    }
                }
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn captures_output_and_finishes() {
        let r = Runner::new();
        let args = vec!["-c".to_string(), "echo hello; echo err >&2".to_string()];
        r.spawn("sh echo", "sh", &args, None).expect("spawn");
        for _ in 0..100 {
            if !r.is_running() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(20));
        }
        assert!(!r.is_running());
        let log = r.log();
        assert!(log.contains("hello"), "log: {log}");
        assert!(log.contains("err"), "log: {log}");
    }
}
