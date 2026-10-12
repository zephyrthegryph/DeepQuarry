use super::*;
use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
struct Source;
const SOURCE: &str = "/var/global/global_first = 1\n/proc/work()\n    var/static/procedure_value = 2\n    return procedure_value\n/var/global/global_second = 3\n";
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(SOURCE.into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, _: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Missing
    }
}
#[test]
fn root_procedure_static_precedes_global_storage_in_both_rank_producers() {
    let frontend = dm_tree::frontend::build(
        std::path::Path::new("order.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .unwrap();
    let declaration = dm_tree::initializers::capture_declaration_plan(
        &frontend.snapshot,
        &frontend.emission_order,
    )
    .unwrap();
    let parsed = dm_syntax::parse(SOURCE);
    let procedure = parsed
        .items
        .iter()
        .find(|item| item.header.contains("work("))
        .unwrap();
    let identity = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    let capture = dm_tree::procedure_statics::capture(identity, &procedure.children).unwrap();
    let occurrence = frontend.emission_order.iter().copied().find(|id| frontend.snapshot.occurrences.get(*id).is_some_and(|row| matches!(row.target,dm_tree::Target::Member(member) if frontend.snapshot.tree.member(member).is_some_and(|node| node.kind==dm_tree::MemberKind::Proc)))).unwrap();
    let plan = dm_tree::initializers::with_captured_procedure_statics(
        &declaration,
        &[(occurrence, capture)],
    )
    .unwrap();
    let roster = StartupAllocationRoster::issue_current(&plan, &[], &frontend).unwrap();
    let classified = crate::initializer_policy::ClassifiedInitializers {
        accepted: Vec::new(),
        writes: Vec::new(),
        groups: Vec::new(),
    };
    let finalized = roster.finalize(&plan, &classified, &Host).unwrap();
    assert_eq!(roster.allocation.keys, finalized.keys);
    assert!(matches!(finalized.keys[0], Key::ProcedureStatic(_)));
    let globals: Vec<_> = finalized.keys[1..]
        .iter()
        .map(|key| match key {
            Key::Variable { name, .. } => plan.symbols.text(*name).unwrap(),
            _ => panic!("unexpected storage"),
        })
        .collect();
    assert_eq!(globals, ["global_first", "global_second"]);
}

#[test]
fn first_callable_registration_preserves_exact_overload_occurrence() {
    let first = dm_ir::ProcedureIdentity {
        owner: SymbolId::of("/"),
        name: SymbolId::of("work"),
        verb: false,
        occurrence: 0,
    };
    let later = dm_ir::ProcedureIdentity {
        occurrence: 1,
        ..first
    };
    let target = |procedure| {
        InitializerTarget::ProcedureStatic(dm_ir::ProcedureStaticIdentity {
            procedure,
            name: SymbolId::of("local"),
        })
    };
    assert!(first_root_static(&target(first), Some(first)));
    assert!(!first_root_static(&target(later), Some(first)));
    assert!(!first_root_static(&target(first), None));
}
