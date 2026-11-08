use super::*;
#[path = "../examples/support/reference_hierarchy.rs"]
mod reference_hierarchy;
use std::path::Path;
use std::sync::Arc;
struct Source(dm_preprocess::AcquiredSource);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("test requires actual original bytes".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<dm_preprocess::AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(
        &self,
        _: &Path,
        text: &dm_preprocess::SourceText,
    ) -> Option<dm_preprocess::AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn input(source: &str, certified: bool) -> (std::path::PathBuf, PolicyInputs) {
    input_with_primary(source, certified, false)
}
fn input_with_primary(source: &str, certified: bool, primary: bool) -> (std::path::PathBuf, PolicyInputs) { input_with_primary_host(source, certified, primary, None) }
fn input_with_primary_host(source: &str, certified: bool, primary: bool, host: Option<Arc<dyn dm_tree::frontend::BodySyntaxQueries>>) -> (std::path::PathBuf, PolicyInputs) {
    use crate::policy_inputs::{HostCapture, PolicyRole};
    let root = std::env::current_dir()
        .unwrap()
        .join("member-native-fixture");
    let seed = reference_hierarchy::seed();
    let provider = Source(dm_preprocess::AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    let frontend = dm_tree::frontend::build_with_executor_and_semantic_state_for_policy(
        &root.join("code/probe.dm"),
        &provider,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: certified.then_some(&seed),
            observer: None,
        },
        None,
        &executor,
        None,
        primary,
    )
    .unwrap();
    let frontend = match host { Some(host) => frontend.with_body_queries(host), None => frontend };
    let raw = frontend
        .files
        .iter()
        .filter(|f| f.captured)
        .map(|f| {
            HostCapture::analyze_raw(Arc::clone(&f.path), PolicyRole::DmSource, {
                let raw = f.text.replace("\r\n", "\n").replace('\r', "\n");
                if raw == f.text.as_str() {
                    f.text.clone()
                } else {
                    raw.into()
                }
            })
        })
        .collect::<Vec<_>>();
    (root, PolicyInputs::capture(&frontend, raw).unwrap())
}
#[test]
fn declared_receivers_are_typed_but_returns_and_indexes_remain_untyped() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/datum/typed\n    var/danger\n/proc/make()\n    return new /datum/typed\n/proc/check(holder, datum/typed/typed, list/items)\n    holder.danger\n    typed.danger\n    make().danger\n    items[1].danger\n    (new /datum/typed).danger\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [8, 10, 11]);
}
#[test]
fn unknown_builtin_ancestry_refuses_instead_of_certifying_empty_static_universe() {
    let (root, input) = input("/proc/check(holder)\n    holder.danger\n", false);
    assert!(findings(&input, &root, |_| false, || Ok(())).is_err());
}
#[test]
fn else_if_header_uses_the_legacy_first_if_statement_origin() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    if(holder.danger)\n        return\n    else if(holder.danger)\n        return\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [4]);
}
#[test]
fn cancellation_drops_the_complete_policy_result() {
    let (root, input) = input(
        "/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    holder.danger\n",
        true,
    );
    assert!(findings(&input, &root, |_| false, || Err("cancelled".into())).is_err());
}

#[test]
fn constructor_target_member_is_not_a_read_but_argument_member_is() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    new holder.danger()\n    new holder.danger(\n        holder.danger)\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|r| r.line).collect::<Vec<_>>(), [5]);
}

