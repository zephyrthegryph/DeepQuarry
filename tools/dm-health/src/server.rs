//! Loopback-only report viewer and saved-snapshot API.
use percent_encoding::percent_decode_str;
use std::error::Error;
use std::fs;
use std::path::Path;
use tiny_http::{Header, Response, Server, StatusCode};

fn recent_reports(dir: &Path) -> Vec<String> {
    let mut names: Vec<_> = fs::read_dir(dir)
        .into_iter()
        .flatten()
        .filter_map(Result::ok)
        .filter_map(|entry| entry.file_name().into_string().ok())
        .filter(|name| name.starts_with("dm-health-") && name.ends_with(".json"))
        .collect();
    names.sort();
    names
        .into_iter()
        .rev()
        .take(6)
        .collect::<Vec<_>>()
        .into_iter()
        .rev()
        .collect()
}

fn safe_report_name(name: &str) -> bool {
    name.starts_with("dm-health-")
        && name.ends_with(".json")
        && name
            .chars()
            .all(|ch| ch.is_ascii_alphanumeric() || matches!(ch, '-' | '_' | '.'))
}

fn source_path(root: &Path, encoded: &str) -> Option<std::path::PathBuf> {
    let decoded = percent_decode_str(encoded).decode_utf8().ok()?;
    let relative = Path::new(decoded.as_ref());
    if relative.is_absolute()
        || relative
            .components()
            .any(|component| !matches!(component, std::path::Component::Normal(_)))
        || !matches!(relative.extension()?.to_str()?, "dm" | "dme")
    {
        return None;
    }
    let canonical_root = root.canonicalize().ok()?;
    let source = root.join(relative).canonicalize().ok()?;
    if source.starts_with(canonical_root) {
        Some(source)
    } else {
        None
    }
}

fn readme_path(root: &Path, encoded: &str) -> Option<std::path::PathBuf> {
    let decoded = percent_decode_str(encoded).decode_utf8().ok()?;
    let relative = Path::new(decoded.as_ref());
    if relative.is_absolute()
        || relative
            .components()
            .any(|component| !matches!(component, std::path::Component::Normal(_)))
    {
        return None;
    }
    let canonical_root = root.canonicalize().ok()?;
    let directory = root.join(relative).canonicalize().ok()?;
    if !directory.starts_with(&canonical_root) {
        return None;
    }
    fs::read_dir(directory)
        .ok()?
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .eq_ignore_ascii_case("readme.md")
        })
        .filter_map(|entry| entry.path().canonicalize().ok())
        .find(|path| path.starts_with(&canonical_root) && path.is_file())
}

pub fn serve(root: &Path, dir: &Path, port: u16) -> Result<(), Box<dyn Error + Send + Sync>> {
    let server = Server::http(("127.0.0.1", port))?;
    println!("DM Health viewer: http://127.0.0.1:{port}/");
    for request in server.incoming_requests() {
        let url = request.url().split('?').next().unwrap_or("/");
        let (status, mime, body) = match url {
            "/" | "/index.html" => (
                200,
                "text/html; charset=utf-8",
                include_bytes!("../viewer/index.html").to_vec(),
            ),
            "/style.css" => (
                200,
                "text/css; charset=utf-8",
                include_bytes!("../viewer/style.css").to_vec(),
            ),
            "/app.js" => (
                200,
                "text/javascript; charset=utf-8",
                include_bytes!("../viewer/app.js").to_vec(),
            ),
            "/api/index" => (
                200,
                "application/json",
                serde_json::to_vec(&recent_reports(dir))?,
            ),
            path if path.starts_with("/api/source/") => match source_path(root, &path[12..]) {
                Some(source) => match fs::read(source) {
                    Ok(data) => (200, "text/plain; charset=utf-8", data),
                    Err(_) => (404, "text/plain", b"Source not found".to_vec()),
                },
                None => (400, "text/plain", b"Invalid source path".to_vec()),
            },
            path if path.starts_with("/api/readme/") => match readme_path(root, &path[12..]) {
                Some(source) => match fs::read(source) {
                    Ok(data) => (200, "text/plain; charset=utf-8", data),
                    Err(_) => (404, "text/plain", b"README not found".to_vec()),
                },
                None => (404, "text/plain", b"README not found".to_vec()),
            },
            path if path.starts_with("/api/report/") => {
                let name = &path[12..];
                if safe_report_name(name) {
                    match fs::read(dir.join(name)) {
                        Ok(data) => (200, "application/json", data),
                        Err(_) => (404, "text/plain", b"Report not found".to_vec()),
                    }
                } else {
                    (400, "text/plain", b"Invalid report name".to_vec())
                }
            }
            _ => (404, "text/plain", b"Not found".to_vec()),
        };
        let header = Header::from_bytes("Content-Type", mime).expect("static content type header");
        request.respond(
            Response::from_data(body)
                .with_status_code(StatusCode(status))
                .with_header(header),
        )?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rejects_report_path_traversal() {
        assert!(safe_report_name("dm-health-20260923T120000Z.json"));
        assert!(!safe_report_name("../../secret.json"));
        assert!(!safe_report_name("dm-health-..\\secret.json"));
    }
    #[test]
    fn rejects_source_path_traversal() {
        let root = std::env::current_dir().unwrap();
        assert!(source_path(&root, "..%2Fsecret.dm").is_none());
        assert!(source_path(&root, "C:%5Csecret.dm").is_none());
        assert!(source_path(&root, "tools/dm-health/src/server.rs").is_none());
        assert!(readme_path(&root, "..%2Fsecret").is_none());
    }
}
