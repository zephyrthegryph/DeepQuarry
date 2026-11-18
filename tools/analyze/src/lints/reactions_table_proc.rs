//! `reactions()` is a /datum/system's table proc and nobody else's: a hard ban, no baseline, no ALLOW.
//!
//! Every other type states what it reacts to in its `CAPABILITIES(T)` block (`every(...)`, `on_change(...)`, `on_notice(...)`,
//! `extend(/datum/act/x, instead(...))`; doc/rewrite/final_api.html sections 10 and 17). A definition of `reactions()` fails unless its owner is a
//! `/datum/system/...` type or the base declaration (`/datum/proc/reactions`). Both spellings are read: the path form
//! (`/obj/x/reactions()` at the start of a line) and the bare form (`reactions()` indented under a `/obj/x` header). The unit tests that
//! drive the reaction engine itself declare fixtures with it, so they are exempt by path (`[lint.reactions_table_proc] exempt_prefixes`).

use crate::raw_fixture_policy::PatternApi as _;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::pat;
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "declare it in the type's CAPABILITIES(T) block: every(interval, then(PROC_REF(x)), when = nameof(v)), on_change(nameof(v), ANY, then(PROC_REF(x))), on_notice(/datum/notice/x, then(PROC_REF(x))), extend(/datum/act/x, instead(then(PROC_REF(x)))); only a /datum/system declares reactions()";

static META: Meta = Meta {
    name: crate::allow_registry_fields::reactions_table_proc::SCOPE_META_0.name,
    group: crate::allow_registry_fields::reactions_table_proc::SCOPE_META_0.group,
    label: "reactions_table_proc",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "table_proc", hint: HINT }],
    allow: crate::allow_registry_fields::reactions_table_proc::ALLOW_0,
    lists: crate::allow_registry_fields::reactions_table_proc::SCOPE_META_0.lists,
};

struct ReactionsTableProc;

/// Whether `owner` (the type a `reactions()` is defined on) may declare one.
fn owner_allowed(owner: &str) -> bool {
    owner == "/datum" || owner == "/datum/proc" || owner == "/datum/system" || owner.starts_with("/datum/system/")
}

/// The owners of every `reactions()` definition in `lines`, with its line number.
fn definitions<'a>(lines: impl Iterator<Item = (usize, &'a str)>) -> Vec<(usize, String)> {
    definitions_using(lines,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy definition allocation has no admission refusal")
}
fn definitions_using<'a>(lines: impl Iterator<Item = (usize, &'a str)>,fixture:&crate::raw_fixture_policy::Fixture<'_>) -> Result<Vec<(usize, String)>,String> {
    let mut found = Vec::new();
    let mut header = String::new();
    for (number, line) in lines {
        // `/obj/x/reactions()`, `/datum/proc/reactions()`: the owner is everything before the final segment.
        if let Some(m) = fixture.captures(&fixture.pattern(r"^(/[\w/]*?)/(?:proc/)?reactions\(\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^(/[\w/]*?)/(?:proc/)?reactions\(\)")),line)? {
            fixture.push(&mut found,(number, fixture.own(m.s(1))?))?;
            continue;
        }
        // `reactions()` under a `/obj/x` header (a type block).
        if fixture.pattern(r"^\t+(?:proc/)?reactions\(\)",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^\t+(?:proc/)?reactions\(\)")).is_match(line) {
            fixture.push(&mut found,(number, fixture.own(&header)?))?;
            continue;
        }
        if let Some(m) = fixture.captures(&fixture.pattern(r"^(/[\w/]+)\s*(?://.*)?$",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"^(/[\w/]+)\s*(?://.*)?$")),line)? {
            header = fixture.own(m.s(1))?;
        } else if !line.starts_with('\t') && !line.trim().is_empty() && !line.starts_with("//") && !line.starts_with('#') {
            header.clear();
        }
    }
    Ok(found)
}

impl Lint for ReactionsTableProc {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let rows=if let Some(fixture)=cx.fixture{match definitions_using(f.code().numbered(),fixture){Ok(rows)=>rows,Err(message)=>{fixture.note_scan(Err(message));return}}}else{definitions(f.code().numbered())};
        for (number, owner) in rows {
            if owner_allowed(&owner) {
                continue;
            }
            out.site_msg("table_proc", number, format!("{} defines reactions(): only a /datum/system does", if owner.is_empty() { "a type" } else { owner.as_str() }));
        }
    }

    fn selftest(&self) -> Result<String, String> {
        self.selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
    }

    fn selftest_with_fixture(&self, fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
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
        let found = definitions_using(text.lines().enumerate().map(|(i, l)| (i + 1, l)),fixture)?;
        let wrong: Vec<(usize, String)> = fixture.collect(found.into_iter().filter(|(_, owner)| !owner_allowed(owner)))?;
        let want = fixture.collect([(6, fixture.own("/obj/effect/hotspot")?), (9, fixture.own("/datum/song")?)])?;
        if wrong != want {
            return Err(fixture.detail(format_args!("expected {:?}, got {:?}", want, wrong))?);
        }
        Ok(fixture.own("reactions() is allowed on /datum/proc and /datum/system/*, refused on /obj/effect/hotspot (path form) and /datum/song (bare form); handle_reactions() is no definition")?)
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(ReactionsTableProc);
}
