//! Port of `tools/ci/interactions_lint.py`: DECLARE_INTERACTIONS shadowing
//! (doc/rewrite/interactions.md sec 5a).
//!
//! `DECLARE_INTERACTIONS(T, ...)` generates `T/get_interactions()`, which REPLACES every ancestor's
//! specs. This fails on any `DECLARE_INTERACTIONS` (or hand-written `get_interactions()` override)
//! on a type whose ancestor also declares, unless the site carries
//! `// ALLOW(interactions): <reason>`. Ancestry is by type path.
//!
//! Quirks kept: a type declared in two places keeps only the LAST one seen (files in path order);
//! the nearest declaring ancestor decides, and an annotated site still stops the walk up; the
//! annotation is read on every declaring line, whether or not that site survives the overwrite.


use serde::{Deserialize, Serialize};

use crate::lint::{AllowUse,Cx,Lint,Meta,Registry,Sink};
use crate::parity::{ParseKind, Parity};

use crate::raw_tree_interactions_policy as policy;

/// One file's `DECLARE_INTERACTIONS` / `get_interactions()` sites: `(type path, line, allowed)`.
#[derive(Serialize, Deserialize, Default, PartialEq)]
struct Facts {
    decls: Vec<(String, u32, bool)>,
    uses: Vec<AllowUse>,
}

struct Interactions;

impl Lint for Interactions {
    fn meta(&self) -> &Meta {
        &policy::META
    }

    fn scan_tree(&self,cx:&Cx,out:&mut Sink){let files=cx.files();let facts:Vec<Facts>=crate::incr::sharded_facts("interactions-facts",&files,|f|{let mut sink=Sink::new();let mut x=Facts::default();policy::declarations(f,|ty,line|{let ok=sink.allowed(f,line,"interactions");x.decls.push((ty.to_string(),line as u32,ok));});x.uses=sink.allow_used;x});let mut rows=Vec::new();for(f,x)in files.iter().zip(facts){for u in x.uses{out.replay_allow(u)}for(ty,line,ok)in x.decls{rows.push((ty,f.rel.clone(),line as usize,ok))}}policy::assemble(rows.iter().map(|(ty,rel,line,ok)|(ty.as_str(),rel.as_str(),*line,*ok)),out)}

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/interactions_lint.py"],
            old_raw: &[&["tools/ci/interactions_lint.py"]],
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
    reg.add(Interactions);
}
