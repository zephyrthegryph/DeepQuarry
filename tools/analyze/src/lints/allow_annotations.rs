//! Port of `tools/ci/allow_annotations.py`: every `// ALLOW(lint): reason` must be well formed,
//! name a known lint, carry a real reason (at least 20 characters and 3 words; no allowlist talk,
//! "see above", "not edited here", plan-phase labels or plan item codes), and, over a full run,
//! must actually keep a site (an annotation no lint used is stale).
//!
//! The per-annotation checks are this lint. The unused-annotation check needs the usage every
//! other lint recorded in the same run, so it is `unused()` below, called by `analyze check` after
//! all lints ran (a full run only; `check_ratchets.sh` still has the Python do it while legacy
//! lints remain, via DQ_ALLOW_USAGE).

use std::collections::BTreeSet;

use crate::lint::{AllowUse, Cx, Lint, Meta, Registry, Sink};
use crate::parity::{ParseKind, Parity};
use crate::tree::{Tree, CODE_MAPS_DM};

pub use crate::allow_annotation_policy::{reason_problem,UNOBSERVED};
static KNOWN:std::sync::OnceLock<BTreeSet<String>>=std::sync::OnceLock::new();
pub fn set_known(names:BTreeSet<String>){let _=KNOWN.set(names);}
pub fn known()->&'static BTreeSet<String>{KNOWN.get_or_init(BTreeSet::new)}



struct AllowAnnotations;

impl Lint for AllowAnnotations {
    fn meta(&self) -> &Meta {
        crate::allow_annotation_policy::metadata()
    }

    fn scan_file(&self,_cx:&Cx,file:&crate::tree::SourceFile,out:&mut Sink){
        if !file.text().contains("ALLOW("){return}
        for(number,line)in file.raw().numbered(){
            let result=crate::allow_annotation_policy::validate_line(known(),number,line,&mut crate::key_policy_control::Compatibility,|rule,line,message|{out.site_msg(rule,line,message);Ok(())});
            match result{Ok(())=>{},Err(never)=>match never{}}
        }
    }

    fn parity(&self) -> Option<Parity> {
        Some(Parity {
            old: &["tools/ci/allow_annotations.py"],
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
    reg.add(AllowAnnotations);
}

/// The unused-ALLOW check over a full run: every annotation naming a known lint whose lint ran and
/// recorded usage, but not for this annotation, is stale. A name with annotations but no recorded
/// usage at all is reported once ("no lint run used any"). Returns the problem lines.
pub fn unused(tree:&Tree,used:&[AllowUse],extra_used:&[(String,String,u32)],digest:&dyn Fn(&str)->String)->Vec<String>{
 let files=tree.select(&CODE_MAPS_DM);
 let annotations:Vec<Vec<(u32,Vec<String>)>>=crate::incr::facts("allow-annotations",&files,|file|{
  if !file.text().contains("ALLOW("){return Vec::new()}
  match crate::allow_annotation_policy::annotations(file.raw().numbered(),&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
 });
 let rows:Vec<_>=files.iter().zip(&annotations).map(|(file,annotations)|crate::allow_annotation_policy::AnnotationFile{relative:&file.rel,has_marker:file.text().contains("ALLOW("),annotations}).collect();
 match crate::allow_annotation_policy::unused(known(),used,extra_used,&rows,digest,&mut crate::key_policy_control::Compatibility){Ok(value)=>value,Err(never)=>match never{}}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reason_quality_rules() {
        assert!(reason_problem("short").unwrap().contains("too short"));
        assert!(reason_problem("the allowlist keeps this one around").unwrap().contains("no allowlist"));
        assert!(reason_problem("see above for the reason here ok").unwrap().contains("say the reason here"));
        assert!(reason_problem("wave F3 will convert this call site").unwrap().contains("plan-phase"));
        assert!(reason_problem("kept until M1a lands in the tree ok").unwrap().contains("plan item code"));
        assert!(reason_problem("world.Export() is a blocking external call").is_none());
    }

    #[test]
    fn repr_matches_python() {
        assert_eq!(crate::allow_annotation_policy::py_repr("a b"), "'a b'");
        assert_eq!(crate::allow_annotation_policy::py_repr("it's"), "\"it's\"");
    }
}
