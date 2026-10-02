//! `instance_list_lint.singleton_types()` / `is_singleton()`, shared by `instance_list` and
//! `base_vars` (which imported them from it): the types that have exactly one instance, so a list
//! var on them is one list, not one per instance.
//!
//! A singleton is a type under `/datum/world_service` or `/datum/controller`, or the exact type a
//! `GLOBAL_DATUM_INIT(name, /type, new...)` creates anywhere under `code/` (bare `/datum` excluded).
//!
//! Suspected bug, kept for parity: `instance_list_lint.GLOBAL_DATUM` ends in `new` followed by a
//! literal backspace (U+0008), a `\b` that was corrupted when the file was written
//! (`git log -S` finds it in the commit that added the lint). Real source never has a backspace
//! there, so the Python never found a `GLOBAL_DATUM_INIT` type and only the two root prefixes ever
//! exempt a singleton. The pattern below carries the same `\x08`; fix both in a separate change.

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
                // The trailing `\x08` is the Python's literal backspace (see the module docs).
                for m in pat!(r"GLOBAL_DATUM_INIT\(\s*\w+\s*,\s*(/[\w/]+)\s*,\s*new\x08").captures_iter(text) {
                    types.insert(m.s(1).to_string());
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
    fn global_datum_types_need_the_pythons_backspace() {
        // Real source: the pattern never matches (the Python's `new\b` is a literal backspace).
        let real = SourceFile::from_text("code/a.dm", "GLOBAL_DATUM_INIT(x,\n\t/datum/one,\n\tnew)\nGLOBAL_DATUM_INIT(y, /datum/two, new /datum/two())\n");
        let tree = Tree::from_files(vec![]);
        assert!(singleton_types(&tree, &[&real]).is_empty());
        // With the backspace it collects, across lines, in dot-directories, never `/datum`, never maps/.
        let a = SourceFile::from_text("code/a.dm", "GLOBAL_DATUM_INIT(x,\n\t/datum/one,\n\tnew\u{8})\nGLOBAL_DATUM_INIT(y, /datum, new\u{8})\nGLOBAL_DATUM_INIT(z, /datum/two, null)\n");
        let b = SourceFile::from_text("code/.h/b.dm", "GLOBAL_DATUM_INIT(w, /datum/three, new\u{8}/datum/three())\n");
        let m = SourceFile::from_text("maps/c.dm", "GLOBAL_DATUM_INIT(v, /datum/four, new\u{8})\n");
        let got = singleton_types(&tree, &[&a, &b, &m]);
        let mut v: Vec<&String> = got.iter().collect();
        v.sort();
        assert_eq!(v, ["/datum/one", "/datum/three"]);
    }
}
