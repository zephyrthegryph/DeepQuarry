fn implicit_parent(path: &str) -> Option<&'static str> {
    match path {
        "/obj" | "/mob" => Some("/atom/movable"),
        "/atom/movable" => Some("/atom"),
        "/turf" | "/area" => Some("/atom"),
        "/atom" => Some("/datum"),
        _ => None,
    }
}

pub fn ancestors(path: &str) -> Vec<String> {
    let trimmed = path.trim_end_matches('/');
    let parts: Vec<&str> = trimmed.split('/').collect();
    (2..=parts.len()).map(|k| parts[..k].join("/")).collect()
}

/// `path` and every ancestor, nearest first, including DM's implicit parents; ends with `/datum`
/// for every datum path (not for "/", `/client`, `/list`, ...).
pub fn lineage(path: &str) -> Vec<String> {
    let mut out: Vec<String> = ancestors(path).into_iter().rev().collect();
    let mut root: Option<String> = out.last().cloned();
    while let Some(r) = root.clone() {
        match implicit_parent(&r) {
            Some(p) => {
                out.push(p.to_string());
                root = Some(p.to_string());
            }
            None => break,
        }
    }
    const NON_DATUM: &[&str] = &[
        "/client",
        "/world",
        "/list",
        "/savefile",
        "/regex",
        "/icon",
        "/image",
        "/sound",
        "/matrix",
        "/database",
        "/exception",
        "/generator",
        "/mutable_appearance",
        "/particles",
        "/dm_filter",
        "/callee",
    ];
    if let Some(last) = out.last() {
        if last != "/datum" && !NON_DATUM.contains(&last.as_str()) {
            out.push("/datum".to_string());
        }
    }
    out
}
