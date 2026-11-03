use super::*;
use crate::policy_inputs::{HostCapture, PolicyRole};
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use std::path::Path;
use std::{path::PathBuf, sync::Arc};
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
struct Source(AcquiredSource);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("acquisition required".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn input(source: &str, certified: bool) -> (PathBuf, PolicyInputs) {
    input_at(source, certified, "code/probe.dm")
}
fn input_at(source: &str, certified: bool, relative: &str) -> (PathBuf, PolicyInputs) { input_at_host(source, certified, relative, None) }
fn input_at_host(source: &str, certified: bool, relative: &str, host: Option<Arc<dyn dm_tree::frontend::BodySyntaxQueries>>) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("weak-raw-native-fixture");
    let source = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join(relative),
        &source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: certified.then_some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        true,
    )
    .unwrap();
    let frontend = match host { Some(host) => frontend.with_body_queries(host), None => frontend };
    let extra = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, f.text.clone())
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, extra).unwrap())
}

fn weak() -> HashMap<String, Vec<String>> {
    HashMap::from([("target".into(), vec!["/datum/owner".into()])])
}
#[test]
fn real_receiver_types_reads_writes_list_elements_and_interpolation_are_observed() {
    let source="/datum/owner\n    var/datum/target\n    proc/read(datum/owner/H, list/datum/owner/L)\n        target\n        src.target\n        H.target\n        L[1].target\n        target = H\n        var/text = \"x[H.target]\"\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter().map(|r| r.line).collect::<Vec<_>>(),
        [4, 5, 6, 7, 8, 9]
    );
    assert!(rows
        .iter()
        .all(|r| r.var == "target" && r.holder == "/datum/owner"));
}
#[test]
fn nameof_excludes_actual_argument_nodes_but_not_a_later_raw_expression() {
    let source="/datum/owner\n    var/datum/target\n    proc/read(datum/owner/H)\n        nameof(target)\n        nameof(H.target)\n        nameof(list(H.target, H.target.child))\n        target()\n        H.target()\n        H.target\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [9]);
}
#[test]
fn accessor_callee_is_not_raw_but_its_weak_receiver_remains_a_read() {
    let source =
        "/datum/owner\n    var/datum/owner/target\n    proc/read()\n        target.ping()\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [4]);
}
#[test]
fn untyped_unrelated_receiver_and_whole_proc_local_shadow_stay_silent() {
    let source="/datum/other\n    var/datum/target\n/datum/owner\n    var/datum/target\n    proc/read(datum/other/O, unknown)\n        target\n        O.target\n        unknown.target\n        var/target\n";
    let (root, inputs) = input(source, true);
    assert!(findings(&inputs, &root, &weak(), |_| false, || Ok(()))
        .unwrap()
        .is_empty());
}
#[test]
fn subtype_compatibility_and_source_return_annotation_use_existing_walker() {
    let source="/datum/owner\n    var/datum/target\n/datum/owner/child\n/proc/make_owner() as /datum/owner\n    return null\n/proc/read(datum/owner/child/C)\n    C.target\n    make_owner().target\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [7, 8]);
    assert_eq!(rows[0].holder, "/datum/owner/child");
}
#[test]
fn cancellation_and_missing_builtin_proof_refuse_instead_of_minting_clean_rows() {
    let source = "/datum/owner\n    var/datum/target\n    proc/read()\n        target\n";
    let (root, inputs) = input(source, true);
    assert!(findings(
        &inputs,
        &root,
        &weak(),
        |_| false,
        || Err("cancelled".into())
    )
    .is_err());
    assert!(findings(&inputs, &root, &weak(), |_| true, || Ok(()))
        .unwrap()
        .is_empty());
    let (root, inputs) = input(source, false);
    assert!(findings(&inputs, &root, &weak(), |_| false, || Ok(())).is_err());
}

#[test]
fn original_macro_receipt_maps_the_hit_to_the_call_site_without_relexing() {
    let source="#define READ(x) x.target\n/datum/owner\n    var/datum/target\n/proc/read(datum/owner/H)\n    READ(H)\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [5]);
}

#[test]
fn grouped_dynamic_callee_does_not_mint_a_nameof_or_accessor_exclusion() {
    let source="/datum/owner\n    var/datum/target\n    proc/read(datum/owner/H)\n        (nameof)(H.target)\n        (H.target)()\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [4, 5]);
}

#[test]
fn typed_scan_preserves_old_proc_scan_outside_raw_code_selection() {
    let source = "/datum/owner\n    var/datum/target\n    proc/read()\n        target\n";
    let (root, inputs) = input_at(source, true, "maps/probe.dm");
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rel, "maps/probe.dm");
    assert_eq!(rows[0].line, 4);
}

#[test]
fn stored_reference_receiver_shares_proven_global_method_fallback_without_stealing_hint() {
    let source="/proc/owner_result() as /datum/owner\n    return null\n/proc/no_hint() as /datum/owner\n    return null\n/datum/owner\n    var/datum/target\n    proc/no_hint()\n        return null\n    proc/read(datum/owner/H, unknown)\n        H.owner_result().target\n        H.no_hint().target\n        unknown.owner_result().target\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, &weak(), |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [10, 12]);
}

