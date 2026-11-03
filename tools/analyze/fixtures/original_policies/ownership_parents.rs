fn implicit_roots(root: &str) -> &'static [&'static str] {
    match root {
        "/obj" | "/mob" => &["/atom/movable", "/atom", "/datum"],
        "/turf" | "/area" => &["/atom", "/datum"],
        "/atom" => &["/datum"],
        _ => &[],
    }
}

/// The type and its ancestors, nearest first, including DM's implicit roots (/obj -> /atom/movable
/// -> /atom -> /datum).
pub fn parents(path: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut root: Option<String> = None;
    let mut p = path.to_string();
    while !p.is_empty() && p.matches('/').count() >= 1 {
        out.push(p.clone());
        if p.matches('/').count() == 1 {
            root = Some(p);
            break;
        }
        let cut = p.rfind('/').unwrap();
        p.truncate(cut);
    }
    if let Some(r) = root {
        for imp in implicit_roots(&r) {
            out.push((*imp).to_string());
        }
    }
    out
}

