//! Last completed compilation facts for CLI inspection and other tools.
use serde_json::Value;
use std::{fs, io, path::{Path, PathBuf}};
fn path(project: &Path, suffix: &str) -> io::Result<PathBuf> {
    let stem = project.file_stem().ok_or_else(|| io::Error::other("manifest stem missing"))?.to_string_lossy();
    Ok(project.parent().ok_or_else(|| io::Error::other("manifest parent missing"))?.join(".dmbc").join(format!("{stem}.{suffix}.json")))
}
pub fn save(project: &Path, suffix: &str, value: &Value) -> io::Result<()> {
    let path = path(project, suffix)?;
    fs::create_dir_all(path.parent().expect("telemetry parent"))?;
    let temporary = path.with_extension(format!("{}.tmp", std::process::id()));
    fs::write(&temporary, serde_json::to_vec(value)?)?;
    fs::rename(temporary, path)
}
pub fn inspect(project: &Path, target: Option<&str>) -> io::Result<Value> {
    let bytes = fs::read(path(project, "stats")?)?;
    if bytes.len() > 64 * 1024 * 1024 { return Err(io::Error::other("telemetry exceeds bound")); }
    let mut value: Value = serde_json::from_slice(&bytes)?;
    if let Some(target) = target {
        let results: Vec<Value> = value["explanations"].as_array().into_iter().flatten()
            .filter(|entry| entry["path"].as_str() == Some(target)).cloned().collect();
        return Ok(serde_json::json!({"target":target,"results":results,"scope":"last completed compilation"}));
    }
    value.as_object_mut().map(|object| object.remove("explanations"));
    if let Ok(bytes) = fs::read(path(project, "last-run")?) {
        if let Ok(last) = serde_json::from_slice::<Value>(&bytes) { value["last_run"] = last; }
    }
    Ok(value)
}
