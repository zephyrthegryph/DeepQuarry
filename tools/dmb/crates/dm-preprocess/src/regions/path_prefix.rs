//! Unify only Windows filesystem spellings with ordinary path semantics.
use std::path::PathBuf;

#[cfg(not(windows))]
pub(super) fn equivalent_prefix(path: PathBuf) -> PathBuf {
    path
}

#[cfg(windows)]
pub(super) fn equivalent_prefix(path: PathBuf) -> PathBuf {
    use std::path::{Component, Prefix};
    let mut components = path.components();
    let replacement = match components.next() {
        Some(Component::Prefix(prefix)) => match prefix.kind() {
            Prefix::VerbatimDisk(drive) => format!("{}:", char::from(drive)),
            // Device namespaces and UNC authority remain unchanged.
            _ => return path,
        },
        _ => return path,
    };
    // Verbatim names may mean something different under ordinary Win32 rules.
    // Never erase that distinction for trailing dots/spaces, streams or devices.
    for component in components.clone() {
        if let Component::Normal(name) = component {
            let Some(name) = name.to_str() else {
                return path;
            };
            let stem = name.split('.').next().unwrap_or("").to_ascii_uppercase();
            let device = matches!(stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
                || ["COM", "LPT"].iter().any(|prefix| {
                    stem.strip_prefix(*prefix).is_some_and(|suffix| {
                        suffix.len() == 1 && matches!(suffix.as_bytes()[0], b'1'..=b'9')
                    })
                });
            if name.ends_with('.') || name.ends_with(' ') || name.contains(':') || device {
                return path;
            }
        }
    }
    let mut normalized = PathBuf::from(replacement);
    for component in components {
        normalized.push(component.as_os_str());
    }
    normalized
}
