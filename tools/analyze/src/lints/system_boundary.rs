//! Port of `tools/ci/system_boundary_lint.py` (doc/rewrite/kernel.md sec 2.5).
//!
//! A subsystem, a world service or a /datum/system is a module; its folder is the boundary.
//! Every site fails (a hard ban, no baseline).
//!
//!   B1  no `SSx.<var>` / `GLOB.<x>_service.<var>` / `system(/datum/system/X).<var>` outside the owner
//!   B2  `system(/datum/system/X).proc()` outside X's folder must name a proc in X's api.dm
//!   B3  no proc definitions of a subsystem / service / system outside the owner's folder
//!   B4  X calls Y's API only if Y is in X's `uses`
//!   B5  no cycle in `needs`, and every `needs` entry names a declared type
//!   B6  OM_EMIT* event types under X's folder are in X's `emits`
//!   B7  a /datum/system folder has an api.dm iff another folder calls the system
//!
//! Shape notes (kept from the Python): a site's `key` is the baseline name (spaces as `%20`); its
//! `msg` is the whole text the old `--report` printed. A B5 or B7 site has no file or line, so the
//! text rides in `rel` (line 0), which is also how the parity parser compares it.
//! Python iterates `glob.glob` order and this engine path-sorted order; they only differ for a
//! duplicate definition, where "first one wins" could pick a different file.



use crate::dm::pylines::recorded_into;
use crate::incr;
use crate::lint::{Cx, Lint, Meta, Registry, Sink};
use crate::parity::{ParseKind, Parity};

use crate::system_boundary_report::META;

struct SystemBoundary;

impl SystemBoundary {
 fn check(&self,cx:&Cx,out:&mut Sink){
  let files=cx.files();let facts=incr::facts("system_boundary-facts",&files,crate::system_boundary_policy::facts_of);
  let borrowed:Vec<_>=files.iter().zip(&facts).map(|(file,facts)|(file.rel.as_str(),facts)).collect();
  let prepared=crate::system_boundary_policy::prepare(&borrowed);
  let results=recorded_into(out,||incr::keyed("system_boundary-judge",prepared.context_key(),&files,|file|crate::system_boundary_policy::judge_file(file,&prepared)));
  let borrowed_results:Vec<_>=files.iter().zip(results).map(|(file,result)|(file.rel.clone(),result)).collect();
  crate::system_boundary_policy::finish(&prepared,&borrowed_results,out);
 }
}

impl Lint for SystemBoundary {
    fn meta(&self) -> &Meta {
        &META
    }

    fn scan_tree(&self, cx: &Cx, out: &mut Sink) {
        self.check(cx, out);
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/system_boundary_lint.py"],
            old_raw: &[&["tools/ci/system_boundary_lint.py", "--report"]],
            blank: &[],
            parse: ParseKind::RulePrefixed,
            update: None,
            seed: None,
            files: &[],
            selftest: None,
        })
    }
}

pub fn register(reg: &mut Registry) {
    reg.add(SystemBoundary);
}
