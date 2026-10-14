use super::*;
use dm_syntax::BindingValue;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Inputs(&'static str);
impl dm_preprocess::SourceProvider for Inputs {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
#[test]
fn arguments_branch_locals_loop_and_catch_bindings_use_current_issued_scopes() {
    let frontend = build(Path::new("project.dme"), &Inputs(
        "/datum/x/proc/read(x)\n    var/y = x\n    if(x)\n        var/x = 2\n        y = x\n    else\n        var/x = 3\n        y = x\n    for(var/i = 0; i < 2; i++)\n        y = i\n    try\n        y = x\n    catch(var/e)\n        y = e\n    return x\n"), &Default::default(),1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let result = analyze(&frontend, body, None).unwrap();
            assert!(result.diagnostics.is_empty(), "{:?}", result.diagnostics);
            assert!(result.gaps.is_empty(), "{:?}", result.gaps);
            let ids = |name: &str| {
                result
                    .references
                    .iter()
                    .filter(|reference| reference.name.as_ref() == name)
                    .map(|reference| match &reference.binding {
                        ReferenceBinding::Lexical(id) => *id,
                        ReferenceBinding::RequiresSemanticResolver => {
                            panic!("unexpected nonlocal {name}")
                        }
                    })
                    .collect::<Vec<_>>()
            };
            let x = ids("x");
            assert_eq!(x.len(), 6);
            assert_eq!(x[0], x[1]);
            assert_eq!(x[0], x[4]);
            assert_eq!(x[0], x[5]);
            assert_ne!(x[2], x[0]);
            assert_ne!(x[3], x[0]);
            assert_ne!(x[2], x[3]);
            assert!(matches!(
                result.scopes.binding(x[0]).unwrap().value,
                BindingValue::Parameter { ordinal: 0 }
            ));
            let i = ids("i");
            assert!(i.len() >= 3);
            assert!(i.iter().all(|id| *id == i[0]));
            assert_eq!(ids("e").len(), 1);
            assert!(std::ptr::eq(result.occurrence, body.occurrence()));
            assert_eq!(result.scopes.scope_depth(), 0);
            let mut exported = Vec::new();
            let count = jsonl::write_jsonl(&result, &mut exported).unwrap();
            let rows = std::str::from_utf8(&exported)
                .unwrap()
                .lines()
                .map(|line| serde_json::from_str::<serde_json::Value>(line).unwrap())
                .collect::<Vec<_>>();
            assert_eq!(count, rows.len());
            assert_eq!(rows[0]["meaning"]["kind"], "argument");
            assert_eq!(rows[0]["name"], "x");
            assert_eq!(rows.last().unwrap()["semantic_resolution_complete"], false);
            assert_eq!(
                rows.iter()
                    .filter(|row| row["row"] == "identifier_reference")
                    .count(),
                result.references.len()
            );
        })
        .unwrap();
}
#[test]
fn named_call_labels_are_not_fabricated_local_reads_and_foreign_issuance_is_rejected() {
    let inputs = Inputs("/datum/x/proc/read(x)\n    return f(x = x)\n");
    let frontend = build(Path::new("project.dme"), &inputs, &Default::default(), 1).unwrap();
    let foreign = build(Path::new("project.dme"), &inputs, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let model = analyze(&frontend, body, None).unwrap();
            assert!(model.references.is_empty());
            assert_eq!(model.gaps.len(), 1);
            assert!(matches!(
                analyze(&foreign, body, None),
                Err(BindingError::Issuance(_))
            ));
        })
        .unwrap();
}

#[test]
fn member_calls_bind_receivers_and_values_but_not_selectors_named_labels_or_arglist_names() {
    let inputs=Inputs("/datum/x/proc/read(holder, key, value)\n    holder.run(key = value, key)\n    global.run(key = value)\n    holder.run(arglist(value))\n    return holder.child\n");
    let frontend = build(Path::new("project.dme"), &inputs, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let model = analyze(&frontend, body, None).unwrap();
            assert!(model.diagnostics.is_empty(), "{:?}", model.diagnostics);
            assert!(model.gaps.is_empty(), "{:?}", model.gaps);
            let count = |name: &str| {
                model
                    .references
                    .iter()
                    .filter(|reference| reference.name.as_ref() == name)
                    .count()
            };
            assert_eq!(count("holder"), 3);
            assert_eq!(count("value"), 3);
            assert_eq!(count("key"), 1);
            assert_eq!(count("global"), 0);
            assert_eq!(count("run"), 0);
            assert_eq!(count("arglist"), 0);
            assert!(model
                .references
                .iter()
                .all(|reference| matches!(reference.binding, ReferenceBinding::Lexical(_))));
            assert_eq!(model.selectors.len(), 4);
            assert_eq!(model.selectors[0].kind, SelectorKind::Procedure);
            assert_eq!(model.selectors[1].kind, SelectorKind::GlobalProcedure);
            assert!(model.selectors[1].receiver_path.is_none());
            assert_eq!(model.selectors[3].kind, SelectorKind::Field);
        })
        .unwrap();
}

#[test]
fn assignment_and_update_targets_keep_variable_roles_and_global_arglist_stays_a_gap() {
    let inputs=Inputs("#undef TRUE\n/datum/x/proc/read(TRUE, x)\n    TRUE = x\n    TRUE++\n    x += TRUE\n    global.run(arglist(x))\n    return TRUE\n");
    let frontend = build(Path::new("project.dme"), &inputs, &Default::default(), 1).unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let model = analyze(&frontend, body, None).unwrap();
            assert!(model.diagnostics.is_empty(), "{:?}", model.diagnostics);
            let named = |name: &str| {
                model
                    .references
                    .iter()
                    .filter(|reference| reference.name.as_ref() == name)
                    .collect::<Vec<_>>()
            };
            let truth = named("TRUE");
            assert_eq!(
                truth.len(),
                2,
                "value TRUE is a literal; assignment/update TRUE is a variable"
            );
            assert_eq!(truth[0].access, ReferenceAccess::Write);
            assert_eq!(truth[1].access, ReferenceAccess::ReadWrite);
            let x = named("x");
            assert_eq!(x.len(), 2);
            assert_eq!(x[0].access, ReferenceAccess::Read);
            assert_eq!(x[1].access, ReferenceAccess::ReadWrite);
            assert_eq!(model.gaps.len(), 1);
            assert!(model.gaps[0].reason.contains("named-call"));
            assert_eq!(
                model.selectors.last().unwrap().kind,
                SelectorKind::NamedProcedure
            );
            assert_eq!(model.selectors.last().unwrap().selector.as_ref(), "arglist");
        })
        .unwrap();
}
