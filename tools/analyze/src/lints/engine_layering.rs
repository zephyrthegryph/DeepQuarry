//! Hard engine boundary to library/content/game/modules/datums: semantic provenance, not name prefixes.
//! Dynamic target values and untyped receiver chains have no static provenance and are not prohibited by this lint.
use std::collections::BTreeSet;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::CODE_DM;

const HINT: &str = "move the content-specific implementation downstream; call an actual engine-declared virtual interface, or move the foundational implementation into the engine";
static META: Meta = Meta {
    name: "engine_layering", group: "", label: "engine_layering", legacy: "",
    select: CODE_DM, scan: ScanKind::Tree, policy: Policy::Hard,
    rules: &[RuleMeta { name: "external_dependency", hint: HINT }, RuleMeta { name: "semantic_model", hint: "repair the parsed environment; engine layering cannot pass without the semantic model" }],
    allow: &[], lists: &[],
};
struct EngineLayering;
impl Lint for EngineLayering {
    fn meta(&self) -> &Meta { &META }
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files: Vec<_> = cx.files().into_iter().filter(|f| f.rel.starts_with("code/engine/")).collect();
        if files.is_empty() { return; }
        let Some(sem) = cx.sem() else {
            out.site_in_msg("semantic_model", &files[0].rel, 1, "no semantic model: engine boundary not verified"); return;
        };
        let included: BTreeSet<_> = files.iter().map(|f| f.rel.clone()).collect();
        let mut found: BTreeSet<_> = crate::sem::layering::scan(&sem, &included).into_iter().collect();
        let marker_type = regex::Regex::new(r"^(?:(?:CAPABILITIES|STAT)\s*\(\s*(/[A-Za-z_][\w/]*)|CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*))").unwrap();
        for f in files {
            let mut entries = false;
            let mut marker_owner: Option<String> = None;
            for (line, text) in f.clean().numbered() {
                if !text.starts_with('\t') && !text.starts_with(' ') && !text.trim().is_empty() {
                    entries = text.starts_with("CAPABILITIES(") || text.starts_with("STAT(") || text.starts_with("CAPABILITY_TYPE(");
                    marker_owner = marker_type.captures(text).and_then(|cap| cap.get(1).or_else(|| cap.get(2)).map(|m| m.as_str().to_string()));
                }
                found.extend(crate::sem::layering::source_paths(&sem, &f.rel, line as u32, text));
                found.extend(crate::sem::layering::source_proc_refs(&sem, &f.rel, line as u32, text, marker_owner.as_deref()));
                if entries || text.trim_start().starts_with("var/") || (text.starts_with('/') && text.contains('(')) { found.extend(crate::sem::layering::marker_calls(&sem, &f.rel, line as u32, text)); }
            }
        }
        for f in found { out.site_in_msg(f.rule, &f.file, f.line as usize, f.message); }
    }
}
pub fn register(reg: &mut Registry) { reg.add(EngineLayering); }
