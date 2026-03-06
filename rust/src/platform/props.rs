use std::process::Command;

pub fn getprop(name: &str) -> Option<String> {
    Command::new("getprop")
        .arg(name)
        .output()
        .ok()
        .and_then(|o| {
            let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
            if s.is_empty() { None } else { Some(s) }
        })
}

pub fn resetprop(name: &str, value: &str) -> anyhow::Result<()> {
    let status = Command::new("resetprop")
        .args(["-n", name, value])
        .status()?;
    if status.success() {
        Ok(())
    } else {
        anyhow::bail!("resetprop -n {name} {value} failed")
    }
}

pub fn resetprop_delete(name: &str) -> anyhow::Result<()> {
    let status = Command::new("resetprop")
        .args(["--delete", name])
        .status()?;
    if status.success() {
        Ok(())
    } else {
        anyhow::bail!("resetprop --delete {name} failed")
    }
}

pub fn resetprop_wait(name: &str, value: &str) -> anyhow::Result<()> {
    let status = Command::new("resetprop")
        .args(["-w", name, value])
        .status()?;
    if status.success() {
        Ok(())
    } else {
        anyhow::bail!("resetprop -w {name} {value} timed out")
    }
}
