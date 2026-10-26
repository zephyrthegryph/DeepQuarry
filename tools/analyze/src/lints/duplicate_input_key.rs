//! `duplicate_input_key`: a type declares each input entry once.
//!
//! `click_on()`, `double_click_on()`, `drag_onto()`, `drag_over()`, `hover()` and `tooltip()` each build an entry with a fixed key (`input:drag_onto`, ...),
//! and a type's table holds one entry per key: a second declaration of the same key (in the same CAPABILITIES block, or in another block of the same type
//! in another file) silently replaces the first, so its handler never runs. One handler per input: it dispatches the cases itself and answers
//! `INPUT_FALLTHROUGH` for the ones it does not take. A hard ban, no baseline.

use std::collections::HashMap;

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::CODE_DM;

const HINT: &str = "one handler per input key for a type: merge the handlers into one proc that tries each case in priority order and answers INPUT_FALLTHROUGH for the cases it does not take";

static META: Meta = Meta {
    name: "duplicate_input_key",
    group: "",
    label: "duplicate_input_key",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "duplicate_input_key", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct DuplicateInputKey {
    block: Pat,
    entry: Pat,
}

/// The input entries declared at the top level of `CAPABILITIES` blocks: (type, key, file, line), in file order.
fn declared(cx: &Cx, block: &Pat, entry: &Pat) -> Vec<(String, String, String, usize)> {
    let mut found = Vec::new();
    for f in cx.files() {
        let mut current: Option<String> = None;
        for (number, line) in f.code().numbered() {
            if line.trim().is_empty() {
                continue;
            }
            if !line.starts_with(['\t', ' ']) {
                current = block.captures(line.trim_end()).map(|m| m.s(1).to_string());
                continue;
            }
            let Some(ty) = &current else { continue };
            if !line.starts_with('\t') || line.starts_with("\t\t") {
                continue;
            }
            if let Some(m) = entry.captures(line.trim_start()) {
                found.push((ty.clone(), m.s(1).to_string(), f.rel.clone(), number));
            }
        }
    }
    found
}

impl Lint for DuplicateInputKey {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let mut first: HashMap<(String, String), (String, usize)> = HashMap::new();
        for (ty, key, rel, line) in declared(cx, &self.block, &self.entry) {
            match first.get(&(ty.clone(), key.clone())) {
                Some((r0, l0)) => out.site_in_msg("duplicate_input_key", &rel, line, format!("{} declares {}() twice (first at {}:{}): the later one replaces the earlier", ty, key, r0, l0)),
                None => {
                    first.insert((ty, key), (rel, line));
                }
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(DuplicateInputKey {
        block: Pat::new(r"^CAPABILITIES\(\s*(/[\w/]+)\s*\)"),
        entry: Pat::new(r"^(click_on|double_click_on|drag_onto|drag_over|hover|tooltip)\("),
    });
}