#[test]
fn projected_setting_weak_reads_preserve_nameof_callee_skips_and_current_source_lines() {
    for prefix in ["", "// earlier source \u{e9}\n\n"] {
        let source=format!("{prefix}/datum/owner\n    var/datum/target\n    proc/p(datum/owner/H)\n        set name = H.target\n        set desc = nameof(H.target)\n        target\n");
        let (root,old)=input(&source,true); let expected=findings(&old,&root,&weak(),|_|false,||Ok(())).unwrap();
        assert_eq!(expected.len(),2);
        let (root,native)=input_at_host(&source,true,"code/probe.dm",Some(crate::untyped_order::projected_body_host_for_test()));
        assert!(matches!(&native.archive().parse(0).unwrap().statement_body().parsed().statements[0].kind,dm_syntax::StatementKind::ProjectedSet{..}));
        assert_eq!(findings(&native,&root,&weak(),|_|false,||Ok(())).unwrap(),expected);
    }
}

struct WeakControl{polls:usize,fail_at:Option<usize>,denied:bool,wrong:bool,peak:usize}
impl crate::policy_body_demand::WorkspaceWork for WeakControl{type Error=crate::policy_body_demand::PolicyFailure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.fail_at==Some(self.polls){Err(crate::policy_body_demand::PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}}fn retain(&mut self,_:usize)->Result<(),Self::Error>{if self.denied{Err(self.overflow())}else{Ok(())}}fn temporary(&mut self,n:usize)->Result<(),Self::Error>{if self.denied{return Err(self.overflow())}self.peak=self.peak.max(n);Ok(())}fn overflow(&mut self)->Self::Error{crate::policy_body_demand::PolicyFailure::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Self::Error{self.overflow()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Self::Error>{<crate::policy_body_demand::Checked as crate::policy_body_demand::Demand>::parse(a,if self.wrong{(n+1)%a.len()}else{n})}}
fn weak_control()->WeakControl{WeakControl{polls:0,fail_at:None,denied:false,wrong:false,peak:0}}

#[test]fn full_workspace_weak_preserves_original_nameof_markers_and_projected_settings(){let source="/datum/owner\n    var/datum/target\n    proc/read(datum/owner/H)\n        set name = H.target\n        set desc = nameof(H.target)\n        target()\n        H.target.child()\n        H.target\n";let(root,owned)=input(source,true);let expected=findings(&owned,&root,&weak(),|_|false,||Ok(())).unwrap();let host=crate::untyped_order::projected_body_host_for_test();let(root,actual)=input_at_host(source,true,"code/probe.dm",Some(host));let mut work=weak_control();assert_eq!(findings_workspace_using(&actual,&root,&weak(),|_|false,&mut work).unwrap(),expected);assert!(!expected.is_empty());assert!(work.peak>0);}
#[test]fn full_workspace_weak_preserves_marker_lookup_actual_io_denial_foreign_body_and_recovery(){let nested=format!("nameof(list({}))",vec!["H.target";128].join(","));let source=format!("/datum/owner\n    var/datum/target\n    proc/first(datum/owner/H)\n        {nested}\n        H.target\n    proc/second(datum/owner/H)\n        H.target\n");let(root,inputs)=input(&source,true);let mut good=weak_control();let expected=findings_workspace_using(&inputs,&root,&weak(),|_|false,&mut good).unwrap();for offset in [good.polls/3,good.polls/2]{let mut failed=weak_control();failed.fail_at=Some(offset);assert!(matches!(findings_workspace_using(&inputs,&root,&weak(),|_|false,&mut failed),Err(crate::policy_body_demand::PolicyFailure::Operational(ref e))if e.raw_os_error()==Some(1450)));assert_eq!(failed.polls,offset);}let mut denied=weak_control();denied.denied=true;assert!(matches!(findings_workspace_using(&inputs,&root,&weak(),|_|false,&mut denied),Err(crate::policy_body_demand::PolicyFailure::Operational(ref e))if e.kind()==std::io::ErrorKind::OutOfMemory));let mut wrong=weak_control();wrong.wrong=true;assert!(matches!(findings_workspace_using(&inputs,&root,&weak(),|_|false,&mut wrong),Err(crate::policy_body_demand::PolicyFailure::Unsupported(ref e))if e.0.contains("foreign original body")));assert_eq!(findings_workspace_using(&inputs,&root,&weak(),|_|false,&mut weak_control()).unwrap(),expected);}
#[test]fn full_workspace_weak_final_order_is_complete_message_not_var_prefix(){let source="/datum/owner\n    var/datum/target\n    var/datum/target_\n    proc/read(datum/owner/H)\n        H.target; H.target_\n";let(root,inputs)=input(source,true);let mut index=weak();index.insert("target_".into(),vec!["/datum/owner".into()]);let rows=findings_workspace_using(&inputs,&root,&index,|_|false,&mut weak_control()).unwrap();assert_eq!(rows.iter().map(|r|r.var.as_str()).collect::<Vec<_>>(),["target_","target"]);}
