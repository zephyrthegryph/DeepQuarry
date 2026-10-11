use super::*;
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> ColdFrontend {
    dm_tree::frontend::build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
struct LocalPolicy;
impl AbiPolicy for LocalPolicy {
    fn inputs(
        &self,
        _: UnitIdentity,
        _: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        Ok(ProcedureInputs::default())
    }
}

#[test]
fn prepared_symbolic_namespace_matches_current_effective_rows_and_rejects_foreign_owner() {
    for source in [
        "/datum/a/proc/p()\n    return 1\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n",
        "\n/datum/added\n    var/field = 1\n/proc/new_body()\n    return 9\n/datum/a/proc/p()\n    return 4\n",
    ] {
        let frontend = frontend(source);
        let roster = PreparedBodyRoster::issue(&frontend).ok().unwrap();
        let bindings = roster.source_bindings(&frontend).unwrap();
        assert!(std::ptr::eq(bindings, roster.source_bindings(&frontend).unwrap()));
        let mut expected: std::collections::BTreeSet<_> = frontend.snapshot.tree.types()
            .iter().map(|node| dm_ir::SymRef::Type(node.path)).collect();
        for source in source_unit_roster(&frontend).unwrap().into_iter().filter(|source| source.effective) {
            let identity = source.identity;
            expected.insert(match identity.namespace {
                Namespace::Proc => dm_ir::SymRef::Proc { owner: identity.owner, name: identity.name, occurrence: identity.occurrence },
                Namespace::Verb => dm_ir::SymRef::Verb { owner: identity.owner, name: identity.name, occurrence: identity.occurrence },
            });
        }
        assert_eq!(bindings, &expected);
        assert!(roster.source_bindings(&self::frontend(source)).is_none());
    }
}

#[test]
fn prepared_rows_keep_exact_current_order_identity_and_key_after_structural_edits() {
    for source in [
        "/datum/a/proc/p()\n    return 1\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n",
        "\n/proc/new_body()\n    return 9\n/datum/a/proc/p()\n    return 1\n/datum/a/p()\n    return 4\n/datum/a/p()\n    return 2\n/datum/a/verb/v()\n    return 3\n",
    ] {
        let frontend = frontend(source);
        let roster = PreparedBodyRoster::issue(&frontend).ok().expect("current roster");
        let old = source_unit_roster(&frontend).unwrap();
        assert_eq!(roster.ordered().map(PreparedBody::source).collect::<Vec<_>>(), old);
        for row in roster.ordered() {
            let input = frontend.body_input(row.body()).unwrap();
            assert!(std::ptr::eq(input.source(), row.input().source()));
            let tail = crate::lowering_memo::key_recipe::PreparedKey::Parsed(vec![7, 8]);
            let current = crate::lowering_memo::key_recipe::CurrentKey::new(&frontend, row.body(), 91, false, false).unwrap();
            let prepared = crate::lowering_memo::key_recipe::CurrentKey::from_prepared(&frontend, row, 91, false, false).unwrap();
            assert_eq!(current.materialize(&tail), prepared.materialize(&tail));
        }
    }
}

#[test]
fn prepared_roster_declines_foreign_issuer_and_public_body_roster_replacement() {
    let source = "/proc/p()\n    return 1\n";
    let frontend = frontend(source);
    let independent = self::frontend(source);
    let roster = PreparedBodyRoster::issue(&frontend)
        .ok()
        .expect("current roster");
    let row = roster.ordered().next().unwrap();
    assert!(!roster.authenticates(&independent));
    assert!(crate::lowering_memo::key_recipe::CurrentKey::from_prepared(
        &independent,
        row,
        1,
        false,
        false
    )
    .is_none());
    // Exact copied descriptors may be rebound; the receipt remains current.
    let rebound = roster.selected(&independent.bodies[0]).unwrap();
    assert!(std::ptr::eq(rebound.body(), &frontend.bodies[0]));
    let mut changed = self::frontend(source);
    changed.bodies = Arc::from(changed.bodies.to_vec());
    assert!(PreparedBodyRoster::issue(&changed).is_err());
    let mut descriptor = frontend.bodies[0].clone();
    descriptor.expanded_span.start += 1;
    assert!(roster.selected(&descriptor).is_none());
}

#[test]
fn completed_prepared_roster_matches_fresh_code_and_retains_selected_duplicate_rejection() {
    let frontend = frontend("/proc/p()\n    return 1\n/proc/q()\n    return 2\n");
    let roster = PreparedBodyRoster::issue(&frontend)
        .ok()
        .expect("current roster");
    let executor = dm_exec::BuildExecutor::new(2).unwrap();
    let complete = |input: CompletedInput| -> Result<Vec<u8>, String> {
        Ok(serde_json::to_vec(&input.into_lowered().code.procedure).unwrap())
    };
    let run = |prepared| {
        let arena = dm_tree::frontend::BodyArena::new(&frontend);
        let execution = LoweringExecution::new(&executor, &arena);
        let execution = if prepared {
            execution.with_prepared_roster(&roster)
        } else {
            execution
        };
        lower_frontend_completed_input_on_execution(
            &frontend,
            frontend.snapshot.tree.as_ref(),
            &LocalPolicy,
            Default::default(),
            None,
            None,
            execution,
            false,
            &complete,
        )
    };
    let fresh = run(false);
    let prepared = run(true);
    assert!(fresh.diagnostics.is_empty());
    assert!(prepared.diagnostics.is_empty());
    assert_eq!(prepared.units.len(), 2);
    for (a, b) in fresh.units.iter().zip(&prepared.units) {
        assert_eq!(
            (a.identity, a.effective, &a.value),
            (b.identity, b.effective, &b.value)
        );
    }
    let arena = dm_tree::frontend::BodyArena::new(&frontend);
    let selected = [&frontend.bodies[0], &frontend.bodies[0]];
    let duplicate = lower_frontend_completed_input_on_execution(
        &frontend,
        frontend.snapshot.tree.as_ref(),
        &LocalPolicy,
        Default::default(),
        None,
        None,
        LoweringExecution::new(&executor, &arena)
            .with_prepared_roster(&roster)
            .with_selected_bodies(&selected),
        false,
        &complete,
    );
    assert!(duplicate.units.is_empty());
    assert!(duplicate
        .diagnostics
        .iter()
        .any(|error| error.message.contains("unique current body issuance")));
}
