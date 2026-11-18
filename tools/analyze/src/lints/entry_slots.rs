//! `entry_slots`: a declaration helper takes a fixed number of positional entries, then its options by name. A call with more positional
//! arguments than that does not fail: DM puts the extra one into the next parameter, which is the first option (`when(cond, a, b, c, d, e, f, g)`
//! sets `reads = g`; `on_change(cond, edge, ...)`'s ninth sets `at_most`). More entries than slots go in one list (a bundle), which the helper flattens.
//!
//! The slots are ENTRY_SLOTS (p1..p6, code/engine/declare/entries.dm) after the helper's leading parameters; `captures` has eight field slots.
//! The limits below are the positional arguments a call may have, leading parameters included.

use crate::raw_fixture_policy::PatternApi as _;
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

const HINT: &str = "a helper has six entry slots (eight field slots for captures()), then named options: a seventh positional argument lands in the first option. Put the entries in one list: when(cond, list(a, b, c, ...))";

/// (helper, positional arguments it takes before its named options).
const LIMITS: &[(&str, usize)] = &[
    ("stage", 7),
    ("when", 7),
    ("extend", 7),
    ("on_change", 8),
    ("on_notice", 7),
    ("on_op", 7),
    ("instead", 6),
    ("while_slotted", 7),
    ("ruined", 7),
    ("captures", 8),
];

static META: Meta = Meta {
    name: crate::allow_registry_fields::entry_slots::SCOPE_META_0.name,
    group: crate::allow_registry_fields::entry_slots::SCOPE_META_0.group,
    label: "entry_slots",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "positional_overflow", hint: HINT }],
    allow: crate::allow_registry_fields::entry_slots::ALLOW_0,
    lists: crate::allow_registry_fields::entry_slots::SCOPE_META_0.lists,
};

struct EntrySlots;

/// The helpers called in `text` (comments and strings already blanked) with more positional arguments than slots: (line, helper, found, limit).
fn overflows(f:&SourceFile)->Vec<(usize,&'static str,usize,usize)>{
    overflows_using(f,&crate::raw_fixture_policy::Fixture::legacy()).expect("legacy overflow scan has no admission refusal")
}
fn overflows_using(f:&SourceFile,fixture:&crate::raw_fixture_policy::Fixture<'_>)->Result<Vec<(usize,&'static str,usize,usize)>,String>{
    let call = fixture.pattern(r"(?<![\w./:])(stage|when|extend|on_change|on_notice|on_op|instead|while_slotted|ruined|captures)\s*\(",crate::raw_fixture_policy::PatternMode::Search,||crate::pat!(r"(?<![\w./:])(stage|when|extend|on_change|on_notice|on_op|instead|while_slotted|ruined|captures)\s*\("));
    let named = fixture.pattern(r"\s*[A-Za-z_]\w*\s*=(?!=)",crate::raw_fixture_policy::PatternMode::Match,||crate::pat_match!(r"\s*[A-Za-z_]\w*\s*=(?!=)"));
    let clean = f.clean();
    let text = clean.text.as_str();
    let mut found = Vec::new();
    for m in fixture.captures_iter(&call,text)? {
        let name = m.s(1);
        let Some(&(helper, limit)) = LIMITS.iter().find(|(n, _)| *n == name) else { continue };
        let Some(spans) = fixture.arg_spans(text, m.end(0) - 1)? else { continue };
        let positional = spans
            .iter()
            .filter(|(a, b)| {
                let arg = text.get(*a..*b).unwrap_or("");
                !arg.trim().is_empty() && !named.is_match(arg)
            })
            .count();
        if positional > limit {
            fixture.push(&mut found,(clean.line_of(m.start(0)), helper, positional, limit))?;
        }
    }
    Ok(found)
}

impl Lint for EntrySlots {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.starts_with("code/engine/_generated/") {
            return;
        }
        let rows=if let Some(fixture)=cx.fixture{match overflows_using(f,fixture){Ok(rows)=>rows,Err(message)=>{fixture.note_scan(Err(message));return}}}else{overflows(f)};
        for (line, helper, found, limit) in rows {
            out.site_msg("positional_overflow", line, format!("{}() takes {} positional arguments, this call has {}: the extra ones land in its named options", helper, limit, found));
        }
    }

    fn selftest(&self) -> Result<String, String> {
        self.selftest_with_fixture(&crate::raw_fixture_policy::Fixture::legacy())
    }

    fn selftest_with_fixture(&self, fixture: &crate::raw_fixture_policy::Fixture<'_>) -> Result<String, String> {
        let text = "CAPABILITIES(/obj/a)\n\twhen(x, a, b, c, d, e, f)\n\twhen(x, a, b, c, d, e, f, g)\n\ton_change(nameof(v), ENTER, a, b, c, d, e, f, at_most = 1)\n\ton_change(nameof(v), ENTER, a, b, c, d, e, f, g)\n\tcaptures(a, b, c, d, e, f, g, h, resume = LATEST)\n\tinstead(a, b, c, d, e, f, g, order = 1)\n\t// when(x, a, b, c, d, e, f, g)\n\tx = \"when(1,2,3,4,5,6,7,8)\"\n";
        let f = fixture.file("code/a.dm", text)?;
        let got: Vec<(usize, &str)> = fixture.collect(overflows_using(&f,fixture)?.into_iter().map(|(l, h, _, _)| (l, h)))?;
        if got == [(3, "when"), (5, "on_change"), (7, "instead")] {
            Ok(String::new())
        } else {
            Err(fixture.detail(format_args!("unexpected overflows {:?}", got))?)
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(EntrySlots);
}
