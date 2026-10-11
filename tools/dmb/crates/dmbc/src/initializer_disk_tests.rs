use super::super::{lower_plan, LowerOptions, LoweredInitializers};
use super::*;
use std::{
    path::{Path, PathBuf},
    sync::atomic::Ordering,
};
struct Temp(PathBuf);
impl Temp {
    fn new() -> Self {
        let base = if cfg!(windows) {
            PathBuf::from("E:/dq-cache/dmb-protocol-checks")
        } else {
            std::env::temp_dir()
        };
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let root = base.join(format!(
            "initializer-shared-disk-{}-{stamp}",
            std::process::id()
        ));
        std::fs::create_dir_all(&root).unwrap();
        Self(root)
    }
}
impl Drop for Temp {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}
struct Source<'a>(&'a str);
impl dm_preprocess::SourceProvider for Source<'_> {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn run(source: &str, memo: Option<&crate::lowering_memo::ProcedureMemo>) -> LoweredInitializers {
    let frontend = dm_tree::frontend::build(
        Path::new("shared.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let declarations = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let plan = declarations.plan();
    let host = frontend.snapshot.tree.as_ref();
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: host,
        symbols: plan.symbols.as_ref(),
    };
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    lower_plan(
        (&frontend, plan),
        &evaluator,
        host,
        None,
        true,
        LowerOptions {
            allocation: None,
            observer: None,
            memo,
            executor: Some(&executor),
            classification: memo.and_then(|m| {
                m.initializers
                    .as_ref()
                    .map(|store| crate::initializer_policy::InitializerReuse {
                        store,
                        resolver: host,
                        policy: m.policy,
                        resource_search_context: None,
                    })
            }),
            parallel: Some((
                crate::initializer_policy::ParallelEvaluator {
                    factory: &evaluator,
                    engine: None,
                },
                &executor,
            )),
        },
    )
    .unwrap()
}
fn request(root: &Path) -> (Arc<LazyDisk>, crate::lowering_memo::ProcedureMemo) {
    let disk = Arc::new(LazyDisk::new(root.into()));
    let mut host = crate::runner_host::BuildHost::one_shot();
    let memo = host
        .procedure_memo(37, Some(Arc::clone(&disk)), true)
        .unwrap();
    (disk, memo)
}
fn equal(a: &LoweredInitializers, b: &LoweredInitializers) {
    assert_eq!(a.units.len(), b.units.len());
    for (a, b) in a.units.iter().zip(&b.units) {
        assert!(crate::lowering_memo_wire::verification_code_equal(
            &a.code, &b.code
        ));
        assert_eq!(a.debug_origins, b.debug_origins);
        assert_eq!(a.write_ordinals, b.write_ordinals);
    }
}
#[test]
fn one_shot_shared_initializer_disk_rebinds_and_recomputes_only_changed_write() {
    let root = Temp::new();
    let source = "/datum/example\n    var/list/first = list(7)\n    var/list/second = list(9)\n";
    let (disk, writer) = request(&root.0);
    let first = run(source, Some(&writer));
    let report = disk.finish_batch().unwrap();
    assert!(
        report.records >= 3,
        "two fragments and assembly must use the existing spool"
    );
    assert!(
        writer.take_pending().is_empty(),
        "no anonymous group transport is used"
    );
    let (_, reader) = request(&root.0);
    let warm = run(source, Some(&reader));
    equal(&first, &warm);
    assert_eq!(
        reader
            .initializer_assemblies
            .as_ref()
            .unwrap()
            .hits
            .load(Ordering::Relaxed),
        1
    );
    assert_eq!(reader.anonymous_initializer_verification_counts(), (0, 0));
    let shifted = format!("\n\n{source}");
    let (_, shifted_reader) = request(&root.0);
    equal(&run(&shifted, Some(&shifted_reader)), &run(&shifted, None));
    assert_eq!(
        shifted_reader
            .initializer_assemblies
            .as_ref()
            .unwrap()
            .hits
            .load(Ordering::Relaxed),
        1
    );
    let changed = source.replace("list(9)", "list(11)");
    let (_, changed_reader) = request(&root.0);
    equal(&run(&changed, Some(&changed_reader)), &run(&changed, None));
    let fragments = changed_reader.initializer_fragments.as_ref().unwrap();
    assert_eq!(fragments.hits.load(Ordering::Relaxed), 1);
    assert_eq!(fragments.recomputed.load(Ordering::Relaxed), 1);
}
#[test]
fn one_shot_without_disk_still_uses_shared_initializer_core() {
    let mut host = crate::runner_host::BuildHost::one_shot();
    let memo = host.procedure_memo(1, None, true).unwrap();
    let source = "/datum/example\n    var/list/value = list(7)\n";
    equal(&run(source, Some(&memo)), &run(source, None));
    assert_eq!(
        memo.initializer_fragments
            .as_ref()
            .unwrap()
            .recomputed
            .load(Ordering::Relaxed),
        1
    );
    assert_eq!(
        memo.initializer_assemblies
            .as_ref()
            .unwrap()
            .recomputed
            .load(Ordering::Relaxed),
        1
    );
}
#[test]
fn portable_recipe_ignores_source_spans_but_not_runtime_values_or_policy() {
    let mut symbols = dm_ir::SymbolTable::default();
    let owner = symbols.intern("/datum/example").unwrap();
    let name = symbols.intern("value").unwrap();
    let expression = dm_syntax::parse_expression("list(7)").expr.unwrap();
    let write = dm_ir::InitializerWrite {
        source_site: dm_ir::InitializerSite::Declaration,
        target: dm_ir::InitializerTarget::Instance {
            declaring_owner: owner,
            receiver_owner: owner,
            name,
        },
        lexical_owner: owner,
        lexical_procedure: None,
        value: dm_ir::InitializerValue::NoAuthoredValue,
        declared_array: None,
        declaration_flags: Some(0),
    };
    let binding = receipts::Binding::fragment(
        0,
        receipts::FragmentInputs {
            write,
            shape: receipts::Shape::Expression,
            policy: 7,
            resource_context: None,
            debug_enabled: true,
            accepted: None,
        },
    );
    let first = disk_recipe::capture(&binding, b"policy-a", None, &[&expression]).unwrap();
    let shifted = dm_syntax::parse_expression("   list(7)").expr.unwrap();
    assert_eq!(
        disk_recipe::capture(&binding, b"policy-a", None, &[&shifted])
            .unwrap()
            .bytes,
        first.bytes
    );
    let changed = dm_syntax::parse_expression("list(8)").expr.unwrap();
    assert_ne!(
        disk_recipe::capture(&binding, b"policy-a", None, &[&changed])
            .unwrap()
            .bytes,
        first.bytes
    );
    assert_ne!(
        disk_recipe::capture(&binding, b"policy-b", None, &[&expression])
            .unwrap()
            .bytes,
        first.bytes
    );
    let resource = dm_syntax::parse_expression("list('asset.txt')")
        .expr
        .unwrap();
    assert!(disk_recipe::capture(&binding, b"policy-a", None, &[&resource]).is_none());
}

