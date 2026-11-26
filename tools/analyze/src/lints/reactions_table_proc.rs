//! `reactions()` is a /datum/system's table proc and nobody else's: a hard ban, no baseline, no ALLOW.
//!
//! Every other type states what it reacts to in its `CAPABILITIES(T)` block (`every(...)`, `on_change(...)`, `on_notice(...)`,
//! `extend(/datum/act/x, instead(...))`; doc/rewrite/final_api.html sections 10 and 17). A definition of `reactions()` fails unless its owner is a
//! `/datum/system/...` type or the base declaration (`/datum/proc/reactions`). Both spellings are read: the path form
//! (`/obj/x/reactions()` at the start of a line) and the bare form (`reactions()` indented under a `/obj/x` header). The unit tests that
//! drive the reaction engine itself declare fixtures with it, so they are exempt by path (`[lint.reactions_table_proc] exempt_prefixes`).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "declare it in the type's CAPABILITIES(T) block: every(interval, then(PROC_REF(x)), when = nameof(v)), on_change(nameof(v), ANY, then(PROC_REF(x))), on_notice(/datum/notice/x, then(PROC_REF(x))), extend(/datum/act/x, instead(then(PROC_REF(x)))); only a /datum/system declares reactions()";

static META: Meta = Meta {
    name: "reactions_table_proc",
    group: "",
    label: "reactions_table_proc",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "table_proc", hint: HINT }],
    allow: &[],
    lists: &[],
};

struct ReactionsTableProc;

/// Whether `owner` (the type a `reactions()` is defined on) may declare one.
fn owner_allowed(owner: &str) -> bool {
    owner == "/datum" || owner == "/datum/proc" || owner == "/datum/system" || owner.starts_with("/datum/system/")
}

/// The owners of every `reactions()` definition in `lines`, with its line number.
fn definitions<'a>(lines: impl Iterator<Item = (usize, &'a str)>) -> Vec<(usize, String)> {
    let mut found = Vec::new();
    let mut header = String::new();
    for (number, line) in lines {
        // `/obj/x/reactions()`, `/datum/proc/reactions()`: the owner is everything before the final segment.
        if let Some(m) = pat!(r"^(/[\w/]*?)/(?:proc/)?reactions\(\)").captures(line) {
            found.push((number, m.s(1).to_string()));
            continue;
        }
        // `reactions()` under a `/obj/x` header (a type block).
        if pat!(r"^\t+(?:proc/)?reactions\(\)").is_match(line) {
            found.push((number, header.clone()));
            continue;
        }
        if let Some(m) = pat!(r"^(/[\w/]+)\s*(?://.*)?$").captures(line) {
            header = m.s(1).to_string();
        } else if !line.starts_with('\t') && !line.trim().is_empty() && !line.starts_with("//") && !line.starts_with('#') {
            header.clear();
        }
    }
    found
}

impl Lint for ReactionsTableProc {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        for (number, owner) in definitions(f.code().numbered()) {
            if owner_allowed(&owner) {
                continue;
            }
            out.site_msg("table_proc", number, format!("{} defines reactions(): only a /datum/system does", if owner.is_empty() { "a type" } else { owner.as_str() }));
        }
    }

    fn selftest(&self) -> Result<String, String> {
        let text = "\
/datum/proc/reactions()\n\
\treturn list()\n\
/datum/system/air/reactions()\n\
\t. = ..()\n\
/datum/system/air/pumps/reactions()\n\
/obj/effect/hotspot/reactions()\n\
\t. = ..()\n\
/datum/song\n\
\treactions()\n\
\t\t. = ..()\n\
/datum/system/lobby\n\
\treactions()\n\
/mob/living/proc/handle_reactions()\n";
        let found = definitions(text.lines().enumerate().map(|(i, l)| (i + 1, l)));
        let wrong: Vec<(usize, String)> = found.into_iter().filter(|(_, owner)| !owner_allowed(owner)).collect();
        let want = vec![(6, "/obj/effect/hotspot".to_string()), (9, "/datum/song".to_string())];
        if wrong != want {
            return Err(format!("expected {:?}, got {:?}", want, wrong));
        }
        Ok("reactions() is allowed on /datum/proc and /datum/system/*, refused on /obj/effect/hotspot (path form) and /datum/song (bare form); handle_reactions() is no definition".into())
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReactionsTableProc);
}