#[test]
fn physical_statement_origin_is_not_a_nested_member_expression_line() {
    let(root,input)=input("/datum/static_owner\r\n    var/static/danger\r\n/proc/check(holder)\r\n    for(var/i=0;\r\n        holder.danger;\r\n        i++)\r\n        return\r\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|row| row.line).collect::<Vec<_>>(), [4]);
}
#[test]
fn macro_statement_needs_producer_line_receipt() {
    let(root,input)=input("#define READ(x) x.danger\n/datum/static_owner\n    var/static/danger\n/proc/check(holder)\n    READ(holder)\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(rows.iter().map(|row| row.line).collect::<Vec<_>>(), [5]);
}

#[test]
fn scoped_values_have_no_declared_receiver_and_proc_reference_arguments_are_not_evaluated() {
    let(root,input)=input("/datum/static_owner\n    var/static/danger\n    var/static/ignored_danger\n    var/static/payload\n    proc/method()\n        return\n/proc/check(holder)\n    (/datum/static_owner::payload).danger\n    (/datum/static_owner::method(holder.ignored_danger))\n",true);
    let rows = findings(&input, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| (row.line, row.name.as_str()))
            .collect::<Vec<_>>(),
        [(8, "danger")]
    );
}

#[test]
fn static_universe_uses_pinned_dsl_not_empty_runtime_seed_and_explicit_modifiers_only() {
    let(_,inputs)=input("var/implicit_root\nvar/global/explicit_global\nvar/static/explicit_static\nvar/const/constant = 1\nvar/tmp/temporary\n/datum/holder\n    var/global/member_global\n    var/static/member_static\n    var/ordinary\n/proc/check(holder)\n    holder.explicit_global\n",true);
    let tree = inputs.archive().tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let names = static_names(tree, profile).unwrap();
    for name in [
        "world",
        "explicit_global",
        "explicit_static",
        "member_global",
        "member_static",
    ] {
        assert!(
            names.contains(name),
            "pinned checker/static declaration absent: {name}"
        );
    }
    for name in ["implicit_root", "constant", "temporary", "ordinary"] {
        assert!(
            !names.contains(name),
            "global storage is not an explicit STATIC flag: {name}"
        );
    }
    assert!(!reference_hierarchy::MEMBER_INVENTORY_COMPLETE);
    assert!(reference_hierarchy::seed().fields.is_empty());
    let catalog = dm_tree::checker_builtins::pinned_catalog().unwrap();
    assert_eq!(catalog.declarations.len(), 822);
    assert_eq!(
        catalog
            .declarations
            .iter()
            .filter(|row| row.kind == MemberKind::Var)
            .count(),
        444
    );
}
#[test]
fn authored_formal_replaces_builtin_flag_but_value_override_preserves_formal() {
    let(_,inputs)=input("var/world\nworld = null\n/datum/base\n    var/static/kept = 1\n    var/ordinary = 1\n/datum/base\n    kept = 2\n    ordinary = 2\n/datum/base/child\n    kept = 3\n/proc/check(holder)\n    holder.kept\n",true);
    let tree = inputs.archive().tree();
    let names = static_names(tree, tree.checker_builtin_profile().unwrap()).unwrap();
    assert!(
        !names.contains("world"),
        "same-owner source formal replaces pinned builtin declaration"
    );
    assert!(
        names.contains("kept"),
        "same-owner and subtype defaults do not erase formal static flags"
    );
    assert!(!names.contains("ordinary"));
}

#[test]
fn qualifier_only_fields_without_primary_view_refuse() {
    let source="/datum/static_owner\n    var/static/danger\n/datum/holder\n    var/SpacemanDMM_private/untyped\n    proc/check()\n        untyped.danger\n";
    let (root, inputs) = input(source, true);
    assert!(findings(&inputs, &root, |_| false, || Ok(())).is_err());
}
#[test]
fn original_qualified_local_receivers_preserve_independent_old_static_member_findings() {
    for (source,line) in [
        ("/datum/static_owner\n    var/static/danger\n/proc/check()\n    var/SpacemanDMM_private/untyped\n    untyped.danger\n",5),
        ("/datum/static_owner\n    var/static/danger\n/proc/check(SpacemanDMM_protected/untyped)\n    untyped.danger\n",4),
    ] {
        let(root,inputs)=input(source,true);
        let rows=findings(&inputs,&root,|_|false,||Ok(())).unwrap();
        assert_eq!(rows.len(),1,"{source}");
        assert_eq!((rows[0].line,rows[0].name.as_str()),(line,"danger"));
    }
}

#[test]
fn owned_primary_field_qualifiers_admit_untyped_and_preserve_unknown_nonempty_hints() {
    let source="/datum/static_owner\n    var/static/danger\n/datum/holder\n    var/SpacemanDMM_private/untyped\n    var/SpacemanDMM_private/datum/typed\n    var/SpacemanDMM_private/missing_type/unknown\n    proc/check()\n        untyped.danger\n        typed.danger\n        unknown.danger\n";
    let (root, ordinary) = input_with_primary(source, true, false);
    assert!(
        findings(&ordinary, &root, |_| false, || Ok(())).is_err(),
        "no primary receipt means Unknown, not stripped metadata"
    );
    let (root, inputs) = input_with_primary(source, true, true);
    let rows = findings(&inputs, &root, |_| false, || Ok(())).unwrap();
    assert_eq!(
        rows.iter()
            .map(|row| (row.line, row.name.as_str()))
            .collect::<Vec<_>>(),
        [(8, "danger")]
    );
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let formal = tree
        .source_formal_variable_member(SymbolId::of("/datum/holder"), SymbolId::of("unknown"))
        .unwrap()
        .unwrap();
    let view = archive
        .checker_variable_properties(formal, profile)
        .unwrap();
    assert_eq!(view.declared_hint(), Some("/missing_type"));
    assert!(
        tree.lookup_type(SymbolId::of("/missing_type")).is_none(),
        "receiver typing must not depend on type existence"
    );
    assert!(
        tree.symbols()
            .text(view.metadata.declared_type().unwrap())
            .unwrap()
            .contains("SpacemanDMM_private"),
        "runtime metadata unchanged"
    );
}
#[test]
fn public_property_view_uses_actual_profile_formal_and_source_issuance() {
    let source="/datum/base\n    var/SpacemanDMM_private/value\n/datum/base/child\n    value = null\n    proc/check()\n        return\n";
    let (_, inputs) = input_with_primary(source, true, true);
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    let base = tree
        .source_formal_variable_member(SymbolId::of("/datum/base"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    let inherited = tree
        .source_formal_variable_member(SymbolId::of("/datum/base/child"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    assert_eq!(
        base, inherited,
        "value-only override does not manufacture another formal"
    );
    let view = archive
        .checker_variable_properties(inherited, profile)
        .unwrap();
    assert_eq!(view.owner, SymbolId::of("/datum/base"));
    assert_eq!(view.qualifiers, dm_syntax::CHECKER_VAR_PRIVATE);
    assert_eq!(view.declared_hint(), None);
    assert!(
        std::ptr::eq(view.metadata, tree.member(base).unwrap().metadata.as_ref()),
        "borrow SAME original metadata, no reified declaration"
    );
    assert_eq!(
        tree.symbols().text(view.metadata.declared_type().unwrap()),
        Some("/SpacemanDMM_private")
    );
    assert!(archive
        .checker_variable_properties(base, PackedU128::new(profile.get() ^ 1))
        .is_err());
    let (_, ordinary) = input_with_primary(source, true, false);
    let ordinary = ordinary.archive();
    let p = ordinary.tree().checker_builtin_profile().unwrap();
    let id = ordinary
        .tree()
        .source_formal_variable_member(SymbolId::of("/datum/base"), SymbolId::of("value"))
        .unwrap()
        .unwrap();
    assert!(
        ordinary.checker_variable_properties(id, p).is_err(),
        "valid builtin profile alone is not primary qualifier issuance"
    );
}
#[test]
fn public_property_view_preserves_list_container_when_qualifier_is_the_only_element_segment() {
    let source="/datum/holder\n    var/list/SpacemanDMM_private/list_only\n    var/list/SpacemanDMM_private/missing_type/typed_list\n";
    let (_, inputs) = input_with_primary(source, true, true);
    let archive = inputs.archive();
    let tree = archive.tree();
    let profile = tree.checker_builtin_profile().unwrap();
    for (name, hint) in [("list_only", "/list"), ("typed_list", "/list/missing_type")] {
        let formal = tree
            .source_formal_variable_member(SymbolId::of("/datum/holder"), SymbolId::of(name))
            .unwrap()
            .unwrap();
        let view = archive
            .checker_variable_properties(formal, profile)
            .unwrap();
        assert_eq!(view.qualifiers, dm_syntax::CHECKER_VAR_PRIVATE);
        assert_eq!(view.declared_hint(), Some(hint));
        assert_eq!(view.declared_type, Some(SymbolId::of("/list")));
        assert!(tree
            .symbols()
            .text(view.metadata.list_element_type().unwrap())
            .unwrap()
            .contains("SpacemanDMM_private"));
    }
}

#[test]
fn projected_setting_untyped_members_keep_exact_owned_findings_after_current_offset_change() {
    for prefix in ["", "// earlier source \u{e9}\n\n"] {
        let source=format!("{prefix}/datum/static_owner\n    var/static/danger\n/proc/p(holder)\n    set name = holder.danger\n    holder.danger\n");
        let (root,old)=input_with_primary(&source,true,true); let expected=findings(&old,&root,|_|false,||Ok(())).unwrap();
        assert_eq!(expected.len(),2);
        let (root,native)=input_with_primary_host(&source,true,true,Some(crate::untyped_order::projected_body_host_for_test()));
        assert!(matches!(&native.archive().parse(0).unwrap().statement_body().parsed().statements[0].kind,dm_syntax::StatementKind::ProjectedSet{..}));
        assert_eq!(findings(&native,&root,|_|false,||Ok(())).unwrap(),expected);
    }
}

struct MemberControl{polls:usize,fail_at:Option<usize>,denied:bool,wrong:bool,peak:usize}
impl crate::policy_body_demand::WorkspaceWork for MemberControl{type Error=crate::policy_body_demand::PolicyFailure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.polls+=1;if self.fail_at==Some(self.polls){Err(crate::policy_body_demand::PolicyFailure::Operational(std::io::Error::from_raw_os_error(1450)))}else{Ok(())}}fn retain(&mut self,_:usize)->Result<(),Self::Error>{if self.denied{Err(self.overflow())}else{Ok(())}}fn temporary(&mut self,n:usize)->Result<(),Self::Error>{if self.denied{return Err(self.overflow())}self.peak=self.peak.max(n);Ok(())}fn overflow(&mut self)->Self::Error{crate::policy_body_demand::PolicyFailure::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Self::Error{self.overflow()}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Self::Error>{<crate::policy_body_demand::Checked as crate::policy_body_demand::Demand>::parse(a,if self.wrong{(n+1)%a.len()}else{n})}}
fn member_control()->MemberControl{MemberControl{polls:0,fail_at:None,denied:false,wrong:false,peak:0}}
#[test]fn full_workspace_member_preserves_original_qualifiers_static_overrides_and_projected_settings(){let source="/datum/target\n    var/static/danger\n    var/datum/target/next\n/datum/target/child\n    danger = 1\n/datum/target/proc/check(datum/target/T,U,list/datum/target/L)\n    set name = U.danger\n    T.next.danger\n    T.danger\n    U.danger\n    L[1].danger\n";let(root,owned)=input(source,true);let expected=findings(&owned,&root,|_|false,||Ok(())).unwrap();let host=crate::untyped_order::projected_body_host_for_test();let(root,actual)=input_with_primary_host(source,true,true,Some(host));let mut control=member_control();assert_eq!(findings_workspace_using(&actual,&root,|_|false,&mut control).unwrap(),expected);assert!(!expected.is_empty());assert!(control.peak>0);}
#[test]fn full_workspace_member_control_preserves_first_io_quota_foreign_body_and_recovery(){let source=format!("/datum/member\n    var/static/danger\n/datum/member/proc/first(U)\n{}\n/datum/member/proc/second(U)\n    U.danger\n","    U.danger\n".repeat(256));let(root,inputs)=input(&source,true);let mut good=member_control();let expected=findings_workspace_using(&inputs,&root,|_|false,&mut good).unwrap();let mut failed=member_control();failed.fail_at=Some(good.polls/2);assert!(matches!(findings_workspace_using(&inputs,&root,|_|false,&mut failed),Err(crate::policy_body_demand::PolicyFailure::Operational(ref error))if error.raw_os_error()==Some(1450)));assert_eq!(failed.polls,failed.fail_at.unwrap());let mut denied=member_control();denied.denied=true;assert!(matches!(findings_workspace_using(&inputs,&root,|_|false,&mut denied),Err(crate::policy_body_demand::PolicyFailure::Operational(ref error))if error.kind()==std::io::ErrorKind::OutOfMemory));let mut wrong=member_control();wrong.wrong=true;assert!(matches!(findings_workspace_using(&inputs,&root,|_|false,&mut wrong),Err(crate::policy_body_demand::PolicyFailure::Unsupported(ref error))if error.0.contains("foreign original body")));assert_eq!(findings_workspace_using(&inputs,&root,|_|false,&mut member_control()).unwrap(),expected);}
#[test]fn full_workspace_member_receiver_chain_preserves_mid_lookup_io_denial_and_recovery(){let chain=format!("T.{}next","next.".repeat(32));let source=format!("/datum/chain\n    var/datum/chain/next\n/datum/chain/proc/check(datum/chain/T)\n    {chain}.danger\n");let(_,inputs)=input(&source,true);let archive=inputs.archive();let tree=archive.tree();let body=archive.parse_checked(0).unwrap();let scope=untyped::archived_scope(&body,tree,&[]).unwrap();let receiver=Receiver{archive,tree,profile:tree.checker_builtin_profile().unwrap(),owner:scope.owner,locals:&scope.locals};let dm_syntax::StatementKind::Expression(expression)=&body.statement_body().parsed().statements[0].kind else{panic!("actual member expression")};let ExprKind::Member{object,..}=&expression.kind else{panic!("actual member receiver")};let expected=receiver.of(object,&mut||Ok::<(),Unsupported>(())).unwrap();assert_eq!(expected.as_deref(),Some("/datum/chain"));for denied in [false,true]{let mut polls=0;let result=receiver.of(object,&mut||{polls+=1;if polls==40{Err(crate::policy_body_demand::PolicyFailure::Operational(if denied{std::io::ErrorKind::OutOfMemory.into()}else{std::io::Error::from_raw_os_error(1450)}))}else{Ok(())}});assert!(matches!(result,Err(crate::policy_body_demand::PolicyFailure::Operational(ref actual))if if denied{actual.kind()==std::io::ErrorKind::OutOfMemory}else{actual.raw_os_error()==Some(1450)}));assert_eq!(polls,40);}let mut count=0;assert_eq!(receiver.of(object,&mut||{count+=1;Ok::<(),Unsupported>(())}).unwrap(),expected);assert!(count>100,"receiver and exact lookup steps stay controlled");}
