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

use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::sem::decls::Decls;

struct SemKeys;

impl Lint for SemKeys {
    fn meta(&self) -> &Meta {
        crate::keys_policy::metadata()
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
