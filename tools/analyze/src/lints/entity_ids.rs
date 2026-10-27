//! `entity_ids`: an ad-hoc id scheme for naming an entity (doc/rewrite/proposals/relations.md D9, "One handle").
//!
//! An entity has one deletion-safe, round-stable name: its handle, `ref_token(D)` (resolved with `resolve_token(h)`,
//! `code/engine/time/handles.dm`). A handle never resolves to whatever reuses a deleted datum's slot, is text (so it keys a plain
//! list), and is already the engine's name for an entity everywhere (timers, I/O callbacks, relations, prompts). A second scheme
//! for the same purpose (a counter, a REF text) is a name nothing clears or checks: it outlives its entity or names the next one.
//!
//! Rules:
//! * `counter_id`: an id minted from a counter, `X++` / `++X` where the counter's name says it is an id (`*uid*`, `id`, `*_id`,
//!   `next_*id`, `*_id_counter`, `*_id_ticker`, `id_assign`). Name the entity by `ref_token()`; a player-facing serial or record number
//!   that is data, not a way to find the entity again, keeps its site with `// ALLOW(entity_ids): <why it is not a handle>`.
//! * `ref_key`: a `REF()` / `ref()` text embedded in a list key (`L["[REF(x)]"]`, `L -= "a-[REF(x)]"`): the stored-text form `ref_text`
//!   does not see. Key the list by `ref_token(x)`.
//!
//! The engine (which implements the handles and keeps ordering serials), tests and generated output are exempt by path
//! (`[lint.entity_ids] exempt_prefixes`). A shrink-only baseline seeded when the lint was added.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat::Pat;
use crate::tree::{SourceFile, CODE_DM};

const H_COUNTER: &str = "do not mint an entity id from a counter: ref_token(D) is the one deletion-safe, round-stable handle (resolve_token(h) finds the entity \
again, null once it is gone). A serial that is player-facing data keeps its site with ALLOW(entity_ids) and a reason. doc/rewrite/proposals/relations.md D9";
const H_REF_KEY: &str = "do not key a list by a REF() text: it outlives its entity and can name the next one at that address; key it by ref_token(D). \
doc/rewrite/proposals/relations.md D9";

static META: Meta = Meta {
    name: "entity_ids",
    group: "",
    label: "entity_ids",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Sites {
        baseline: "tools/ci/entity_ids_baseline.txt",
        header: &[
            "Ad-hoc entity ids: counters minted as ids and REF() text list keys (doc/rewrite/proposals/relations.md D9). rule<TAB>file<TAB>normalized line.",
            "Shrink-only: after a sweep run `analyze baseline --update --lint entity_ids`; it drops fixed sites and never adds one.",
        ],
        banned: &[],
    },
    rules: &[RuleMeta { name: "counter_id", hint: H_COUNTER }, RuleMeta { name: "ref_key", hint: H_REF_KEY }],
    allow: &[],
    lists: &[],
};

struct EntityIds {
    /// `++name` or `name++` (with an optional `GLOB.` / `src.` receiver); group 1 or 2 is the counter's name.
    counter: Pat,
    /// An id-shaped counter name.
    id_name: Pat,
    /// A REF()/ref() text as a list index, or removed from a list by its key (`+=` on text is a concatenation, an href more often than not).
    ref_key: Vec<Pat>,
}

impl EntityIds {
    fn new() -> EntityIds {
        EntityIds {
            counter: Pat::new(r"(?:\+\+\s*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)|(?<![\w.])(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*\+\+)"),
            id_name: Pat::new(r"(?i)(?:uid|^id$|_id$|^next_\w*id$|_id_(?:counter|ticker)$|^id_assign$)"),
            ref_key: vec![
                Pat::new(r#"\[\s*"[^"\n]*\[\s*(?:REF|ref)\("#),
                Pat::new(r#"(?<![+|])-=\s*"[^"\n]*\[\s*(?:REF|ref)\("#),
            ],
        }
    }

    fn counter_id(&self, line: &str) -> bool {
        self.counter.captures_iter(line).iter().any(|c| {
            let name = c.get(1).or_else(|| c.get(2)).unwrap_or("");
            self.id_name.is_match(name)
        })
    }
}

/// The raw line without a trailing `//` comment that sits outside a string.
fn strip_comment(line: &str) -> &str {
    let bytes = line.as_bytes();
    let mut in_str = false;
    let mut depth = 0usize; // `[...]` embeds inside a string
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if in_str => i += 1,
            b'"' if depth == 0 => in_str = !in_str,
            b'[' if in_str => depth += 1,
            b']' if in_str && depth > 0 => depth -= 1,
            b'/' if !in_str && bytes.get(i + 1) == Some(&b'/') => return &line[..i],
            _ => {}
        }
        i += 1;
    }
    line
}

impl Lint for EntityIds {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let code = f.code();
        let raw = f.raw();
        for (i, line) in code.lines().enumerate() {
            let n = i + 1;
            let t = line.trim_start();
            if t.starts_with('#') || t.is_empty() {
                continue;
            }
            // An id is often minted inside a string embed ("DQ-[next_id++]") and a REF() key is one, both blanked in the code view:
            // read the raw line, its comment removed.
            let r = strip_comment(raw.line(n));
            if r.contains("++") && self.counter_id(r) {
                out.site("counter_id", n);
                continue;
            }
            if (r.contains("REF(") || r.contains("ref(")) && self.ref_key.iter().any(|p| p.is_match(r)) {
                out.site("ref_key", n);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(EntityIds::new());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counters_named_as_ids() {
        let l = EntityIds::new();
        for hit in [
            "\tc_uid = cell_uid++",
            "\tGLOB.file_uid++",
            "\tcontract.id = \"DQ-[next_contract_id++]\"",
            "\tid = id_assign++",
            "\tbrowser_id = \"[base]-[GLOB.managed_browser_id_ticker++]\"",
            "\t\tid++",
            "\tsrc.id = next_id++",
        ] {
            assert!(l.counter_id(hit), "{hit}");
        }
        for miss in ["\tidx++", "\tgid++", "\tserial = ++next_serial", "\ttimes_idle++", "\tL[++L.len] = x", "\tvalid++"] {
            assert!(!l.counter_id(miss), "{miss}");
        }
    }

    #[test]
    fn ref_text_keys() {
        let l = EntityIds::new();
        for hit in [
            "\tGLOB.sleep_audited[\"[REF(D)]\"] = TRUE",
            "\treturn GLOB.log[\"[REF(thing)]|[rule.type]\"] || 0",
            "\t\tGLOB.panels -= \"[REF(a)]-[REF(b)]\"",
        ] {
            assert!(l.ref_key.iter().any(|p| p.is_match(strip_comment(hit))), "{hit}");
        }
        for miss in ["\tmap_name = \"overmap_[REF(src)]_map\"", "\tdat += \"<a href='byond://?src=[REF(src)];x=1'>X</a>\"", "\tL[ref_token(D)] = TRUE", "\tx = 1 // L[\"[REF(D)]\"]"] {
            assert!(!l.ref_key.iter().any(|p| p.is_match(strip_comment(miss))), "{miss}");
        }
    }
}
