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
fn input(source: &str, certified: bool) -> (PathBuf, PolicyInputs) { input_with_host(source, certified, None) }
fn input_with_host(source: &str, certified: bool, host: Option<Arc<dyn dm_tree::frontend::BodySyntaxQueries>>) -> (PathBuf, PolicyInputs) {
    let root = std::env::current_dir()
        .unwrap()
        .join("player-link-native-fixture");
    let source = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let seed = reference_hierarchy::seed();
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
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
#[test]
fn player_link_judges_mobs_and_preserves_local_shadow_and_named_argument_boundaries() {
    let source="/datum/holder\n    var/mob/passenger\n    proc/use(mob/P, datum/U, list/mob/L)\n        P.key = 1\n        passenger.ckey = 2\n        usr.key = 3\n        U.key = 4\n        L[1].ckey = 5\n        use(key = 6)\n        use(P.key = 7)\n        P.key += 8\n        (P.key) = 9\n/mob/proc/direct()\n    key = 10\n    src.ckey = 11\n/mob/proc/shadow()\n    key = 12\n    var/key\n";
    let (root, inputs) = input(source, true);
    let got = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        got.iter().map(|f| f.line).collect::<Vec<_>>(),
        [4, 5, 6, 8, 14, 15]
    );
    assert!(got.iter().all(|f| f.rel == "code/probe.dm"));
    assert!(
        findings(&inputs, &root, |f| f == "code/probe.dm", || Ok(()))
            .unwrap()
            .is_empty()
    );
}
#[test]
fn player_link_preserves_declared_returns_lists_and_reference_first_ternary_policy() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/no_hint() as /mob\n    return null\n/datum/holder/proc/no_hint()\n    return null\n/datum/holder/proc/method() as /mob\n    return null\n/datum/holder/proc/check(datum/holder/H, mob/P, obj/O, turf/T)\n    mob_result().key = 1\n    H.method().key = 2\n    H.mob_result().key = 3\n    no_hint().key = 4\n    (P ? O : P).key = 5\n    (P ? T : P).key = 6\n    (new /mob()).key = 7\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter().map(|f| f.line).collect::<Vec<_>>(),
        [10, 11, 12, 13, 15, 16]
    );
}
#[test]
fn player_link_deduplicates_statement_lines_and_counts_control_header_roots_only() {
    let source="/mob/proc/test(mob/P)\n    key = 1; ckey = 2\n    if(P.key = 3)\n        P.ckey = 4\n    if((P.key = 5))\n        return\n    for(P.key = 6; P.ckey = 7; P.key = 8)\n        P.key = 9\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter().map(|f| f.line).collect::<Vec<_>>(),
        [2, 3, 4, 7, 8]
    );
}
#[test]
fn player_link_does_not_turn_unproved_hierarchy_or_cancellation_into_clean_results() {
    let (root, inputs) = input("/mob/proc/test()\n    key = 1\n", false);
    assert!(findings(&inputs, &root, |_| false, || Ok(())).is_err());
    let (root, inputs) = input("/mob/proc/test()\n    key = 1\n", true);
    assert_eq!(
        findings(&inputs, &root, |_| false, || Err("cancelled".into()))
            .err()
            .unwrap()
            .0,
        "cancelled"
    );
}

#[test]
fn member_return_fallback_needs_existing_type_and_absent_method_not_missing_hint() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/no_hint() as /mob\n    return null\n/datum/holder/proc/no_hint()\n    return null\n/datum/holder/proc/check(datum/holder/H, unknown)\n    H.mob_result().key = 1\n    H.no_hint().key = 2\n    unknown.mob_result().key = 3\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [8, 10]);
}

#[test]
fn an_undeclared_receiver_type_cannot_borrow_a_global_return_annotation() {
    let source="/proc/mob_result() as /mob\n    return null\n/proc/check(datum/no_such_holder/H)\n    H.mob_result().key = 1\n";
    let (root, inputs) = input(source, true);
    assert!(findings(&inputs, &root, |_| false, || Ok(()))
        .unwrap()
        .is_empty());
}

#[test]
fn untyped_locals_use_original_root_proc_lookup_but_not_root_field_lookup() {
    let source = "/proc/mob_result() as /mob\n    return null\n/proc/check(unknown)\n    var/local\n    unknown.mob_result().key = 1\n    local.mob_result().key = 2\n    unknown.key = 3\n    local.key = 4\n";
    let (root, inputs) = input(source, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [5, 6]);
}

