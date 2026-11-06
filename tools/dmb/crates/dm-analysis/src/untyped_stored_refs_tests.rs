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
        .join("stored-reference-native-fixture");
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

fn scan(
    source: &str,
    configure: impl FnOnce(&mut HashMap<String, Vec<String>>),
) -> Vec<StoredFinding> {
    let (root, inputs) = input(source, true);
    let mut relations = HashMap::new();
    configure(&mut relations);
    let policy = StoredPolicy {
        exempt_types: &[],
        registry: &[],
        transient_types: &[],
        work_queues: &[],
        relations: &relations,
        init_only: &[],
        has_schema: &|_, _| false,
    };
    stored_findings(
        &inputs,
        &root,
        &policy,
        |_| false,
        &mut (64 * 1024 * 1024),
        || Ok(()),
    )
    .unwrap()
}
#[test]
fn stored_fields_are_own_formals_not_child_default_overrides_and_relations_are_symmetric() {
    let source="/datum/holder\n    var/datum/loose\n    var/datum/kept\n/datum/holder/child\n    loose = null\n";
    let rows = scan(source, |r| {
        r.insert("kept".into(), vec!["/datum/holder/child".into()]);
    });
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rule, "var");
    assert_eq!(rows[0].line, 2);
    assert_eq!(
        rows[0].message,
        "/datum/holder/var/loose holds a /datum outside a declared relation"
    );
    assert_eq!(rows[0].ident, "/datum/holder::loose");
}
#[test]
fn stored_list_key_write_does_not_require_a_list_signature_but_compound_rejects_scalar() {
    let source="/datum/holder\n    var/untyped\n    var/icon/ignored\n    proc/check(datum/D)\n        untyped[D] = null\n        ignored[D] += D\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rule, "list");
    assert_eq!(rows[0].line, 2);
    assert!(rows[0].message.ends_with("(e.g. code/probe.dm:5)"));
}
#[test]
fn stored_list_literal_observes_keys_values_and_first_source_write() {
    let source="/datum/holder\n    var/list/items\n    proc/check(datum/D)\n        items = list(D = null)\n        items.Add(D)\n        items.Insert(1,D)\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert!(rows[0].message.ends_with("(e.g. code/probe.dm:4)"));
}
#[test]
fn stored_typed_list_seed_is_after_body_write_and_untyped_return_is_not_inferred() {
    let source="/datum/holder\n    var/list/datum/seeded\n    var/list/calls\n    proc/unknown()\n        return new /datum\n    proc/check(datum/D)\n        seeded += D\n        calls += unknown()\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].line, 2);
    assert!(rows[0].message.ends_with("(e.g. code/probe.dm:7)"));
}
#[test]
fn stored_single_static_counts_comma_static_and_cstyle_static_do_not() {
    let source="/proc/check(datum/D)\n    var/static/list/single\n    single += D\n    var/static/list/first, second\n    first += D\n    second += D\n    for(var/static/list/loop; 0; )\n        loop += D\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].line, 2);
    assert!(rows[0].ident.is_empty());
    assert!(rows[0].message.starts_with("a proc's static list"));
}
#[test]
fn stored_issued_array_preserves_the_original_typed_var_finding() {
    let source = "/datum/holder/var/datum/ref\n/proc/probe()\n    var/list/L[2]\n";
    let (root, inputs) = input(source, true);
    let relations = HashMap::new();
    let p = StoredPolicy {
        exempt_types: &[],
        registry: &[],
        transient_types: &[],
        work_queues: &[],
        relations: &relations,
        init_only: &[],
        has_schema: &|_, _| false,
    };
    let rows = stored_findings(
        &inputs,
        &root,
        &p,
        |_| false,
        &mut (64 * 1024 * 1024),
        || Ok(()),
    )
    .unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].ident, "/datum/holder::ref");
}
#[test]
fn stored_original_parameter_receipts_preserve_leading_vs_embedded_qualifiers() {
    let source="/datum/holder\n    var/list/items\n    proc/check(static/datum/D, datum/static/embedded, SpacemanDMM_private/datum/P)\n        items.Add(D,embedded,P)\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rule, "list");
    assert!(rows[0].message.ends_with("(e.g. code/probe.dm:4)"));
}
#[test]
fn stored_no_profile_cancel_and_zero_budget_fail_closed() {
    for certified in [false, true] {
        let (root, inputs) = input("/datum/holder/var/datum/ref\n", certified);
        let rel = HashMap::new();
        let p = StoredPolicy {
            exempt_types: &[],
            registry: &[],
            transient_types: &[],
            work_queues: &[],
            relations: &rel,
            init_only: &[],
            has_schema: &|_, _| false,
        };
        assert!(stored_findings(&inputs, &root, &p, |_| false, &mut 0, || Ok(())).is_err());
        assert!(stored_findings(
            &inputs,
            &root,
            &p,
            |_| false,
            &mut (64 * 1024 * 1024),
            || Err("cancelled".into())
        )
        .is_err());
    }
}

