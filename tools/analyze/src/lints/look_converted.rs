//! The draw sweep's ratchet (doc/rewrite/codemod_rules.md, "The draw sweep"): in a folder whose looks are all draw(look) over tracked state,
//! the legacy appearance forms stay gone. A hard ban, no baseline: each prefix of `[lint.look_converted.lists] folders` in
//! tools/ci/lint_scopes.toml is a folder that has no `update_icon()` call or override and no APPEARANCE_* / DECLARE_APPEARANCE* declaration;
//! any of them there fails. A folder joins the list once the sweep has cleared it (`look_sweep.py` reports what is left).

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::tree::{SourceFile, CODE_DM};
use crate::pat;

static META: Meta = Meta {
    name: "look_converted",
    group: "",
    label: "look_converted",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::File,
    policy: Policy::Hard,
    rules: &[
        RuleMeta {
            name: "update_icon_in_converted",
            hint: "this folder draws through draw(look): a tracked write redraws by itself (TRACKED / SETTER); state nothing publishes is a changed(src)",
        },
        RuleMeta {
            name: "legacy_appearance_in_converted",
            hint: "this folder draws through draw(look): declare the look in a draw(datum/look/look) override (look.state(), look.overlay(), look_layer())",
        },
    ],
    allow: &[],
    lists: &["folders"],
};

struct LookConverted;

impl Lint for LookConverted {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_file(&self, cx: &Cx, f: &SourceFile, out: &mut Sink) {
        let folders = cx.list("folders");
        if !folders.iter().any(|p| f.rel.starts_with(p.as_str())) {
            return;
        }
        for (number, line) in f.code().numbered() {
            if pat!(r"(?<![\w])update_icon\s*\(").is_match(line) {
                out.site_msg("update_icon_in_converted", number, "update_icon() in a converted folder".to_string());
            } else if pat!(r"^(?:APPEARANCE_[A-Z_]+|DECLARE_APPEARANCE(?:_PROC)?)\(").is_match(line) {
                out.site_msg("legacy_appearance_in_converted", number, "a legacy appearance declaration in a converted folder".to_string());
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(LookConverted);
}
