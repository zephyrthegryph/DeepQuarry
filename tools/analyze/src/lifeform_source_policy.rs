//! Shared original file-only lifecycle scanners. Semantic Lifeforms stays separate.
use std::collections::BTreeMap;
use crate::lint::{Cx,Lint,Meta,Policy,Registry,RuleMeta,ScanKind,Sink};
use crate::tree::{SourceFile,CODE_DM};

static ALLOWS: Meta = Meta {
    name: crate::allow_registry_fields::lifeform_allows::SCOPE_META_0.name,
    group: crate::allow_registry_fields::lifeform_allows::SCOPE_META_0.group,
    label: "lifeform_allows",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "allow_matches_form", hint: "the reason names what a lifecycle form declares: convert the site (rolls(), param()/make(), expire()/spent()/consumed()/destroyed()/dissolved()/replace_with(), lives_while(), tooltip()/click_on()/drag_onto(), with_actor()) instead of keeping it" }],
    allow: &[],
    lists: crate::allow_registry_fields::lifeform_allows::SCOPE_META_0.lists,
};

static HATCHES: Meta = Meta {
    name: crate::allow_registry_fields::escape_hatches::SCOPE_META_0.name,
    group: crate::allow_registry_fields::escape_hatches::SCOPE_META_0.group,
    label: "escape_hatches",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "init_allow", hint: "an Initialize() kept with ALLOW(init/...): declare what it sets (rolls(), param(), contains(), starts_as(), derives(), registry())" },
        RuleMeta { name: "lifecycle_allow", hint: "a qdel kept with ALLOW(lifecycle): end it with a verb that says why (spent(), consumed(), destroyed(), dissolved(), expire(), replace_with())" },
        RuleMeta { name: "usr_allow", hint: "usr kept with ALLOW(sys_usr_outside_verb): take the actor from the input (click_on(), drag_onto(), hover(), tooltip()) or run under with_actor()" },
        RuleMeta { name: "qdel_content", hint: "qdel() is the engine's: content ends a thing with spent(), consumed(), destroyed(), dissolved(), expire(), replace_with(), consume() or slot_clear()" },
        RuleMeta { name: "usr_content", hint: "usr is the engine's: content takes its actor as an argument (click_on()/drag_onto()/hover()/tooltip() hand it one)" },
    ],
    allow: &[],
    lists: crate::allow_registry_fields::escape_hatches::SCOPE_META_0.lists,
};

/// The engine and the paths whose qdel and usr are the mechanism: they do not count against content.
const ENGINE_PREFIXES: &[&str] = &[
    "code/engine/",
    "code/library/",
    "code/library/lifecycle/",
    "code/world/systems/garbage.dm",
    "code/world/kernel/", // the Kernel is the engine's one loop (its target home is code/world/kernel): its boot step and watchdog clear usr
    "code/__defines/", "code/defines/engine/", "code/defines/library/", "code/defines/host/", "code/defines/base/", "code/defines/content/",
    "code/tests/unit_tests/",
    "code/tests/benchmarks/",
    "code/tests/",
    "code/world/tgs/",
];

pub(crate) fn is_engine(rel: &str) -> bool {
    ENGINE_PREFIXES.iter().any(|p| rel.starts_with(p))
}

/// (pattern, form) pairs: an ALLOW reason matching the pattern describes what the form declares.
type FormReason = (&'static str, regex::Regex, &'static str);

pub(crate) fn form_reasons() -> &'static [FormReason] {
    static REASONS: std::sync::LazyLock<[FormReason; 11]> = std::sync::LazyLock::new(|| {
        let r = |p: &str| regex::Regex::new(p).expect("form reason pattern");
        [
            ("init", r(r"(?i)rolled at random|random(ly)? (roll|pick|chosen)"), "rolls()"),
            ("init", r(r"(?i)constructor argument"), "param() and make()"),
            ("lifecycle", r(r"(?i)\b(expires?|timed (delete|deletion|removal)|times out)\b"), "expire()"),
            ("lifecycle", r(r"(?i)\b(used up|single[- ]use|spent)\b"), "spent()"),
            ("lifecycle", r(r"(?i)\b(eaten|drunk|consumed by)\b"), "consumed()"),
            ("lifecycle", r(r"(?i)\b(dissolve[sd]?|melts?|melted)\b"), "dissolved()"),
            ("lifecycle", r(r"(?i)\b(replaced by|becomes (a|an|the))\b"), "replace_with()"),
            ("sys_usr_outside_verb", r(r"(?i)\btooltip"), "tooltip()"),
            ("sys_usr_outside_verb", r(r"(?i)\b(native|hud|screen)\b.*\bclick"), "click_on()"),
            ("sys_usr_outside_verb", r(r"(?i)\b(drag|drop)\b"), "drag_onto()"),
            ("sys_usr_outside_verb", r(r"(?i)\b(callback|proc ?call|admin call)\b"), "with_actor()"),
        ]
    });
    REASONS.as_slice()
}

