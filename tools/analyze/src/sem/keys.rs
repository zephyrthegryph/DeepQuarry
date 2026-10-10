//! Key resolution: op keys, capability keys, stat, stage and source ids.
//!
//! Stats, tracked vars, capability and tag keys, op keys, sources, stages and messages are schema:
//! declared once and resolved by the build (doc/rewrite/final_api.html section 4). The DM compiler
//! cannot check a marker's arguments (`CAPABILITIES(...)` expands to nothing), so every id and
//! key that sits inside one, and every string-literal key passed to `extend/without/configure/
//! perform_op/on_op/...`, is resolved here against what the tree declares.
//!
//! What counts as declared:
//!
//! | Kind | Declared by |
//! |---|---|
//! | stat id `STAT_<NAME>` | `STAT(T, name, ...)`, or a `#define STAT_X` |
//! | source id `SRC_<NAME>` | `SOURCE_DEF(name)`, or a `#define SRC_X` |
//! | stage id `STAGE_<GROUP>_<NAME>` | `STAGE_DEF(group, name)`, or a `#define` |
//! | capability id `CAP_<X>` | `CAPABILITY_DEF/TYPE(name, CAP_X, ...)`, or a `#define CAP_X` |
//! | capability key `name` | the same marker's first argument |
//! | capability state id `<NAME>_<KEY>` | `cap_keys(CAP_X, KEY = ...)` for the capability named by `CAP_X` |
//! | op key `cap.op` / `op` | an `op("name", ...)` entry inside a capability marker (`cap.name`) or a `CAPABILITIES` (`name`) |

use std::collections::{BTreeMap, BTreeSet, HashSet};

use super::decls::{split_args, Decls, Marker};

#[derive(Default, Debug)]
pub struct KeyIndex {
    pub stats: BTreeMap<String, (String, String)>,
    pub sources: BTreeSet<String>,
    pub stages: BTreeSet<String>,
    /// capability key (the name) -> its CAP_ id.
    pub caps: BTreeMap<String, String>,
    pub cap_ids: BTreeSet<String>,
    pub cap_state_ids: BTreeSet<String>,
    pub ops: BTreeSet<String>,
    /// "prefix|op" of the ops a capability with a selector declares: its keys read `prefix.selector.op` ("cell_bay.cell.insert").
    pub sel_ops: BTreeSet<String>,
    /// Duplicates found while indexing: (kind, name, first site, second site).
    pub duplicates: Vec<(String, String, (String, u32), (String, u32))>,
}

/// The id prefixes the build resolves. A token with one of these prefixes inside a marker must be declared.
pub const ID_PREFIXES: &[&str] = &["STAT_", "SRC_", "STAGE_", "CAP_"];

fn up(s: &str) -> String {
    s.to_uppercase()
}

