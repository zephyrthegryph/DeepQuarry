use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}

fn facts(source: &'static str) -> Vec<(String, Rule)> {
    let frontend = build(
        Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let arena = BodyArena::new_typed(&frontend, |_| true);
    let mut result = Vec::new();
    for occurrence in frontend.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| {
                for fact in
                    contributions(&frontend, body, frontend.snapshot.tree.as_ref(), &[]).unwrap()
                {
                    result.push((
                        frontend
                            .snapshot
                            .tree
                            .symbols()
                            .text(fact.name)
                            .unwrap()
                            .into(),
                        fact.rule,
                    ));
                }
            })
            .unwrap();
    }
    result
}

#[test]
fn native_parameters_fields_and_new_contribute_but_locals_and_typed_slots_do_not() {
    let result = facts("/datum/example\n    var/untyped\n    var/datum/typed\n    proc/test(datum/arg)\n        untyped = arg\n        typed = arg\n        var/shadow\n        shadow = new /datum\n");
    assert_eq!(result, [("untyped".into(), Rule::Typed)]);
}

#[test]
fn groups_globals_and_static_local_shadowing_preserve_binding() {
    let result = facts("var/saved\n/datum/example\n    var/shadow\n    proc/test()\n        var/static/shadow\n        shadow = new /datum\n        global.saved = (new /datum)\n");
    assert_eq!(result, [("saved".into(), Rule::Typed)]);
}

#[test]
fn scalar_literals_and_lists_are_not_reference_assignments() {
    assert!(facts("/datum/example\n    var/a\n    proc/test()\n        a = 1\n        a = \"value\"\n        a = list()\n").is_empty());
}

#[test]
fn typed_assignment_dominates_unknown_call_without_losing_first_evidence() {
    let result = facts("/datum/example\n    var/a\n    proc/unknown()\n        return null\n    proc/test(datum/arg)\n        a = unknown()\n        a = arg\n");
    assert_eq!(result, [("a".into(), Rule::Typed)]);
}

#[test]
fn call_named_like_a_scalar_builtin_is_not_a_scalar_proof() {
    let result = facts("/datum/example\n    var/a\n    proc/rand()\n        return new /datum\n    proc/test()\n        a = rand()\n");
    assert_eq!(result, [("a".into(), Rule::Call)]);
}

#[test]
fn loop_bindings_preserve_an_existing_parameter_type_like_the_reference() {
    let result = facts("/datum/example\n    var/saved\n    proc/test(datum/value)\n        for(var/value in list())\n            saved = value\n");
    assert_eq!(result, [("saved".into(), Rule::Typed)]);
}
