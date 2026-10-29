use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Inputs(&'static str);
impl dm_preprocess::SourceProvider for Inputs {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn selected_facts_bind_current_spans_and_reject_foreign_or_mismatched_nodes_before_output() {
    let first = build(
        Path::new("project.dme"),
        &Inputs("/proc/read(x)\n    return x\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let shifted = build(
        Path::new("project.dme"),
        &Inputs("// shifted source\n/proc/read(x)\n    return x\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let facts = SelectedReferences {
        references: vec![dm_ir::SelectedReference {
            path: vec![NodeStep::Statement(0), NodeStep::Expression(0)],
            name: SymbolId::of("x"),
            meaning: SelectedMeaning::Argument(0),
            relative_span: None,
        }],
        complete: false,
        unbound_selections: 0,
    };
    let export = |frontend: &ColdFrontend| {
        let arena = BodyArena::new_typed(frontend, |_| true);
        arena
            .with_parsed(&frontend.bodies[0], |body| {
                let mut output = Vec::new();
                assert_eq!(write_jsonl(frontend, body, &facts, &mut output).unwrap(), 1);
                serde_json::from_slice::<serde_json::Value>(
                    output.split(|byte| *byte == b'\n').next().unwrap(),
                )
                .unwrap()
            })
            .unwrap()
    };
    let a = export(&first);
    let b = export(&shifted);
    assert_eq!(a["path"], b["path"]);
    assert_eq!(a["meaning"], b["meaning"]);
    assert!(b["start"].as_u64().unwrap() > a["start"].as_u64().unwrap());
    let arena = BodyArena::new_typed(&first, |_| true);
    arena
        .with_parsed(&first.bodies[0], |body| {
            let mut output = Vec::new();
            assert!(write_jsonl(&shifted, body, &facts, &mut output).is_err());
            assert!(output.is_empty());
            let mut invalid = facts.clone();
            let mut bad = invalid.references[0].clone();
            bad.name = SymbolId::of("different");
            invalid.references.push(bad);
            assert!(write_jsonl(&first, body, &invalid, &mut output).is_err());
            assert!(output.is_empty(), "validation must precede all row writes");
            let mut wrong_role = facts.clone();
            wrong_role.references[0].meaning = SelectedMeaning::RuntimeProperty {
                name: SymbolId::of("x"),
                static_property: false,
                safe: false,
            };
            assert!(write_jsonl(&first, body, &wrong_role, &mut output).is_err());
            assert!(
                output.is_empty(),
                "matching name alone cannot license a property on an identifier"
            );
        })
        .unwrap();
}

#[test]
fn explicit_global_call_selection_binds_actual_compiler_fact_and_root_namespace() {
    const SOURCE: &str = "/datum/proc/read()\n    return ::chosen()\n/proc/chosen()\n    return 1\n/datum/proc/chosen()\n    return 100\n";
    let frontend = build(
        Path::new("project.dme"),
        &Inputs(SOURCE),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let statements = body.statement_body().unwrap();
            let (_, mut facts) =
                dm_codegen_byond::compile_statement_view_with_resolver_and_references(
                    dm_syntax::StatementView::all(&statements.parsed().statements),
                    &dm_codegen_byond::ProcedureInputs {
                        current_type_path: Some("/datum".into()),
                        ..Default::default()
                    },
                    frontend.snapshot.tree.symbols(),
                    frontend.snapshot.tree.as_ref(),
                    None,
                )
                .unwrap();
            assert_eq!(facts.unbound_selections, 0);
            let index = facts
                .references
                .iter()
                .position(|reference| reference.name == SymbolId::of("chosen"))
                .unwrap();
            assert!(
                matches!(facts.references[index].meaning, SelectedMeaning::ProcedureCall {
            reference: dm_ir::SymRef::Proc { owner, .. }, safe: false,
        } if owner == SymbolId::of("/"))
            );
            let mut output = Vec::new();
            assert_eq!(
                write_jsonl(&frontend, body, &facts, &mut output).unwrap(),
                facts.references.len()
            );
            let row = output
                .split(|byte| *byte == b'\n')
                .filter(|line| !line.is_empty())
                .map(|line| serde_json::from_slice::<serde_json::Value>(line).unwrap())
                .find(|row| row["name"] == "chosen")
                .unwrap();
            let start = SOURCE.find("::chosen").unwrap();
            assert_eq!(row["start"], start);
            assert_eq!(
                row["end"],
                start + "::chosen".len(),
                "compiler and exporter anchor the whole primary callee"
            );
            for meaning in [
                SelectedMeaning::ProcedureCall {
                    reference: dm_ir::SymRef::Proc {
                        owner: SymbolId::of("/datum"),
                        name: SymbolId::of("chosen"),
                        occurrence: 0,
                    },
                    safe: false,
                },
                SelectedMeaning::ProcedureCall {
                    reference: dm_ir::SymRef::Verb {
                        owner: SymbolId::of("/"),
                        name: SymbolId::of("chosen"),
                        occurrence: 0,
                    },
                    safe: false,
                },
                SelectedMeaning::Argument(0),
            ] {
                facts.references[index].meaning = meaning;
                output.clear();
                assert!(write_jsonl(&frontend, body, &facts, &mut output).is_err());
                assert!(output.is_empty());
            }
        })
        .unwrap();
}

#[test]
fn explicit_global_builtin_selection_binds_actual_intrinsic_without_proc_identity() {
    for source in [
        "/datum/proc/read()\n    return ::abs(-2)\n/datum/proc/abs(n)\n    return n + 100\n",
        "/datum/proc/read()\n    return global.abs(-2)\n/datum/proc/abs(n)\n    return n + 100\n",
    ] {
        let frontend = build(
            Path::new("project.dme"),
            &Inputs(source),
            &Default::default(),
            1,
        )
        .unwrap();
        let global = dm_ir::ResolveQuery::GlobalProc(SymbolId::of("abs"));
        assert!(
            matches!(
                dm_ir::Resolver::resolve(frontend.snapshot.tree.as_ref(), global),
                dm_ir::ResolvedMeaning::Unsupported(_)
            ),
            "source-only tree must not invent executable builtin absence"
        );
        assert_eq!(
            dm_ir::Resolver::resolve(
                frontend.snapshot.tree.as_ref(),
                dm_ir::ResolveQuery::SourceDeclarationChain {
                    owner: SymbolId::of("/"),
                    name: SymbolId::of("abs"),
                    verb: false,
                }
            ),
            dm_ir::ResolvedMeaning::Missing,
            "authored source absence is a distinct genuine fact"
        );
        let arena = BodyArena::new_typed(&frontend, |_| true);
        arena
            .with_parsed(&frontend.bodies[0], |body| {
                let statements = body.statement_body().unwrap();
                let (_, mut facts) =
                    dm_codegen_byond::compile_statement_view_with_resolver_and_references(
                        dm_syntax::StatementView::all(&statements.parsed().statements),
                        &dm_codegen_byond::ProcedureInputs {
                            current_type_path: Some("/datum".into()),
                            ..Default::default()
                        },
                        frontend.snapshot.tree.symbols(),
                        frontend.snapshot.tree.as_ref(),
                        None,
                    )
                    .unwrap();
                assert!(facts.references.iter().any(|reference| reference.meaning
                    == SelectedMeaning::IntrinsicCall(SymbolId::of("abs"))));
                let mut output = Vec::new();
                assert_eq!(
                    write_jsonl(&frontend, body, &facts, &mut output).unwrap(),
                    facts.references.len()
                );
                let selected = facts
                    .references
                    .iter_mut()
                    .find(|reference| {
                        reference.meaning == SelectedMeaning::IntrinsicCall(SymbolId::of("abs"))
                    })
                    .unwrap();
                selected.meaning = SelectedMeaning::IntrinsicCall(SymbolId::of("length"));
                output.clear();
                assert!(write_jsonl(&frontend, body, &facts, &mut output).is_err());
                assert!(
                    output.is_empty(),
                    "same callee spelling cannot license another intrinsic selector"
                );
            })
            .unwrap();
    }
}

#[test]
fn actual_global_variable_member_selection_is_not_a_procedure_callee() {
    let frontend = build(
        Path::new("project.dme"),
        &Inputs("var/shared = 1\n/proc/read()\n    return global.shared\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let statements = body.statement_body().unwrap();
            let (_, facts) = dm_codegen_byond::compile_statement_view_with_resolver_and_references(
                dm_syntax::StatementView::all(&statements.parsed().statements),
                &dm_codegen_byond::ProcedureInputs::default(),
                frontend.snapshot.tree.symbols(),
                frontend.snapshot.tree.as_ref(),
                None,
            )
            .unwrap();
            assert!(facts
                .references
                .iter()
                .any(|reference| reference.name == SymbolId::of("shared")
                    && matches!(reference.meaning, SelectedMeaning::SharedStorage(_))));
            let mut output = Vec::new();
            assert_eq!(
                write_jsonl(&frontend, body, &facts, &mut output).unwrap(),
                facts.references.len()
            );
        })
        .unwrap();
}

#[test]
fn source_only_unknown_global_namespace_stays_unsupported() {
    let frontend = build(
        Path::new("project.dme"),
        &Inputs("/datum/proc/read()\n    return ::unreviewed_missing()\n"),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let statements = body.statement_body().unwrap();
            let errors = dm_codegen_byond::compile_statement_view_with_resolver_and_references(
                dm_syntax::StatementView::all(&statements.parsed().statements),
                &dm_codegen_byond::ProcedureInputs {
                    current_type_path: Some("/datum".into()),
                    ..Default::default()
                },
                frontend.snapshot.tree.symbols(),
                frontend.snapshot.tree.as_ref(),
                None,
            )
            .err()
            .expect("unknown executable namespace must not become clean or source absence");
            assert!(errors
                .iter()
                .any(|error| error.reason.contains("unsupported semantic query")));
            assert!(errors
                .iter()
                .all(|error| error.kind != dm_codegen_byond::LowerErrorKind::SourceError));
        })
        .unwrap();
}