#[test]
fn initializer_bucket_rejects_missing_mandatory_and_corrupt_later_row_before_replay() {
    let output = run("/datum/example\n    var/list/value = list(7)\n", None);
    let mut symbols = dm_ir::SymbolTable::default();
    let owner = symbols.intern("/datum/example").unwrap();
    let query = dm_ir::ResolveQuery::Ancestry(owner);
    let recipe = disk_recipe::Recipe {
        bytes: b"exact-current-test-recipe".to_vec(),
        mandatory: vec![query],
        assembly: true,
        roots: 1,
    };
    let reads = vec![dm_session::ResolverRead {
        domain: query.domain(),
        query,
        answer: dm_ir::ResolvedMeaning::Missing,
    }];
    let valid = crate::lowering_memo_wire::initializer::encode(
        recipe.bytes.clone(),
        true,
        1,
        recipe.mandatory.clone(),
        &reads,
        &output.units[0].code,
    )
    .unwrap();
    let valid_bucket = dm_cache::encode_variants(&[valid.clone()]).unwrap();
    assert_eq!(
        Transport::current_candidates(&valid_bucket, &recipe)
            .unwrap()
            .len(),
        1
    );
    let omitted = crate::lowering_memo_wire::initializer::omit_mandatory(&valid);
    // A self-consistent disk-provided empty ledger cannot replace current edges.
    let missing = dm_cache::encode_variants(&[valid.clone(), omitted]).unwrap();
    let corrupt = dm_cache::encode_variants(&[valid, b"corrupt-later-row".to_vec()]).unwrap();
    for bucket in [missing, corrupt] {
        let calls = std::cell::Cell::new(0);
        let admitted = Transport::current_candidates(&bucket, &recipe).map(|rows| {
            // This is the same pre-replay boundary used by lookup: no host is
            // available to bucket validation, including earlier valid rows.
            for row in rows {
                for _ in row.reads {
                    calls.set(calls.get() + 1);
                }
            }
        });
        assert!(admitted.is_err());
        assert_eq!(calls.get(), 0);
    }
}

#[test]
fn initializer_transport_declines_foreign_current_engine_owner() {
    let root = Temp::new();
    let mut first = crate::runner_host::BuildHost::one_shot();
    let bytes = include_bytes!("../../../fixtures/native_template.bin").to_vec();
    let a = first
        .engine(
            PathBuf::from("E:/fixture/a.dme"),
            Default::default(),
            true,
            bytes.clone(),
        )
        .unwrap();
    // Independently parse identical bytes/schema: equality of the immutable
    // payload cannot replace association with the authenticated physical owner.
    let foreign = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../fixtures/native_template.bin"),
        a.snapshot.interpretation_schema(),
    )
    .unwrap();
    let symbols = dm_ir::SymbolTable::default();
    struct Empty;
    impl dm_ir::Resolver for Empty {
        fn resolve(&self, q: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            dm_ir::ResolvedMeaning::Unsupported(q)
        }
    }
    let evaluator = crate::driver_facts::DriverEvaluator {
        pure_calls: None,
        resource_search_context: None,
        resolver: &Empty,
        symbols: &symbols,
    };
    let transport = Transport::new(
        Arc::new(LazyDisk::new(root.0.clone())),
        Some(a.abi_engine_owner()),
        1,
        false,
    );
    transport.configure(Some(crate::initializer_policy::ParallelEvaluator {
        factory: &evaluator,
        engine: Some(&foreign),
    }));
    assert!(matches!(transport.policy.get(), Some(None)));
}