impl KeyIndex {
    pub fn build(decls: &Decls) -> KeyIndex {
        let mut k = KeyIndex::default();
        let mut seen: BTreeMap<(String, String), (String, u32)> = BTreeMap::new();
        let mut note = |k: &mut KeyIndex, kind: &str, name: &str, m: &Marker| {
            let key = (kind.to_string(), name.to_string());
            match seen.get(&key) {
                Some(first) => k.duplicates.push((kind.to_string(), name.to_string(), first.clone(), (m.rel.clone(), m.line))),
                None => {
                    seen.insert(key, (m.rel.clone(), m.line));
                }
            }
        };
        for m in &decls.markers {
            match m.name.as_str() {
                "STAT" => {
                    if let (Some(t), Some(n)) = (m.args.first(), m.args.get(1)) {
                        note(&mut k, "stat", &format!("{}::{}", t, n), m);
                        k.stats.insert(format!("STAT_{}", up(n)), (t.clone(), n.clone()));
                    }
                }
                "SOURCE_DEF" => {
                    if let Some(n) = m.args.first() {
                        note(&mut k, "source", n, m);
                        k.sources.insert(format!("SRC_{}", up(n)));
                    }
                }
                "STAGE_DEF" => {
                    if let (Some(g), Some(n)) = (m.args.first(), m.args.get(1)) {
                        note(&mut k, "stage", &format!("{}/{}", g, n), m);
                        k.stages.insert(format!("STAGE_{}_{}", up(g), up(n)));
                    }
                }
                "CAPABILITY_DEF" | "CAPABILITY_TYPE" => {
                    if let (Some(n), Some(id)) = (m.args.first(), m.args.get(1)) {
                        note(&mut k, "capability", n, m);
                        k.caps.insert(n.clone(), id.clone());
                        k.cap_ids.insert(id.clone());
                        // prefix = "name" keeps the op keys of the final constructor name while the working one differs.
                        let prefix = marker_option(m, "prefix").map(|p| p.trim_matches('"').to_string()).unwrap_or_else(|| n.clone());
                        collect_ops(&m.body, Some(&prefix), &mut k.ops);
                        // A CAPABILITY_TYPE's ops are written in the `entries()` of its datum.
                        if m.name == "CAPABILITY_TYPE" {
                            let selected = marker_option(m, "key").map(|v| v != "NONE").unwrap_or(false);
                            if let Some(ty) = m.args.get(2) {
                                for (t, op) in decls.entry_ops.iter().filter(|(t, _)| t == ty) {
                                    let _ = t;
                                    k.ops.insert(format!("{}.{}", prefix, op));
                                    if selected {
                                        k.sel_ops.insert(format!("{}|{}", prefix, op));
                                    }
                                }
                            }
                        }
                    }
                }
                "CAPABILITIES" => collect_ops(&m.body, None, &mut k.ops),
                crate::sem::decls::ENTRY_PROC => collect_ops(&m.body, None, &mut k.ops),
                _ => {}
            }
        }
        // cap_keys(CAP_X, KEY = ..., ...) -> <CAPNAME>_<KEY> for the capability whose id is CAP_X.
        let by_id: BTreeMap<&String, &String> = k.caps.iter().map(|(n, id)| (id, n)).collect();
        let mut state = BTreeSet::new();
        for m in decls.markers_named("cap_keys") {
            let Some(id) = m.args.first() else { continue };
            let name = by_id.get(id).map(|n| up(n)).unwrap_or_else(|| id.trim_start_matches("CAP_").to_string());
            for a in m.args.iter().skip(1) {
                if let Some((key, _)) = a.split_once('=') {
                    state.insert(format!("{}_{}", name, up(key.trim())));
                }
            }
        }
        k.cap_state_ids = state;
        // Ops the engine itself makes: the state graph's build/undo/dismantle (stage-suffixed: `construction.build:door_wired`) and the window opener of interface() (and its ghost view, ui_observe, with observe = TRUE).
        for engine_op in ["construction.build", "construction.undo", "construction.dismantle", "ui_open", "ui_observe"] {
            k.ops.insert(engine_op.to_string());
        }
        // Ops a library proc makes (code/library/mob/silicon.dm): a silicon's plain click, which every machine and turf declares and a type takes away with without().
        for library_op in ["silicon_hand", "silicon_ui"] {
            k.ops.insert(library_op.to_string());
        }
        k
    }

    /// Whether `token` (a `STAT_X`/`SRC_X`/`STAGE_G_N`/`CAP_X` or a cap-state id) is declared by a
    /// marker or by a `#define`.
    pub fn id_resolves(&self, token: &str, defines: &HashSet<String>) -> bool {
        defines.contains(token)
            || self.stats.contains_key(token)
            || self.sources.contains(token)
            || self.stages.contains(token)
            || self.cap_ids.contains(token)
            || self.cap_state_ids.contains(token)
    }

    /// `COVER_` for a declared capability named `cover`: ids with it are capability-state ids.
    pub fn cap_state_prefixes(&self) -> Vec<String> {
        self.caps.keys().map(|n| format!("{}_", up(n))).collect()
    }

    /// The closest declared id (for a "did you mean" hint), if any is within a small edit distance.
    pub fn suggest(&self, token: &str, defines: &HashSet<String>) -> Option<String> {
        let mut best: Option<(usize, String)> = None;
        let mut consider = |c: &str| {
            if !ID_PREFIXES.iter().any(|p| c.starts_with(p)) {
                return;
            }
            let d = edit_distance(token, c);
            if d <= 3 && best.as_ref().map(|(b, _)| d < *b).unwrap_or(true) {
                best = Some((d, c.to_string()));
            }
        };
        for c in self.stats.keys().chain(self.sources.iter()).chain(self.stages.iter()).chain(self.cap_ids.iter()) {
            consider(c);
        }
        for c in defines {
            consider(c);
        }
        best.map(|(_, s)| s)
    }

