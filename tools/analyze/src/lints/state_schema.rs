//! Port of `tools/ci/state_schema_lint.py`'s CI check (roadmap L1, doc/rewrite/state.md section 2).
//!
//! A saved var (not `tmp`/`static`/`global`/`const`) on a latent-safe type, or one of its
//! ancestors, whose declared type is an object must be `tmp`, have a codec in `state_codecs()`,
//! hold a registry singleton, or have an ownership kind. The `--vars` / `--report` modes of the
//! script are not lints and are not ported.

use std::collections::HashSet;

use crate::dm::schema::{chain, OwnershipKinds, Schema};
use crate::lint::{Cx, Lint, Meta, Policy, Registry, RuleMeta, ScanKind, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::CODE_DM;

static META: Meta = Meta {
    name: "state_schema",
    group: "",
    label: "state_schema",
    legacy: "tools/ci/state_schema_lint.py",
    select: CODE_DM,
    scan: ScanKind::Tree,
    policy: Policy::Hard,
    rules: &[RuleMeta {
        name: "schema",
        hint: "make it tmp, give it a codec in state_codecs(), or give it an ownership kind (own_set/rel_set/proto_set)",
    }],
    allow: &[],
    lists: &[],
};

struct StateSchema;

impl Lint for StateSchema {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        let files = cx.all_files();
        let schema = Schema::get(cx.tree, &files);
        let kinds = OwnershipKinds::get(cx.tree, &files);

        let safe_types = schema.safe_types();
        let mut used: HashSet<String> = HashSet::new();
        let mut checked: HashSet<(String, String)> = HashSet::new();
        let mut problems = 0usize;
        for t in &safe_types {
            for a in chain(t) {
                let Some(vars) = schema.decls.get(&a) else { continue };
                for v in vars {
                    if !v.saved() || !v.holds_ref() || v.registry(&schema.registry) {
                        continue;
                    }
                    if schema.has_codec(&v.name, t) {
                        continue;
                    }
                    let entry = format!("{}/{}", a, v.name);
                    if kinds.kind(&a, &v.name).is_some() {
                        used.insert(entry);
                        continue;
                    }
                    if !checked.insert((a.clone(), v.name.clone())) {
                        continue;
                    }
                    problems += 1;
                    out.site_in_msg(
                        "schema",
                        &v.path,
                        v.line,
                        format!(
                            "{} holds a reference ({}{}) and is saved on latent-safe {}",
                            entry,
                            if v.is_list { "list of " } else { "" },
                            v.vtype,
                            t
                        ),
                    );
                }
            }
        }
        out.note(format!(
            "state schema lint: {} latent-safe types, {} vars with an ownership codec, {} problems",
            safe_types.len(),
            used.len(),
            problems
        ));
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/state_schema_lint.py"],
            old_raw: &[],
            blank: &[],
            parse: ParseKind::FileLine,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(StateSchema);
}
