//! Banned legacy names: a hard ban, no baseline. Each entry of `[lint.legacy_forms.lists] banned` in tools/ci/lint_scopes.toml is
//! `name = hint`; any mention of the name in code (a call, a definition, a member) fails with that hint. When a legacy form is deleted,
//! its names go on the list so it cannot come back.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};

static META: Meta = Meta {
    name: "legacy_forms",
    group: "",
    label: "legacy_forms",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[RuleMeta { name: "banned_name", hint: "the form was deleted: use its replacement (the hint after the name, in [lint.legacy_forms.lists] banned of tools/ci/lint_scopes.toml)" }],
    allow: &[],
    lists: &["banned", "banned_outside"],
};

struct LegacyForms;

fn is_word(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

impl Lint for LegacyForms {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        scan_outside(cx, f, out);
        let banned: Vec<(&str, &str)> = cx.list("banned").iter().map(|e| e.split_once('=').map(|(n, h)| (n.trim(), h.trim())).unwrap_or((e.trim(), ""))).collect();
        if banned.is_empty() {
            return;
        }
        for (number, line) in f.code().numbered() {
            let b = line.as_bytes();
            for (name, hint) in &banned {
                let mut from = 0;
                while let Some(p) = line[from..].find(name) {
                    let at = from + p;
                    let end = at + name.len();
                    if (at == 0 || !is_word(b[at - 1])) && (end >= b.len() || !is_word(b[end])) {
                        out.site_msg("banned_name", number, format!("{} is gone: {}", name, hint));
                        break;
                    }
                    from = end;
                }
            }
        }
    }
}

/// `banned_outside` entries are `name @ prefix;prefix = hint`: the name is gone everywhere except under the listed path prefixes (the
/// folders that still have callers). Shrink the prefixes as callers convert; delete the entry's prefixes entirely when none remain.
fn scan_outside(cx: &Cx, f: &SourceFile, out: &mut Sink) {
    for entry in cx.list("banned_outside") {
        let Some((left, hint)) = entry.split_once('=') else { continue };
        let Some((name, prefixes)) = left.split_once('@') else { continue };
        let name = name.trim();
        if prefixes.split(';').map(str::trim).any(|p| !p.is_empty() && f.rel.starts_with(p)) {
            continue;
        }
        for (number, line) in f.code().numbered() {
            let b = line.as_bytes();
            let mut from = 0;
            while let Some(p) = line[from..].find(name) {
                let at = from + p;
                let end = at + name.len();
                if (at == 0 || !is_word(b[at - 1])) && (end >= b.len() || !is_word(b[end])) {
                    out.site_msg("banned_name", number, format!("{} is gone here: {}", name, hint.trim()));
                    break;
                }
                from = end;
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(LegacyForms);
}