#[test]
fn stored_embedded_modifier_cannot_infer_the_runtime_normalized_alias_type() {
    let source="/holder_alias\n    parent_type=/datum\n/datum/holder\n    var/list/ignored\n    var/list/witness\n    proc/check(holder_alias/static/X, datum/D)\n        ignored += X\n        witness += D\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].ident, "/datum/holder::witness");
    assert_eq!(rows[0].line, 5);
    assert!(rows[0].message.ends_with("(e.g. code/probe.dm:8)"));
}

#[test]
fn stored_single_body_polls_cancellation_per_event_without_partial_rows() {
    fn run(
        statements: usize,
        cancel_at: Option<usize>,
    ) -> (usize, Result<Vec<StoredFinding>, Unsupported>) {
        let source = format!(
            "/datum/holder\n    var/list/items\n    proc/check(datum/D)\n{}",
            "        items += D\n".repeat(statements)
        );
        let (root, inputs) = input(&source, true);
        let relations = HashMap::new();
        let policy = StoredPolicy {
            exempt_types: &[],
            registry: &[],
            transient_types: &[],
            work_queues: &[],
            relations: &relations,
            init_only: &[],
            has_schema: &|_, _| false,
        };
        let mut polls = 0;
        let result = stored_findings(
            &inputs,
            &root,
            &policy,
            |_| false,
            &mut (64 * 1024 * 1024),
            || {
                polls += 1;
                if cancel_at == Some(polls) {
                    Err("cancelled during stored body event".into())
                } else {
                    Ok(())
                }
            },
        );
        (polls, result)
    }
    let (short, rows) = run(1, None);
    assert_eq!(rows.unwrap().len(), 1);
    let (long, rows) = run(100, None);
    assert_eq!(rows.unwrap().len(), 1);
    assert!(
        long > short + 50,
        "events must poll inside one body: {short} -> {long}"
    );
    let stop = short + 10;
    let (polls, result) = run(100, Some(stop));
    assert_eq!(polls, stop);
    assert_eq!(result.unwrap_err().0, "cancelled during stored body event");
}

#[test]
fn stored_property_temporary_includes_original_macro_header_and_provider_path_width() {
    // Expanded qualifier words can be erased by runtime type normalization.
    // The ORIGINAL declaration span, not that short normalized symbol, bounds
    // property projection. No raw-input byte count stands in for expansion.
    let qualifiers = "tmp/".repeat(1024);
    let source = format!(
        "#define QUAL {}\n/datum/holder\n    var/QUAL/datum/ref\n",
        qualifiers.trim_end_matches('/')
    );
    let (root, inputs) = input(&source, true);
    let width =
        maximum_policy_temporary_width(inputs.archive(), &inputs, &root, || Ok(())).unwrap();
    assert!(
        width >= qualifiers.len(),
        "expanded original header was omitted"
    );
    for file in inputs.files() {
        assert!(
            width >= file.path().as_os_str().len() * 3,
            "provider path/lossy expansion was omitted"
        );
    }
}

#[test]
fn stored_constants_use_original_native_declaration_flags_for_fields_and_lists() {
    let source = "/datum/holder\n    var/const/datum/fixed = null\n    var/const/list/fixed_items = list()\n    var/datum/loose\n    proc/check(datum/D)\n        fixed_items += D\n";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].rule, "var");
    assert_eq!(rows[0].ident, "/datum/holder::loose");
}

#[test]
fn absolute_header_type_declaration_preserves_stored_parameter_scope_and_original_finding() {
    let plain = "/datum/holder\n    var/list/refs\n    proc/check(datum/D)\n        refs += D\n";
    let absolute="/datum/holder\n    var/list/refs\n    proc/check(datum/D,/datum/marker/A)\n        refs += D\n";
    let old = scan(plain, |_| {});
    let current = scan(absolute, |_| {});
    assert_eq!(old.len(), 1);
    assert_eq!(current.len(), 1);
    assert_eq!(old[0].rule, current[0].rule);
    assert_eq!(old[0].message, current[0].message);
}

#[test]
fn projected_setting_stored_list_writes_keep_owned_static_declaration_and_statement_origins() {
    for prefix in ["", "// earlier source \u{e9}\n\n"] {
        let source=format!("{prefix}/datum/holder\n    var/list/items\n    proc/p(datum/D)\n        var/static/list/local\n        set name = items.Add(D)\n        set desc = local.Add(D)\n");
        let relations=HashMap::new();
        let policy=StoredPolicy{exempt_types:&[],registry:&[],transient_types:&[],work_queues:&[],relations:&relations,init_only:&[],has_schema:&|_,_|false};
        let (root,old)=input(&source,true);let expected=stored_findings(&old,&root,&policy,|_|false,&mut(64*1024*1024),||Ok(())).unwrap();
        assert_eq!(expected.len(),2);
        assert!(expected.iter().any(|r|r.ident.is_empty()),"original current static-local declaration origin retained");
        let (root,native)=input_with_host(&source,true,Some(crate::untyped_order::projected_body_host_for_test()));
        assert!(matches!(&native.archive().parse(0).unwrap().statement_body().parsed().statements[1].kind,dm_syntax::StatementKind::ProjectedSet{..}));
        assert_eq!(stored_findings(&native,&root,&policy,|_|false,&mut(64*1024*1024),||Ok(())).unwrap(),expected);
    }
}