/// What the CAPABILITIES blocks declare for the checks: per type, its params, required params, built_from and per_type vars.
struct LifeformAllows;

impl Lint for LifeformAllows {
    fn meta(&self) -> &Meta {
        &ALLOWS
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if f.rel.starts_with("code/engine/_generated/") {
            return;
        }
        let reasons = form_reasons();
        let raw = f.raw();
        for number in 1..=raw.num_lines() {
            let line = raw.line(number);
            let Some(a) = crate::allow::parse(line) else { continue };
            for (lint, pat, form) in reasons {
                if a.names.contains(*lint) && pat.is_match(&a.reason) {
                    out.site_msg("allow_matches_form", number, format!("ALLOW({}) \"{}\": {} declares this", lint, a.reason, form));
                    break;
                }
            }
        }
    }
}

struct EscapeHatches;

impl Lint for EscapeHatches {
    fn meta(&self) -> &Meta {
        &HATCHES
    }

    fn scan_file(&self, _cx: &Cx, f: &SourceFile, out: &mut Sink) {
        if is_engine(&f.rel) || f.rel.starts_with("maps/") {
            return;
        }
        let raw = f.raw();
        let clean = f.clean();
        let qdel = crate::pat!(r"(?<![\w.])qdel\s*\(");
        let usr = crate::pat!(r"(?<![\w.])usr(?!\w)");
        let verbs = verb_lines(f);
        let mut counts: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
        for number in 1..=raw.num_lines() {
            if let Some(a) = crate::allow::parse(raw.line(number)) {
                if a.names.contains("init") {
                    counts.entry("init_allow").or_default().push(number);
                }
                if a.names.contains("lifecycle") {
                    counts.entry("lifecycle_allow").or_default().push(number);
                }
                if a.names.contains("sys_usr_outside_verb") {
                    counts.entry("usr_allow").or_default().push(number);
                }
            }
            let code = clean.line(number);
            if code.contains("qdel") && qdel.is_match(code) && !code.trim_start().starts_with('#') {
                counts.entry("qdel_content").or_default().push(number);
            }
            if code.contains("usr") && usr.is_match(code) && !verbs.contains(&number) && !code.trim_start().starts_with('#') {
                counts.entry("usr_content").or_default().push(number);
            }
        }
        for (kind, lines) in counts {
            for number in lines {
                let rel = f.rel.clone();
                out.site_keyed(kind, &rel, number, f.line(number).trim().to_string(), kind);
            }
        }
    }
}

/// The lines of a verb's body (where `usr` is the verb's own caller): a proc under /verb/ or one with a `set name`-style line, and the body of
/// an ADMIN_VERB / DECLARE_*VERB macro. The same reading as sys/usr_use.
fn verb_lines(f: &SourceFile) -> std::collections::HashSet<usize> {
    let set_stmt = crate::pat!(r"^\s*set\s+(?:name|category|src|desc|hidden|popup_menu|instant)\b");
    let verb_macro = crate::pat!(r"^(?:ADMIN_VERB\w*|DECLARE_\w*VERB\w*)\(");
    let clean = f.clean();
    let mut out = std::collections::HashSet::new();
    for proc in crate::dm::dx::procs_in(f) {
        let end = proc.body_start + proc.body_len.max(1) - 1;
        let head = clean.line(proc.line);
        let verb = head.split('(').next().unwrap_or("").contains("/verb/") || (0..proc.body_len).any(|k| set_stmt.is_match(clean.line(proc.body_start + k)));
        if verb {
            out.extend(proc.line..=end);
        }
    }
    let n = clean.num_lines();
    let mut i = 1;
    while i <= n {
        if verb_macro.is_match(clean.line(i)) {
            out.insert(i);
            let mut j = i + 1;
            while j <= n && (clean.line(j).starts_with('\t') || clean.line(j).starts_with(' ') || clean.line(j).trim().is_empty()) {
                out.insert(j);
                j += 1;
            }
            i = j;
            continue;
        }
        i += 1;
    }
    out
}

pub(crate) fn register_allows(reg:&mut Registry){reg.add(LifeformAllows);}
pub(crate) fn register_hatches(reg:&mut Registry){reg.add(EscapeHatches);}
