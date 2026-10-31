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
use crate::sem::decls::Decls;
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


struct SemKeys;

impl Lint for SemKeys {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self,cx:&Cx,out:&mut Sink){
        let decls=Decls::get(cx.tree);
        let markers:Vec<_>=decls.markers.iter().map(|m|crate::declare_policy::Marker{
            name:&m.name,rel:&m.rel,line:m.line,body:&m.body,args:&m.args,
            body_offset:m.body_offset,line_starts:&m.line_starts,
        }).collect();
        let input=crate::keys_policy::ScanInput{
            keys:crate::keys_policy::Input{markers:&markers,entry_ops:&decls.entry_ops},
            defines:&decls.defines,key_refs:&decls.key_refs,bad_sources:&decls.bad_sources,
        };
        crate::keys_policy::scan_keys(cx,&input,out,|system|crate::sem::gen::system_vars(cx.tree,system),crate::sem::gen::system_types);
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SemKeys);
}