#[test]
fn modified_initializer_disk_reissues_moved_nested_ast_and_declines_changed_inputs() {
    let root = Temp::new();
    let source = "/datum/item\n    var/amount = 0\n/datum/example\n    var/list/value = list(/datum/item{amount = 7})\n";
    let (disk, writer) = request(&root.0);
    let first = run(source, Some(&writer));
    assert_eq!(first.units.len(), 1);
    assert_eq!(first.units[0].code.modified_instances.len(), 1);
    assert!(disk.finish_batch().unwrap().records >= 2);
    let shifted = format!("\n\n{source}");
    let (_, reader) = request(&root.0);
    let warm = run(&shifted, Some(&reader));
    equal(&warm, &run(&shifted, None));
    assert_eq!(
        reader
            .initializer_assemblies
            .as_ref()
            .unwrap()
            .hits
            .load(Ordering::Relaxed),
        1
    );
    assert_eq!(
        warm.units[0]
            .code
            .modified_instances
            .values()
            .next()
            .unwrap()
            .source_span,
        run(&shifted, None).units[0]
            .code
            .modified_instances
            .values()
            .next()
            .unwrap()
            .source_span
    );
    for changed in [
        source.replace("amount = 7", "amount = 8"),
        source.replace("/datum/item", "/datum/other"),
    ] {
        let (_, current) = request(&root.0);
        equal(&run(&changed, Some(&current)), &run(&changed, None));
        assert_eq!(
            current
                .initializer_assemblies
                .as_ref()
                .unwrap()
                .hits
                .load(Ordering::Relaxed),
            0
        );
        assert_eq!(
            current
                .initializer_fragments
                .as_ref()
                .unwrap()
                .recomputed
                .load(Ordering::Relaxed),
            1
        );
    }
    let mut host = crate::runner_host::BuildHost::one_shot();
    let current = host
        .procedure_memo(38, Some(Arc::new(LazyDisk::new(root.0.clone()))), true)
        .unwrap();
    equal(&run(source, Some(&current)), &run(source, None));
    assert_eq!(
        current
            .initializer_assemblies
            .as_ref()
            .unwrap()
            .hits
            .load(Ordering::Relaxed),
        0
    );
}

#[test]
fn modified_initializer_bucket_requires_complete_unique_reference_roster() {
    let source = "/datum/item\n    var/amount = 0\n/datum/example\n    var/list/value = list(/datum/item{amount = 7})\n";
    let output = run(source, None);
    let code = &output.units[0].code;
    let root = dm_syntax::parse_expression("list(/datum/item{amount = 7})")
        .expr
        .unwrap();
    let (reference, captured) = code.modified_instances.iter().next().unwrap();
    let expression =
        crate::modified_initializers::ExpressionRecipe::from_capture(*reference, captured, &root)
            .unwrap();
    let mut stripped = code.as_ref().clone();
    stripped.modified_instances.clear();
    let bytes = crate::lowering_memo_wire::initializer::encode_with_modified(
        b"modified-unit-codec".to_vec(),
        true,
        1,
        Vec::new(),
        &[],
        &stripped,
        vec![(0, expression.disk_evidence().unwrap())],
    )
    .unwrap();
    let valid = dm_cache::encode_variants(&[bytes.clone()]).unwrap();
    let candidate = crate::lowering_memo_wire::initializer::decode_bucket(&valid)
        .unwrap()
        .pop()
        .unwrap();
    assert_eq!(candidate.modified.len(), 1);
    assert!(candidate.modified[0].1.accepts_current_path(&root));
    let wrong_path = dm_syntax::parse_expression("list(7)").expr.unwrap();
    assert!(!candidate.modified[0].1.accepts_current_path(&wrong_path));
    struct ChangedRuntimeType;
    impl dm_ir::Resolver for ChangedRuntimeType {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::RuntimeType(_) => {
                    dm_ir::ResolvedMeaning::Symbol(dm_ir::SymbolId::of("/datum/other"))
                }
                _ => dm_ir::ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let mut symbols = dm_ir::SymbolTable::default();
    symbols.intern("/datum/example").unwrap();
    assert!(
        candidate.modified[0]
            .1
            .reissue(&root, &ChangedRuntimeType, &symbols)
            .is_none(),
        "current runtime-type meaning is mandatory even for identical syntax/evidence"
    );
    for duplicate in [false, true] {
        let bad =
            crate::lowering_memo_wire::initializer::corrupt_modified_roster(&bytes, duplicate);
        let bucket = dm_cache::encode_variants(&[bytes.clone(), bad]).unwrap();
        assert!(crate::lowering_memo_wire::initializer::decode_bucket(&bucket).is_err());
    }
}
