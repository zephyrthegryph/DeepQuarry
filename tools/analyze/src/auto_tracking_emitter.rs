//! Exact AutoTracked output template over completed unique decision rows.
use crate::{auto_tracking_policy::{Auto,AutoSet},sparse_slots_policy::Output};
use std::collections::BTreeSet;
pub(crate) fn documents(out:&mut Output){
        out.doc("Read-driven tracking: the vars reactive code reads that no declaration makes tracked, written as the TRACKED() their author would have");
        out.doc("declared (tools/analyze/src/gens/auto_tracked.rs, doc/rewrite/final_api.html section 7). Write them only through set_<var>();");
        out.doc("the `tracked` lint holds every write to that and `analyze fix` rewrites it.");
}
pub(crate) fn emit_rows(set:&AutoSet,tests:&BTreeSet<String>,out:&mut Output){
        let (test, content): (Vec<&Auto>, Vec<&Auto>) = set.tracked.iter().partition(|a| tests.contains(&a.ty));
        for a in &content {
            out.line(format!("TRACKED({}, {})", a.ty, a.var));
        }
        if !test.is_empty() {
            out.line(crate::generator_test_scope::TEST_GUARD);
            for a in &test {
                out.line(format!("TRACKED({}, {})", a.ty, a.var));
            }
            out.line("#endif");
        }
}
#[cfg(feature="native-policy")]
pub(crate) fn generate_admitted(set:&AutoSet,tests:&BTreeSet<String>,budget:&std::sync::Arc<crate::captured_generator_budget::Budget>,checkpoint:&dyn Fn()->std::io::Result<()>)->std::io::Result<Output>{
 checkpoint()?;let overflow=||{budget.deny();std::io::Error::new(std::io::ErrorKind::OutOfMemory,"auto tracking renderer capacity overflow")};
 let width=set.tracked.iter().try_fold(0usize,|n,row|n.checked_add(row.ty.len())?.checked_add(row.var.len())).ok_or_else(&overflow)?;
 let bytes=set.tracked.len().checked_mul(4*std::mem::size_of::<&Auto>()+128).and_then(|n|width.checked_mul(4).and_then(|w|n.checked_add(w))).and_then(|n|n.checked_add(4096)).ok_or_else(&overflow)?;
 budget.charge(bytes).map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;
 let mut out=Output::captured(budget.clone());documents(&mut out);emit_rows(set,tests,&mut out);checkpoint()?;budget.require().map_err(|message|std::io::Error::new(std::io::ErrorKind::OutOfMemory,message))?;Ok(out)
}

#[cfg(test)]mod tests{
 use super::*;mod original{include!("auto_tracking_emitter_reference.rs");}
 #[test]fn auto_template_preserves_entire_original_output_and_test_partition_order(){
  let set=AutoSet{tracked:vec![Auto{ty:"/datum/content".into(),var:"charge".into(),list:false},Auto{ty:"/datum/test_only".into(),var:"items".into(),list:true}],blocked:Vec::new()};let tests=BTreeSet::from(["/datum/test_only".into()]);let mut old=Output::default();original::generate(&set,&tests,&mut old);let mut current=Output::default();documents(&mut current);emit_rows(&set,&tests,&mut current);assert_eq!(current,old);assert!(current.body.contains("TRACKED(/datum/content, charge)"));assert!(current.body.contains(crate::generator_test_scope::TEST_GUARD));
 }
 #[test]fn exact_frozen_template_projection(){let frozen=include_str!("auto_tracking_emitter_frozen_original.rs");let reference=include_str!("auto_tracking_emitter_reference.rs");let start=frozen.find("        out.doc(\"Read-driven").unwrap();let end=frozen[start..].find("        let inf =").unwrap()+start;assert!(reference.contains(&frozen[start..end]));let start=frozen.find("        let (test, content)").unwrap();let end=frozen[start..].find("\n    }\n}").unwrap()+start;assert!(reference.contains(&frozen[start..end].replace("crate::sem::gen::TEST_GUARD","crate::generator_test_scope::TEST_GUARD")));}
 #[cfg(feature="native-policy")]#[test]fn auto_template_actual_quota_and_os_error_leave_retry_available(){let set=AutoSet{tracked:vec![Auto{ty:"/datum/unit".into(),var:"value".into(),list:false}],blocked:Vec::new()};let tests=BTreeSet::new();let fixed=std::mem::size_of::<crate::captured_generator_budget::Budget>()+2*std::mem::size_of::<usize>();let tiny=crate::captured_generator_budget::Budget::new(fixed).unwrap();assert_eq!(generate_admitted(&set,&tests,&tiny,&||Ok(())).unwrap_err().kind(),std::io::ErrorKind::OutOfMemory);assert!(tiny.denied());let healthy=crate::captured_generator_budget::Budget::new(1024*1024).unwrap();assert_eq!(generate_admitted(&set,&tests,&healthy,&||Err(std::io::Error::from_raw_os_error(1450))).unwrap_err().raw_os_error(),Some(1450));let mut old=Output::default();original::generate(&set,&tests,&mut old);assert_eq!(generate_admitted(&set,&tests,&healthy,&||Ok(())).unwrap(),old);}

}
