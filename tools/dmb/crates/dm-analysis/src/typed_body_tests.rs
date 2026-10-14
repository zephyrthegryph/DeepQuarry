use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        // Lossless declaration parsing permits an unknown nested block, while
        // the typed body parser diagnoses it and retains an Unsupported node.
        Ok("/datum/x/proc/read()\n    unknown_block\n        return 1\n".into())
    }
}
#[test]
fn recovering_nodes_report_current_issued_diagnostics_without_another_parse() {
    let frontend = build(Path::new("project.dme"), &Source, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| false);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            struct Visitor;
            impl TypedVisitor for Visitor {}
            let typed = body.statement_body().unwrap();
            let expected = typed.parsed();
            assert!(!expected.diagnostics.is_empty());
            assert_eq!(
                expected.diagnostics[0].message,
                "unsupported statement block"
            );
            let result = visit(body, &mut Visitor).unwrap();
            assert!(std::ptr::eq(result.occurrence, body.occurrence()));
            assert!(std::ptr::eq(
                result.diagnostics,
                expected.diagnostics.as_slice()
            ));
            assert_eq!(result.report.unsupported_statements, 1);
            let mut bytes = Vec::new();
            let exported = crate::typed_body_jsonl::write_jsonl(body, &mut bytes).unwrap();
            assert_eq!(exported, result.report);
            let rows: Vec<serde_json::Value> = std::str::from_utf8(&bytes)
                .unwrap()
                .lines()
                .map(|line| serde_json::from_str(line).unwrap())
                .collect();
            let summary = rows.last().unwrap();
            assert_eq!(
                summary["diagnostics"][0]["message"],
                expected.diagnostics[0].message
            );
            assert_eq!(summary["declaration"], body.occurrence().declaration.0);
            assert_eq!(summary["unsupported_statements"], 1);
        })
        .unwrap();
}
#[test]
fn raw_issued_body_does_not_trigger_hidden_typed_parsing_or_partial_output() {
    let frontend = build(Path::new("project.dme"), &Source, &Default::default(), 1).unwrap();
    let body = frontend.parse_body(&frontend.bodies[0]).unwrap();
    let mut bytes = Vec::new();
    assert!(matches!(
        crate::typed_body_jsonl::write_jsonl(&body, &mut bytes),
        Err(crate::typed_body_jsonl::ExportError::NoTypedModel(_))
    ));
    assert!(bytes.is_empty());
    assert!(!body.statement_attempted());
}

#[test]
fn caller_selected_reference_queries_keep_negative_answers_and_current_node_subjects() {
    struct Inputs;
    impl dm_preprocess::SourceProvider for Inputs {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/x/proc/read()\n    return absent\n".into())
        }
    }
    struct Host;
    impl dm_ir::Resolver for Host {
        fn resolve(&self, query: dm_ir::ResolveQuery) -> dm_ir::ResolvedMeaning {
            match query {
                dm_ir::ResolveQuery::Var { .. } => dm_ir::ResolvedMeaning::Missing,
                _ => dm_ir::ResolvedMeaning::Unsupported(query),
            }
        }
    }
    let frontend = build(Path::new("project.dme"), &Inputs, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let query = dm_ir::ResolveQuery::Var {
                owner: dm_ir::SymbolId::of("/datum/x"),
                name: dm_ir::SymbolId::of("absent"),
            };
            let mut bytes = Vec::new();
            let count = queries::write_jsonl(
                body,
                frontend.snapshot.tree.symbols(),
                &Host,
                |node, path| {
                    assert_eq!(
                        path,
                        [
                            dm_syntax::NodeStep::Statement(0),
                            dm_syntax::NodeStep::Expression(0)
                        ]
                    );
                    assert!(
                        matches!(&node.kind, dm_syntax::ExprKind::Ident(name) if name == "absent")
                    );
                    [query]
                },
                &mut bytes,
            )
            .unwrap();
            assert_eq!(count, 1);
            let row: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
            assert_eq!(row["answer"]["status"], "missing");
            assert_eq!(row["schema"], "dm-resolved-query-v1");
            assert!(row["subject"]
                .as_str()
                .unwrap()
                .starts_with("body-occurrence:"));
            assert_eq!(
                serde_json::from_str::<dm_ir::ResolveQuery>(row["query_wire"].as_str().unwrap())
                    .unwrap(),
                query
            );
            let mut syntax = Vec::new();
            crate::typed_body_jsonl::write_jsonl(body, &mut syntax).unwrap();
            let expression: serde_json::Value = std::str::from_utf8(&syntax)
                .unwrap()
                .lines()
                .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
                .find(|row| row["row"] == "expression")
                .unwrap();
            assert_eq!(expression["syntax"]["name"], "absent");
        })
        .unwrap();
}