struct StoredWork{calls:usize,stop:usize,denial:bool}
impl crate::policy_body_demand::WorkspaceWork for StoredWork{type Error=crate::policy_body_demand::PolicyFailure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Self::Error>{self.calls+=1;if self.calls==self.stop{return Err(Self::Error::Operational(std::io::Error::from_raw_os_error(1450)))}Ok(())}fn retain(&mut self,_:usize)->Result<(),Self::Error>{self.checkpoint()?;if self.denial{Err(Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into()))}else{Ok(())}}fn temporary(&mut self,n:usize)->Result<(),Self::Error>{self.retain(n)}fn overflow(&mut self)->Self::Error{Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Self::Error{Self::Error::Operational(std::io::ErrorKind::OutOfMemory.into())}fn body<'a>(&mut self,a:&'a dm_tree::frontend::BodyArchive,n:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Self::Error>{self.checkpoint()?;a.parse_checked(n).map_err(|e|match e{dm_tree::frontend::BodySyntaxFailure::Operational(e)=>Self::Error::Operational(e),dm_tree::frontend::BodySyntaxFailure::Syntax(e)=>Unsupported(e.message).into()})}}

#[test]fn complete_stored_same_walk_preserves_first_inner_io_quota_and_recovery(){let(root,inputs)=input("/datum/holder\n    var/datum/loose\n    var/list/items\n    proc/check(datum/D)\n        var/static/list/local\n        local += D\n        items.Add(D)\n        items[D] = D\n",true);let relations=HashMap::new();let p=StoredPolicy{exempt_types:&[],registry:&[],transient_types:&[],work_queues:&[],relations:&relations,init_only:&[],has_schema:&|_,_|false};let mut good=StoredWork{calls:0,stop:usize::MAX,denial:false};let expected=stored_findings_workspace_using(&inputs,&root,&p,|_|false,&mut usize::MAX,&mut good,&mut|_,_,_|Ok(false)).unwrap();assert_eq!(expected.len(),3);assert!(good.calls>100);for stop in[1,17,99,good.calls/2]{let mut work=StoredWork{calls:0,stop,denial:false};let error=stored_findings_workspace_using(&inputs,&root,&p,|_|false,&mut usize::MAX,&mut work,&mut|_,_,_|Ok(false)).unwrap_err();assert!(matches!(error,crate::policy_body_demand::PolicyFailure::Operational(e)if e.raw_os_error()==Some(1450)));assert_eq!(work.calls,stop);}let mut denied=StoredWork{calls:0,stop:usize::MAX,denial:true};assert!(matches!(stored_findings_workspace_using(&inputs,&root,&p,|_|false,&mut usize::MAX,&mut denied,&mut|_,_,_|Ok(false)),Err(crate::policy_body_demand::PolicyFailure::Operational(e))if e.kind()==std::io::ErrorKind::OutOfMemory));let mut recovered=StoredWork{calls:0,stop:usize::MAX,denial:false};assert_eq!(stored_findings_workspace_using(&inputs,&root,&p,|_|false,&mut usize::MAX,&mut recovered,&mut|_,_,_|Ok(false)).unwrap(),expected);}

#[test]
fn stored_alist_method_literal_and_static_preserve_first_observation() {
    let source = "/datum/holder
    var/alist/methods
    var/alist/literal
    var/alist/insert_index_only
    proc/check(datum/D)
        methods.Add(D)
        methods = alist(D)
        literal = alist(D = null)
        insert_index_only.Insert(D, null)
        var/static/alist/persistent
        persistent.Insert(1, D)
        var/alist/local
        local.Add(D)
";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 3);
    for (declaration, ident, write) in [
        (2, "/datum/holder::methods", 6),
        (3, "/datum/holder::literal", 8),
        (10, "", 11),
    ] {
        let row = rows.iter().find(|row| row.line == declaration).unwrap();
        assert_eq!((row.rule, row.ident.as_str()), ("list", ident));
        assert!(row.message.ends_with(&format!("(e.g. code/probe.dm:{write})")));
    }
}

#[test]
fn stored_nested_index_writes_follow_only_the_legacy_container_chain() {
    let source = "/datum/holder
    var/list/keyed
    var/list/value
    var/alist/added
    var/list/unioned
    var/list/logical
    var/list/grouped
    var/icon/scalar
    var/list/not_added
    proc/check(datum/D)
        keyed[1][D] = null
        keyed.Add(D)
        value[1][2] = D
        added[1][2] += D
        unioned[1][2] |= D
        logical[1][2] ||= D
        (grouped[1])[2] += D
        scalar[1][2] += D
        not_added[1][2] += null
";
    let rows = scan(source, |_| {});
    assert_eq!(rows.len(), 5);
    for (name, write) in [("keyed", 11), ("value", 13), ("added", 14), ("unioned", 15), ("logical", 16)] {
        let row = rows.iter().find(|row| row.ident.ends_with(&format!("::{name}"))).unwrap();
        assert!(row.message.ends_with(&format!("(e.g. code/probe.dm:{write})")));
    }
}
