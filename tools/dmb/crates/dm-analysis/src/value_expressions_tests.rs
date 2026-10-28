use super::*;
use crate::value_equations;
use dm_ir::{ProcedureIdentity, ResolveQuery, ResolvedMeaning, Resolver, SymbolId};
use dm_tree::{
    frontend::{build, BodyArena, ColdFrontend},
    MemberKind,
};
use std::{collections::BTreeMap, path::Path};

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

// This corpus uses global calls only. The production host must additionally
// supply override dispatch, mutable fields, arguments and escape barriers.
struct Globals<'a>(&'a ColdFrontend);
impl ValueHost<ProcedureIdentity> for Globals<'_> {
    type Error = String;
    fn read(&self, _: &Expr) -> Result<Equation<ProcedureIdentity>, String> {
        Ok(constant(false))
    }
    fn call(&self, expression: &Expr) -> Result<Equation<ProcedureIdentity>, String> {
        let ExprKind::Call { callee, .. } = &expression.kind else {
            unreachable!()
        };
        if matches!(&callee.kind, ExprKind::Unary { op, .. } if op == "new") {
            return Ok(constant(false));
        }
        let ExprKind::Ident(name) = &callee.kind else {
            return Err("corpus requires global call selection".into());
        };
        let tree = &self.0.snapshot.tree;
        let query = ResolveQuery::GlobalProc(SymbolId::of(name));
        let ResolvedMeaning::Member { owner, name, .. } = Resolver::resolve(tree.as_ref(), query)
        else {
            return Err("native call selection is incomplete".into());
        };
        let member = tree
            .resolve(tree.lookup_type(owner).unwrap(), name, MemberKind::Proc)
            .unwrap();
        let identity = self
            .0
            .callable_roster()
            .unwrap()
            .identity_for_member(member)
            .unwrap();
        Ok(Equation {
            admissible: true,
            requires: BTreeSet::from([identity]),
        })
    }
}

fn equations(source: &'static str) -> BTreeMap<ProcedureIdentity, Equation<ProcedureIdentity>> {
    let frontend = build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let host = Globals(&frontend);
    let roster = frontend.callable_roster().unwrap();
    frontend
        .bodies
        .iter()
        .enumerate()
        .map(|(ordinal, occurrence)| {
            let proof = arena
                .with_parsed(occurrence, |body| {
                    returns(body.statement_body().unwrap(), &host).unwrap()
                })
                .unwrap();
            (roster.identity(ordinal).unwrap(), proof)
        })
        .collect()
}

#[test]
fn actual_native_call_identities_form_recursive_value_components() {
    let facts = equations("/proc/a()\n    return b()\n/proc/b()\n    return a()\n");
    let solution = value_equations::solve(&facts).unwrap();
    assert_eq!(solution.components.len(), 1);
    assert_eq!(solution.components[0].len(), 2);
    assert!(solution.values.values().all(|value| *value));
}

#[test]
fn entity_exit_then_scalar_repair_retracts_the_old_native_summary() {
    let bad = equations("/proc/a()\n    return b()\n/proc/b()\n    return new /datum\n");
    assert!(value_equations::solve(&bad)
        .unwrap()
        .values
        .values()
        .all(|value| !*value));
    let repaired = equations("/proc/a()\n    return b()\n/proc/b()\n    return 1\n");
    assert!(value_equations::solve(&repaired)
        .unwrap()
        .values
        .values()
        .all(|value| *value));
}

#[test]
fn operand_returning_operators_differ_from_arithmetic_and_result_writes() {
    let arithmetic = equations("/proc/a()\n    return value + 1\n");
    assert!(value_equations::solve(&arithmetic)
        .unwrap()
        .values
        .values()
        .all(|value| *value));
    for source in [
        "/proc/a()\n    return value || 1\n",
        "/proc/a()\n    . = new /datum\n    return\n",
    ] {
        assert!(value_equations::solve(&equations(source))
            .unwrap()
            .values
            .values()
            .all(|value| !*value));
    }
}

#[test]
fn unsupported_native_syntax_cannot_produce_a_clean_proof() {
    let frontend = build(
        Path::new("project.dme"),
        &Source("/proc/a()\n    return (\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            assert!(!body.statement_body().unwrap().syntax_complete());
            assert!(crate::checks::BodyView::new(&frontend, body).is_err());
            assert_eq!(
                returns(body.statement_body().unwrap(), &Globals(&frontend)),
                Err(ProofError::UnsupportedSyntax),
                "native parse: {:?}; raw: {:?}",
                body.statement_body().unwrap().parsed(),
                body.item()
            );
        })
        .unwrap();
}
