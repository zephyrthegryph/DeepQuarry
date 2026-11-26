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
