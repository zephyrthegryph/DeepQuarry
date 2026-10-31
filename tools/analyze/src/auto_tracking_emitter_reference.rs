use crate::{auto_tracking_policy::{Auto,AutoSet},sparse_slots_policy::Output};use std::collections::BTreeSet;
pub fn generate(set:&AutoSet,tests:&BTreeSet<String>,out:&mut Output){
        out.doc("Read-driven tracking: the vars reactive code reads that no declaration makes tracked, written as the TRACKED() their author would have");
        out.doc("declared (tools/analyze/src/gens/auto_tracked.rs, doc/rewrite/final_api.html section 7). Write them only through set_<var>();");
        out.doc("the `tracked` lint holds every write to that and `analyze fix` rewrites it.");
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
