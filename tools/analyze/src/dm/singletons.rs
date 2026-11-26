//! `instance_list_lint.singleton_types()` / `is_singleton()`, shared by `instance_list` and
//! `base_vars` (which imported them from it): the types that have exactly one instance, so a list
//! var on them is one list, not one per instance.
//!
//! A singleton is a type under `/datum/world_service` or `/datum/controller`, or the exact type a
//! `GLOBAL_DATUM_INIT(name, /type, new...)` creates anywhere under `code/` (bare `/datum` excluded).
//!
//! `GLOBAL_DATUM_INIT(name, /type, new...)` needs `new` as a word. (The Python it was ported from ended the pattern in a literal backspace,
//! a corrupted `\b`, so it never found one; the port fixes that, and the sites it hid were annotated by hand.)

use std::collections::HashSet;
use std::sync::Arc;

use crate::pat;
use crate::tree::{SourceFile, Tree};

/// `SINGLETON_ROOTS`.
pub const SINGLETON_ROOTS: &[&str] = &["/datum/world_service", "/datum/controller"];

/// `singleton_types()`: the exact types some `GLOBAL_DATUM_INIT(name, /type, new...)` creates. The
/// Python walked every `.dm` under `code/` with `os.walk` (dot-files and dot-directories included),
/// so `files` must be a hidden-inclusive selection; files outside `code/` are ignored.
pub fn singleton_types(tree: &Tree, files: &[&SourceFile]) -> Arc<HashSet<String>> {
    let mut h = blake3::Hasher::new();
    h.update(b"singleton-types");
    for f in files {
        h.update(&f.fkey.to_le_bytes());
    }
    let key = h.finalize().to_hex().to_string();
    tree.memo(&key, || {
        let mut types: HashSet<String> = HashSet::new();
        for f in files {
            if !f.rel.starts_with("code/") {
                continue;
            }
            let text = f.raw().text.as_str();
            if text.contains("GLOBAL_DATUM_INIT") {
                for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\b").captures_iter(text) {
                    types.insert(m.s(1).to_string());
                }
            }
            if text.contains("SYSTEM_DEF(") {
                // SYSTEM_DEF(x) declares the one instance of /datum/system/x.
                for m in pat!(r"(?m)^SYSTEM_DEF\((\w+)\)").captures_iter(text) {
                    types.insert(format!("/datum/system/{}", m.s(1)));
                }
            }
        }
        types.remove("/datum");
        types
    })
}

/// `is_singleton(type_path, globals_)`.
pub fn is_singleton(type_path: &str, globals: &HashSet<String>) -> bool {
    globals.contains(type_path)
        || SINGLETON_ROOTS.iter().any(|r| type_path == *r || (type_path.starts_with(r) && type_path.as_bytes().get(r.len()) == Some(&b'/')))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn singleton_roots_match_whole_segments() {
        let g: HashSet<String> = ["/datum/solo".to_string()].into_iter().collect();
        assert!(is_singleton("/datum/solo", &g));
        assert!(!is_singleton("/datum/solo/child", &g));
        assert!(is_singleton("/datum/world_service", &g));
        assert!(is_singleton("/datum/world_service/x/y", &g));
        assert!(is_singleton("/datum/controller", &g));
        assert!(!is_singleton("/datum/controllers", &g));
        assert!(!is_singleton("/datum/world_servicex", &g));
    }

    #[test]
    fn global_datum_types_are_collected() {
        // Across lines, in dot-directories, never `/datum`, never maps/.
        let tree = Tree::from_files(vec![]);
        let a = SourceFile::from_text("code/a.dm", "GLOBAL_DATUM_INIT(x,\n\t/datum/one,\n\tnew)\nGLOBAL_DATUM_INIT(y, /datum, new)\nGLOBAL_DATUM_INIT(z, /datum/two, null)\nGLOBAL_DATUM_INIT(n, /datum/newt, newbie())\n");
        let b = SourceFile::from_text("code/.h/b.dm", "GLOBAL_DATUM_INIT(w, /datum/three, new /datum/three())\n");
        let m = SourceFile::from_text("maps/c.dm", "GLOBAL_DATUM_INIT(v, /datum/four, new)\n");
        let got = singleton_types(&tree, &[&a, &b, &m]);
        let mut v: Vec<&String> = got.iter().collect();
        v.sort();
        assert_eq!(v, ["/datum/one", "/datum/three"]);
    }
}
