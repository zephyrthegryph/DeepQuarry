//! `map_edits`: a var a map edits on a placed atom must exist.
//!
//! The map loader reports an unknown var only when that map is loaded, and a submap or template is loaded when a player or an
//! admin asks for it, so a var that was renamed, moved or removed leaves its edits silently dead until then. This checks every
//! `/type{var = value}` of the maps a round can load against the semantic model. An edit is known when the type has the var (its
//! own, inherited or built in) or a type trait took it over (a `var_names` row of a `/datum/entry_engine/type_trait`, which the
//! loader writes to the holder's trait). Palettes and reference maps are mapping aids: nothing loads them.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::CODE_DM;
use std::collections::{BTreeMap, BTreeSet};

static META: Meta = Meta {
    name: "map_edits",
    group: "",
    label: "map_edits",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta {
            name: "unknown_var",
            hint: "the map edits a var the type does not have, so the value is lost when the map loads: give the loader a mapping (world/proc/map_edit_moved_var) or fix the map",
        },
        RuleMeta { name: "unknown_type", hint: "the map places a type that no longer exists: restore the path or fix the map" },
    ],
    allow: &[],
    lists: &[],
};

/// Mapping aids nothing loads.
const SKIP: &[&str] = &["maps/palettes/", "maps/_templates_and_guidance/", "maps/~map_system/"];
/// The vars world/proc/map_edit_moved_var() carries over by name.
const MOVED: &[&str] = &["light_range", "light_power", "light_color", "emagged", "cap_state", "req_access_txt", "req_one_access_txt"];
const SKIP_NAMES: &[&str] = &["1mapping_palette.dmm", "SouthernCrossRef.dmm"];

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

/// (type, var) -> (first line) for every edit in one map's text.
fn edits(text: &str) -> BTreeMap<(String, String), usize> {
    let mut found = BTreeMap::new();
    let mut current: Option<String> = None;
    let mut number = 0;
    for line in text.lines() {
        number += 1;
        let t = line.trim();
        if let Some(open) = t.find('{').filter(|_| current.is_none() && t.starts_with('/')) {
            let ty = t[..open].to_string();
            let rest = &t[open + 1..];
            for piece in rest.trim_end_matches([',', ')']).trim_end_matches('}').split(';') {
                if let Some((name, _)) = piece.split_once(" = ") {
                    found.entry((ty.clone(), name.trim().to_string())).or_insert(number);
                }
            }
            if !t.contains('}') {
                current = Some(ty);
            }
            continue;
        }
        if let Some(ty) = &current {
            if let Some((name, _)) = t.split_once(" = ") {
                if name.chars().all(|c| c.is_alphanumeric() || c == '_') {
                    found.entry((ty.clone(), name.to_string())).or_insert(number);
                }
            }
            if t.contains('}') && !t.contains('"') || t.ends_with('}') || t.ends_with("},") || t.ends_with("})") {
                current = None;
            }
        }
    }
    found
}

/// Old path -> parent type for every row of a registered variant family: the registry in variant_tables.dm names each family's table
/// (`/parent = "dq_variants_x"`), and the table's rows (`"key" = list(`) are the paths `parent/key` the map loader still resolves.
fn variant_aliases(cx: &Cx) -> BTreeMap<String, String> {
    let registry = crate::pat_match!(r#"^\t(/[\w/]+) = "(dq_variants_\w+)","#);
    let table = crate::pat_match!(r"^GLOBAL_LIST_INIT\((dq_variants_\w+), *list\(");
    let row = crate::pat_match!(r#"^\t"([^"]+)" = list\("#);
    let mut parents: BTreeMap<String, String> = BTreeMap::new();
    let mut rows: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for f in cx.all_files() {
        if !f.rel.starts_with("code/content/") || !f.rel.ends_with(".dm") {
            continue;
        }
        let mut current: Option<String> = None;
        for (_, line) in f.raw().numbered() {
            if let Some(m) = registry.captures(line) {
                parents.insert(m.s(2).to_string(), m.s(1).to_string());
            } else if let Some(m) = table.captures(line) {
                current = Some(m.s(1).to_string());
            } else if let (Some(name), Some(m)) = (&current, row.captures(line)) {
                rows.entry(name.clone()).or_default().push(m.s(1).to_string());
            } else if line.starts_with("))") {
                current = None;
            }
        }
    }
    let mut out = BTreeMap::new();
    for (table, parent) in &parents {
        for key in rows.get(table).into_iter().flatten() {
            out.insert(format!("{}/{}", parent, key), parent.clone());
        }
    }
    out
}

impl Lint for MapEdits {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let Some(sem) = cx.sem() else { return };
        let slots = crate::pat_match!(r"^sparse\(/[\w/]+, *(\w+)");
        let mut sparse: BTreeSet<String> = BTreeSet::new();
        let mut trait_vars: BTreeSet<String> = BTreeSet::new();
        for f in cx.all_files() {
            if !f.rel.ends_with(".dm") {
                continue;
            }
            for (_, line) in f.raw().numbered() {
                if let Some(m) = slots.captures(line) {
                    sparse.insert(m.s(1).to_string());
                }
                if line.trim_start().starts_with("var_names = list(") {
                    let body = line.trim_start().trim_start_matches("var_names = list(");
                    for row in body.split(',') {
                        if let Some((name, _)) = row.split_once('=') {
                            trait_vars.insert(name.trim().trim_matches('"').to_string());
                        }
                    }
                }
            }
        }
        let aliases = variant_aliases(cx);
        let mut maps = Vec::new();
        dmm_files(&cx.tree.root.join("maps"), &mut maps);
        maps.sort();
        for path in maps {
            let rel = path.strip_prefix(&cx.tree.root).unwrap_or(&path).to_string_lossy().replace('\\', "/");
            if SKIP.iter().any(|s| rel.starts_with(s)) || SKIP_NAMES.iter().any(|s| rel.ends_with(s)) {
                continue;
            }
            let Ok(bytes) = std::fs::read(&path) else { continue };
            let text = String::from_utf8_lossy(&bytes);
            for ((ty, var), number) in edits(&text) {
                // A path of a collapsed variant family (code/content/variants/variant_alias.dm) loads as its parent type, so its edits are the parent's.
                let ty = aliases.get(&ty).cloned().unwrap_or(ty);
                if MOVED.contains(&var.as_str()) || trait_vars.contains(&var) || sparse.contains(&var) || sem.var_decl(&ty, &var).is_some() {
                    continue;
                }
                if sem.ty(&ty).is_none() {
                    out.site_decl("unknown_type", &rel, number, ty.clone(), format!("{}::{}", ty, var));
                    continue;
                }
                out.site_decl("unknown_var", &rel, number, format!("{}.{}", ty, var), format!("{}::{}", ty, var));
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(MapEdits);
}
