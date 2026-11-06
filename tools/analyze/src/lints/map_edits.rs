//! `map_edits`: a var a map edits on a placed atom must exist.
//!
//! The map loader reports an unknown var only when that map is loaded, and a submap or template is loaded when a player or an
//! admin asks for it, so a var that was renamed, moved or removed leaves its edits silently dead until then. This checks every
//! `/type{var = value}` of the maps a round can load against the semantic model. An edit is known when the type has the var (its
//! own, inherited or built in) or a type trait took it over (a `var_names` row of a `/datum/entry_engine/type_trait`, which the
//! loader writes to the holder's trait). Palettes and reference maps are mapping aids: nothing loads them.

use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::map_edits_policy::{self as policy, Declaration};

struct MapEdits;

fn dmm_files(root: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
    let Ok(dir) = std::fs::read_dir(root) else { return };
    for entry in dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            dmm_files(&path, out);
        } else if path.extension().is_some_and(|e| e == "dmm") {
            out.push(path);
        }
    }
}

impl Lint for MapEdits {
    fn meta(&self) -> &Meta {
        &policy::META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else { return };
        let mut names = policy::CodeNames::default();
        for file in cx.all_files() {
            names.add_file(&file.rel, file.raw().numbered().map(|(_, line)| line));
        }
        let names = names.finish();
        let mut maps = Vec::new();
        dmm_files(&cx.tree.root.join("maps"), &mut maps);
        maps.sort();
        for path in maps {
            let rel = path.strip_prefix(&cx.tree.root).unwrap_or(&path).to_string_lossy().replace('\\', "/");
            if policy::skips_map(&rel) {
                continue;
            }
            let Ok(bytes) = std::fs::read(&path) else { continue };
            let declaration = |ty: &str, var: &str| {
                Ok::<_, std::convert::Infallible>(if sem.var_decl(ty, var).is_some() {
                    Declaration::Variable
                } else if sem.ty(ty).is_some() {
                    Declaration::Type
                } else {
                    Declaration::Missing
                })
            };
            names.scan_map(&rel, &bytes, declaration, out).unwrap();
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(MapEdits);
}