#[derive(Debug)]
struct ProjectedBodyHost(Arc<dm_syntax::SettingChargeCounter>);
impl dm_tree::frontend::BodySyntaxQueries for ProjectedBodyHost {
    fn syntax(&self, input: &Arc<dm_tree::frontend::BodySyntaxInput>) -> Result<Arc<dm_tree::frontend::BodySyntax>, dm_tree::frontend::Diagnostic> {
        let checkpoint = || Ok(());
        let a = dm_syntax::SettingAdmission::new(&self.0, 16 * 1024 * 1024, &checkpoint);
        match input.parse_with_setting_admission(&a) {
            Ok(value) => Ok(Arc::new(value)),
            Err(dm_tree::frontend::BodySyntaxFailure::Syntax(error)) => Err(error),
            Err(dm_tree::frontend::BodySyntaxFailure::Operational(error)) => panic!("unexpected actual fixture operation: {error}"),
        }
    }
}
#[test]
fn player_link_projected_setting_keeps_owned_root_assignment_policy_and_current_lines() {
    for prefix in ["", "// shifted original source é\n\n"] {
        let source = format!("{prefix}/mob/proc/check(mob/P)\n    set name = P.key = 1\n    set desc = call(P.ckey = 2)\n    set category = (P.key = 3)\n    P.ckey = 4\n");
        let (root, old) = input(&source, true);
        let expected = findings(&old, &root, |_| false, || Ok(())).unwrap();
        assert_eq!(expected.iter().map(|r|r.line).collect::<Vec<_>>(), [2 + prefix.bytes().filter(|b|*b==b'\n').count(), 5 + prefix.bytes().filter(|b|*b==b'\n').count()]);
        let host = Arc::new(ProjectedBodyHost(Arc::new(std::sync::atomic::AtomicUsize::new(0))));
        let (root, native) = input_with_host(&source, true, Some(host));
        let body = native.archive().parse(0).unwrap();
        assert!(matches!(&body.statement_body().parsed().statements[0].kind, dm_syntax::StatementKind::ProjectedSet { .. }));
        assert_eq!(findings(&native, &root, |_| false, || Ok(())).unwrap(), expected);
    }
}

