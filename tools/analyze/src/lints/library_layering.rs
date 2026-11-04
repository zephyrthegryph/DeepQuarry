//! Library boundary to content/game/modules/datums: code/library/ may name the engine, itself and code/domains/world_model/ (the base type
//! declarations), never content. The same provenance walk as `engine_layering` (semantic, not name prefixes), with the library as the
//! scanned layer. A shrink-only ratchet over `tools/ci/library_layering_baseline.txt`: a library file moves clear of content and its rows go.
use std::collections::BTreeSet;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::layering::Layer;
use crate::tree::CODE_DM;

const HINT: &str = "library code may not name content: move the content-specific implementation to code/content/, declare a virtual proc in the library and implement it there, or move the shared type into code/domains/world_model/";
static META: Meta = Meta {
    name: "library_layering", group: "", label: "library_layering", legacy: "",
    select: CODE_DM, scan: ScanKind::Tree,
    policy: Policy::Sites {
        baseline: "tools/ci/library_layering_baseline.txt",
        header: &[
            "Library files that name content (library may not reference content). rule<TAB>file<TAB>normalized line.",
            "`analyze check --lint library_layering` fails on a site not listed here.",
            "Shrink-only: after a sweep, `analyze baseline --update --lint library_layering`.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "external_dependency", hint: HINT }, RuleMeta { name: "semantic_model", hint: "repair the parsed environment; library layering cannot pass without the semantic model" }],
    allow: &[], lists: &[],
};
struct LibraryLayering;
impl Lint for LibraryLayering {
    fn meta(&self) -> &Meta { &META }
    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files: Vec<_> = cx.files().into_iter().filter(|f| f.rel.starts_with("code/library/")).collect();
        if files.is_empty() { return; }
        let Some(sem) = cx.sem() else {
            out.site_in_msg("semantic_model", &files[0].rel, 1, "no semantic model: library boundary not verified"); return;
        };
        let layer = Layer::Library;
        let included: BTreeSet<_> = files.iter().map(|f| f.rel.clone()).collect();
        let mut found: BTreeSet<_> = crate::sem::layering::scan_in(&sem, &included, layer).into_iter().collect();
        let marker_type = regex::Regex::new(r"^(?:(?:CAPABILITIES|STAT)\s*\(\s*(/[A-Za-z_][\w/]*)|CAPABILITY_TYPE\s*\(\s*[^,]+,\s*[^,]+,\s*(/[A-Za-z_][\w/]*))").unwrap();
        for f in files {
            let mut entries = false;
            let mut marker_owner: Option<String> = None;
            for (line, text) in f.clean().numbered() {
                if !text.starts_with('\t') && !text.starts_with(' ') && !text.trim().is_empty() {
                    entries = text.starts_with("CAPABILITIES(") || text.starts_with("STAT(") || text.starts_with("CAPABILITY_TYPE(");
                    marker_owner = marker_type.captures(text).and_then(|cap| cap.get(1).or_else(|| cap.get(2)).map(|m| m.as_str().to_string()));
                }
                found.extend(crate::sem::layering::source_paths_in(&sem, &f.rel, line as u32, text, layer));
                found.extend(crate::sem::layering::source_proc_refs_in(&sem, &f.rel, line as u32, text, marker_owner.as_deref(), layer));
                if entries || text.trim_start().starts_with("var/") || (text.starts_with('/') && text.contains('(')) { found.extend(crate::sem::layering::marker_calls_in(&sem, &f.rel, line as u32, text, layer)); }
            }
        }
        for f in found { out.site_in_msg(f.rule, &f.file, f.line as usize, f.message); }
    }
}
pub fn register(reg: &mut Registry) { reg.add(LibraryLayering); }
