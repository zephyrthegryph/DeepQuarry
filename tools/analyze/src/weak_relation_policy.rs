//! Original weak-relation declaration matcher and metadata. No typed model.
use crate::{
    lint::{Meta, Policy, RuleMeta, ScanKind},
    tree::{SourceFile, CODE_DM},
};
use std::collections::HashMap;
const HINT: &str = "a weak relation var holds a handle, not the target: read it with its generated accessor v() and write it with rel_set / rel_add / rel_remove / rel_clear. \
doc/rewrite/proposals/relations.md D5";

pub(crate) static META: Meta = Meta {
    name: "weak_raw_read",
    group: "",
    label: "weak_raw_read",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "raw",
        hint: HINT,
    }],
    allow: &[],
    lists: &[],
};

pub fn metadata() -> &'static Meta {
    &META
}
pub(crate) fn declarations<'a>(
    files: impl IntoIterator<Item = &'a SourceFile>,
) -> HashMap<String, Vec<String>> {
    let header = crate::pat!(r"^\s*CAPABILITIES\(\s*(/[\w/]+)\s*\)");
    let decl = crate::pat!(r"\bref_(?:one|many)\(\s*nameof\(\s*(\w+)\s*\)[^\n]*\bweak\s*=\s*TRUE");
    let mut out: HashMap<String, Vec<String>> = HashMap::new();
    for f in files {
        if !f.rel.ends_with(".dm") {
            continue;
        }
        let mut owner: Option<String> = None;
        for line in f.code().lines() {
            if let Some(c) = header.captures(line) {
                owner = Some(c.s(1).to_string());
                continue;
            }
            if !line.starts_with(char::is_whitespace) && !line.trim().is_empty() {
                owner = None;
            }
            let Some(o) = owner.as_ref() else { continue };
            if let Some(c) = decl.captures(line) {
                let types = out.entry(c.s(1).to_string()).or_default();
                if !types.contains(o) {
                    types.push(o.clone());
                }
            }
        }
    }
    out
}