struct WorkspacePlayerControl{polls:usize,fail_at:Option<usize>,denied:bool,wrong_ordinal:bool,peak:usize}
impl crate::policy_body_demand::WorkspaceWork for WorkspacePlayerControl{
 type Error=crate::policy_body_demand::PolicyFailure;const CHECKED:bool=true;
 fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.fail_at==Some(self.polls){return Err(crate::policy_body_demand::PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450)))}Ok(())}
 fn retain(&mut self,_:usize)->Result<(),Self::Error>{if self.denied{Err(self.allocation_failed())}else{Ok(())}}
 fn temporary(&mut self,n:usize)->Result<(),Self::Error>{if self.denied{return Err(self.allocation_failed())}self.peak=self.peak.max(n);Ok(())}
 fn overflow(&mut self)->Self::Error{crate::policy_body_demand::PolicyFailure::Operational(std::io::ErrorKind::OutOfMemory.into())}
 fn allocation_failed(&mut self)->Self::Error{self.overflow()}
 fn body<'a>(&mut self,archive:&'a dm_tree::frontend::BodyArchive,ordinal:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Self::Error>{let ordinal=if self.wrong_ordinal{(ordinal+1)%archive.len()}else{ordinal};<crate::policy_body_demand::Checked as crate::policy_body_demand::Demand>::parse(archive,ordinal)}
}
fn player_control()->WorkspacePlayerControl{WorkspacePlayerControl{polls:0,fail_at:None,denied:false,wrong_ordinal:false,peak:0}}
#[test]fn full_workspace_player_link_preserves_same_receiver_and_projected_root_policy(){let source="/mob/proc/check(mob/P)\n    set name = P.key = 1\n    set desc = call(P.ckey = 2)\n    P.ckey = 3\n    if(P.key = 4)\n        P.key = 5\n/mob/proc/shadow()\n    key = 6\n    var/key\n";let(root,owned)=input(source,true);let expected=findings(&owned,&root,|_|false,||Ok(())).unwrap();let host=Arc::new(ProjectedBodyHost(Arc::new(std::sync::atomic::AtomicUsize::new(0))));let(root,inputs)=input_with_host(source,true,Some(host));let first=inputs.archive().parse_checked(0).unwrap();assert!(matches!(&first.statement_body().parsed().statements[0].kind,dm_syntax::StatementKind::ProjectedSet{..}));let mut control=player_control();let actual=findings_workspace_using(&inputs,&root,|_|false,&mut control).unwrap();assert_eq!(actual,expected);assert!(!actual.is_empty());assert!(control.peak>0);assert!(control.polls>inputs.archive().len());}
#[test]fn full_workspace_player_link_preserves_mid_body_actual_io_and_rejects_other_body_ordinals(){let text=format!("/mob/proc/check()\n{}", "    return 1\n".repeat(4096));let(root,inputs)=input(&text,true);let mut control=player_control();control.fail_at=Some(100);let error=findings_workspace_using(&inputs,&root,|_|false,&mut control).unwrap_err();assert!(matches!(error,crate::policy_body_demand::PolicyFailure::Operational(ref actual)if actual.raw_os_error()==Some(1450)));assert_eq!(control.polls,100);let mut denied=player_control();denied.denied=true;assert!(matches!(findings_workspace_using(&inputs,&root,|_|false,&mut denied),Err(crate::policy_body_demand::PolicyFailure::Operational(ref actual))if actual.kind()==std::io::ErrorKind::OutOfMemory));let(root,two)=input("/mob/proc/first()\n    key = 1\n/mob/proc/second()\n    key = 2\n",true);let mut foreign=player_control();foreign.wrong_ordinal=true;assert!(matches!(findings_workspace_using(&two,&root,|_|false,&mut foreign),Err(crate::policy_body_demand::PolicyFailure::Unsupported(ref actual))if actual.0.contains("foreign original body")));let mut clean=player_control();assert_eq!(findings_workspace_using(&two,&root,|_|false,&mut clean).unwrap().len(),2);}

#[test]fn full_workspace_player_link_receiver_chain_propagates_actual_io_denial_and_recovers(){
 let chain=format!("N.{}passenger","next.".repeat(32));let source=format!("/datum/player_chain\n    var/datum/player_chain/next\n    var/mob/passenger\n/datum/player_chain/proc/check(datum/player_chain/N)\n    {chain}.key = 1\n");let(root,inputs)=input(&source,true);let archive=inputs.archive();let body=archive.parse_checked(0).unwrap();let scope=untyped::archived_scope(&body,archive.tree(),&[]).unwrap().with_archive(archive).unwrap();let dm_syntax::StatementKind::Assign{target:lhs,op,..}=&body.statement_body().parsed().statements[0].kind else{panic!("actual primary assignment statement expected")};assert_eq!(op,"=","the real fixture is a simple assignment, not a compound write");let ExprKind::Member{object,..}=&lhs.kind else{panic!("actual key receiver expected")};let legacy=scope.player_link_receiver_type(object).unwrap();assert_eq!(legacy.as_deref(),Some("/mob"));
 for limit in [false,true]{let mut count=0usize;let mut poll=||{count+=1;if count==8{Err(crate::policy_body_demand::PolicyFailure::Operational(if limit{std::io::ErrorKind::OutOfMemory.into()}else{std::io::Error::from_raw_os_error(1450)}))}else{Ok(())}};let error=scope.player_link_receiver_type_using(object,&mut poll).unwrap_err();match error{crate::policy_body_demand::PolicyFailure::Operational(actual)=>if limit{assert_eq!(actual.kind(),std::io::ErrorKind::OutOfMemory)}else{assert_eq!(actual.raw_os_error(),Some(1450))},other=>panic!("actual operation must survive receiver recursion: {other}")}assert_eq!(count,8);}
 let mut calls=0usize;let actual=scope.player_link_receiver_type_using(object,&mut||{calls+=1;Ok::<(),crate::policy_body_demand::PolicyFailure>(())}).unwrap();assert_eq!(actual,legacy);assert!(calls>32,"each receiver and field lookup has a control point");let mut clean=player_control();assert_eq!(findings_workspace_using(&inputs,&root,|_|false,&mut clean).unwrap().len(),1);
}