    /// An op key resolves exactly, or by the part before a `:` stage chain (`construction.build:door_wired`).
    pub fn op_resolves(&self, key: &str) -> bool {
        let base = key.split(':').next().unwrap_or(key);
        if self.ops.contains(key) || self.ops.contains(base) {
            return true;
        }
        // "prefix.selector.op" of a capability with a selector ("cell_bay.cell.insert").
        let parts: Vec<&str> = base.split('.').collect();
        parts.len() == 3 && self.sel_ops.contains(&format!("{}|{}", parts[0], parts[2]))
    }

    pub fn suggest_op(&self, key: &str) -> Option<String> {
        let mut best: Option<(usize, &String)> = None;
        for o in &self.ops {
            let d = edit_distance(key, o);
            if d <= 3 && best.map(|(b, _)| d < b).unwrap_or(true) {
                best = Some((d, o));
            }
        }
        best.map(|(_, s)| s.clone())
    }
}

/// The value of `name = value` among a marker's arguments, or None.
fn marker_option(m: &Marker, name: &str) -> Option<String> {
    m.args.iter().find_map(|a| {
        let (k, v) = a.split_once('=')?;
        (k.trim() == name).then(|| v.trim().to_string())
    })
}

/// Every `op("name", ...)` in a marker body: `cap.name` inside a capability marker, `name` otherwise.
fn collect_ops(body: &str, cap: Option<&String>, out: &mut BTreeSet<String>) {
    let b = body.as_bytes();
    let mut i = 0;
    while let Some(p) = body[i..].find("op(") {
        let at = i + p;
        i = at + 3;
        // word boundary before `op`
        if at > 0 && (b[at - 1].is_ascii_alphanumeric() || b[at - 1] == b'_' || b[at - 1] == b'.') {
            continue;
        }
        let Some(close) = super::decls::matching_paren(body, at + 2) else { continue };
        let args = split_args(&body[at + 3..close]);
        if let Some(name) = args.first().and_then(|a| a.strip_prefix('"')).and_then(|a| a.strip_suffix('"')) {
            match cap {
                Some(c) => {
                    out.insert(format!("{}.{}", c, name));
                }
                None => {
                    out.insert(name.to_string());
                }
            }
        }
    }
}

/// Every identifier-like token in `text` with one of the resolved prefixes, with its byte offset.
pub fn id_tokens(text: &str, extra_prefixes: &[String]) -> Vec<(usize, String)> {
    let mut out = Vec::new();
    let b = text.as_bytes();
    let mut i = 0;
    let mut in_str = false;
    while i < b.len() {
        let c = b[i];
        if c == b'"' {
            in_str = !in_str;
            i += 1;
            continue;
        }
        if in_str || !(c.is_ascii_alphabetic() || c == b'_') {
            i += 1;
            continue;
        }
        let start = i;
        while i < b.len() && (b[i].is_ascii_alphanumeric() || b[i] == b'_') {
            i += 1;
        }
        let tok = &text[start..i];
        let prev_ok = start == 0 || !(b[start - 1] == b'.' || b[start - 1] == b'/');
        if prev_ok && (ID_PREFIXES.iter().any(|p| tok.starts_with(p)) || extra_prefixes.iter().any(|p| tok.starts_with(p.as_str()))) && tok.len() > 4 && tok.chars().all(|ch| ch.is_ascii_uppercase() || ch.is_ascii_digit() || ch == '_') {
            out.push((start, tok.to_string()));
        }
    }
    out
}

fn edit_distance(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    for i in 1..=a.len() {
        let mut cur = vec![i; b.len() + 1];
        for j in 1..=b.len() {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            cur[j] = (prev[j] + 1).min(cur[j - 1] + 1).min(prev[j - 1] + cost);
        }
        prev = cur;
    }
    prev[b.len()]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tokens_skip_strings_and_members() {
        let t = id_tokens("contributes(STAT_DENSITY, x.SRC_NOT, \"STAT_IN_STRING\", SRC_AI_CONTROL)", &[]);
        let names: Vec<&str> = t.iter().map(|(_, s)| s.as_str()).collect();
        assert_eq!(names, vec!["STAT_DENSITY", "SRC_AI_CONTROL"]);
    }

    #[test]
    fn edit_distance_basics() {
        assert_eq!(edit_distance("STAT_DENSTY", "STAT_DENSITY"), 1);
    }
}
