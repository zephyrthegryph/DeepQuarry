//! `sem/keys`: key resolution (E5, doc/rewrite/final_api.html sections 4 and 19).
//!
//! A string key or id that does not resolve to a declared identifier is a build error. The DM
//! compiler cannot see inside a declaration marker (`CAPABILITIES(...)` expands to nothing), so
//! this resolves, against what the tree declares (`sem::keys`):
//!
//! * `unresolved_id`: a `STAT_`/`SRC_`/`STAGE_`/`CAP_` id inside a marker nobody declares;
//! * `unresolved_op`: a literal op key in `extend/without/on_op/shares_effects/above/perform_op`;
//! * `unresolved_capability`: a literal capability key in `configure`;
//! * `text_source`: `source = "text"` or `source = null` on a hold/grant/release (a source is a
//!   datum or a `SRC_*`);
//! * `duplicate_declaration`: the same stat, source, stage or capability declared twice;
//! * `accessor_var`: a `SYSTEM_ACCESSOR(system, name, nameof(var))` whose var is not on the system.
//!
//! Text only: it reads the declarations and calls, not the AST, so it costs a scan, not a parse.

use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::sem::decls::{Decls, KeyKind};
use crate::sem::keys::{id_tokens, KeyIndex};
use crate::tree::CODE_DM;

const H_ID: &str = "declare it with STAT/SOURCE_DEF/STAGE_DEF/CAPABILITY_DEF (or #define it), or fix the spelling";
const H_OP: &str = "declare the op (op(\"name\", ...) in its capability) or fix the key; perform_op with an unknown key is an error, not a no-op";
const H_CAP: &str = "declare the capability (CAPABILITY_DEF/CAPABILITY_TYPE name) or fix the key";
const H_SRC: &str = "a source is a datum or a SOURCE_DEF flyweight (SRC_X): text and null are errors";
const H_DUP: &str = "declare each stat, source, stage and capability once";
const H_ACC: &str = "name a var the system declares: SYSTEM_ACCESSOR(system, accessor, nameof(var))";

static META: Meta = Meta {
    name: "sem/keys",
    group: "sem",
    label: "keys",
    legacy: "",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[
        RuleMeta { name: "unresolved_id", hint: H_ID },
        RuleMeta { name: "unresolved_op", hint: H_OP },
        RuleMeta { name: "unresolved_capability", hint: H_CAP },
        RuleMeta { name: "text_source", hint: H_SRC },
        RuleMeta { name: "duplicate_declaration", hint: H_DUP },
        RuleMeta { name: "accessor_var", hint: H_ACC },
    ],
    allow: &["keys"],
    lists: &[],
};

/// Markers whose bodies may only name declared ids.
const CHECKED_MARKERS: &[&str] = &["CAPABILITIES", "CAPABILITY_DEF", "CAPABILITY_TYPE", "cap_keys", crate::sem::decls::ENTRY_PROC, "STATE_GRAPH", "RESOURCE_DEF", "SCHEMA", "ACTION"];

struct SemKeys;

impl Lint for SemKeys {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let decls = Decls::get(cx.tree);
        let idx = KeyIndex::build(&decls);
        let allowed = |out: &mut Sink, rel: &str, line: u32| -> bool {
            match cx.tree.get(rel) {
                Some(f) => out.allowed(f, line as usize, "keys"),
                None => false,
            }
        };

        let cap_prefixes = idx.cap_state_prefixes();
        for m in &decls.markers {
            if !CHECKED_MARKERS.contains(&m.name.as_str()) || cx.exempt(&m.rel) {
                continue;
            }
            for (off, tok) in id_tokens(&m.body, &cap_prefixes) {
                if idx.id_resolves(&tok, &decls.defines) {
                    continue;
                }
                let line = m.line_at(off);
                if allowed(out, &m.rel, line) {
                    continue;
                }
                let msg = match idx.suggest(&tok, &decls.defines) {
                    Some(s) => format!("`{}` is not declared; did you mean `{}`?", tok, s),
                    None => format!("`{}` is not declared", tok),
                };
                out.site_in_msg("unresolved_id", &m.rel, line as usize, msg);
            }
        }

        for r in decls.key_refs.iter().filter(|r| !cx.exempt(&r.rel)) {
            match r.kind {
                KeyKind::Op if !idx.op_resolves(&r.key) => {
                    if allowed(out, &r.rel, r.line) {
                        continue;
                    }
                    let msg = match idx.suggest_op(&r.key) {
                        Some(s) => format!("op key \"{}\" in {}() is not declared; did you mean \"{}\"?", r.key, r.call, s),
                        None => format!("op key \"{}\" in {}() is not declared", r.key, r.call),
                    };
                    out.site_in_msg("unresolved_op", &r.rel, r.line as usize, msg);
                }
                KeyKind::Capability if !idx.caps.contains_key(&r.key) => {
                    if allowed(out, &r.rel, r.line) {
                        continue;
                    }
                    out.site_in_msg("unresolved_capability", &r.rel, r.line as usize, format!("capability key \"{}\" in {}() is not declared", r.key, r.call));
                }
                _ => {}
            }
        }

        for (rel, line, v) in decls.bad_sources.iter().filter(|(rel, _, _)| !cx.exempt(rel)) {
            if allowed(out, rel, *line) {
                continue;
            }
            out.site_in_msg("text_source", rel, *line as usize, format!("source = {} is not a datum or a SRC_*", v));
        }

        for (kind, name, first, second) in &idx.duplicates {
            if allowed(out, &second.0, second.1) {
                continue;
            }
            out.site_in_msg("duplicate_declaration", &second.0, second.1 as usize, format!("{} `{}` is already declared at {}:{}", kind, name, first.0, first.1));
        }

        // SYSTEM_ACCESSOR(system, name, nameof(var)): the var must be on the system.
        for m in decls.markers_named("SYSTEM_ACCESSOR") {
            let (Some(system), Some(name), Some(key)) = (m.args.first(), m.args.get(1), m.args.get(2)) else { continue };
            let Some(var) = key.trim().strip_prefix("nameof(").and_then(|s| s.strip_suffix(')')).map(|s| s.trim().to_string()) else { continue };
            let (known, vars) = crate::sem::gen::system_vars(cx.tree, system);
            if !vars.contains(&var) && !allowed(out, &m.rel, m.line) {
                let msg = if known {
                    format!("accessor `{}`: system `{}` has no var `{}`", name, system, var)
                } else {
                    format!("accessor `{}`: no system type for `{}` (looked for {})", name, system, crate::sem::gen::system_types(system).join(", "))
                };
                out.site_in_msg("accessor_var", &m.rel, m.line as usize, msg);
            }
        }
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemKeys);
}
