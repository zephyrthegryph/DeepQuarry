use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}

fn observe(body: &str) -> Result<(Vec<ConditionKind>, ControlFlow), String> {
    let frontend = build(
        Path::new("flow.dme"),
        &Source(format!("/proc/probe(a,b)\n{body}")),
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body)?;
            let result = analyze(&view)?;
            let kinds = result
                .events
                .iter()
                .filter_map(|event| match event {
                    Event::ControlCondition { kind, .. } => Some(*kind),
                    _ => None,
                })
                .collect();
            Ok((kinds, result.flow))
        })
        .map_err(|e| e.message)?
}
fn expression_truth(expression: &str) -> Result<Option<bool>, String> {
    let frontend = build(
        Path::new("truth.dme"),
        &Source(format!("/proc/probe(a)\n    return {expression}\n")),
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body)?;
            let StatementKind::Return(Some(value)) = &view.syntax().parsed().statements[0].kind
            else {
                unreachable!()
            };
            truthy(value)
        })
        .map_err(|e| e.message)?
}

#[test]
fn terminating_siblings_are_skipped_but_branch_arms_are_not_pruned() {
    assert_eq!(
        observe("    return\n    if(1)\n        a=1\n").unwrap().0,
        []
    );
    assert_eq!(observe("    if(a)\n        return\n    else\n        return\n    switch(1)\n        if(0)\n            a=1\n").unwrap().0,[ConditionKind::If]);
    assert_eq!(observe("    if(0)\n        switch(1)\n            if(0)\n                a=1\n    else\n        a=2\n").unwrap().0,[ConditionKind::If,ConditionKind::Switch]);
}

#[test]
fn ordinary_loop_returns_are_cleared_but_do_return_propagates() {
    let after = "    switch(1)\n        if(0)\n            a=1\n";
    assert_eq!(
        observe(&format!("    while(a)\n        return\n{after}"))
            .unwrap()
            .0,
        [ConditionKind::Switch]
    );
    assert_eq!(
        observe(&format!("    do\n        return\n    while(a)\n{after}"))
            .unwrap()
            .0,
        []
    );
    assert_eq!(
        observe(&format!("    for(var/i=1 to 1)\n        return\n{after}"))
            .unwrap()
            .0,
        []
    );
    assert_eq!(
        observe(&format!("    for(var/i=0 to 0)\n        return\n{after}"))
            .unwrap()
            .0,
        [ConditionKind::Switch]
    );
}

#[test]
fn pinned_throw_label_spawn_and_fuzzy_break_behavior_is_retained() {
    let after = "    switch(1)\n        if(0)\n            a=1\n";
    for prefix in [
        "    throw a\n",
        "    label:\n        return\n",
        "    spawn(0)\n        return\n",
    ] {
        assert_eq!(
            observe(&format!("{prefix}{after}")).unwrap().0,
            [ConditionKind::Switch],
            "{prefix}"
        );
    }
    assert_eq!(
        observe("    while(a)\n        break\n        if(1)\n            a=2\n")
            .unwrap()
            .0,
        [ConditionKind::If]
    );
    assert!(observe(&format!("    CRASH()\n{after}"))
        .unwrap()
        .0
        .is_empty());
}

#[test]
fn elseif_chain_preserves_condition_then_body_interleaving() {
    assert_eq!(observe("    if(a)\n        switch(1)\n            if(0)\n                a=1\n    else if(b)\n        switch(2)\n            if(0)\n                a=2\n").unwrap().0,[ConditionKind::If,ConditionKind::Switch,ConditionKind::If,ConditionKind::Switch]);
    assert_eq!(
        observe("    for(var/i=0,1,i++)\n        a=1\n").unwrap().0,
        [ConditionKind::ForTest]
    );
}

#[test]
fn truthiness_is_syntactic_and_does_not_fold_or_short_circuit() {
    for (expression, expected) in [
        ("0", false),
        ("1.0", true),
        ("0e0", false),
        ("null", false),
        ("\"\"", false),
        ("\"text\"", true),
        ("/datum", true),
        ("list()", true),
        ("new /datum", true),
        ("!0", true),
        ("(0)", false),
        ("a=1", true),
    ] {
        assert_eq!(
            expression_truth(expression).unwrap(),
            Some(expected),
            "{expression}"
        );
    }
    for expression in ["0 && a", "1 || a", "1 == 1", "-1", "a=!0", "a"] {
        assert_eq!(expression_truth(expression).unwrap(), None, "{expression}");
    }
    assert_eq!(expression_truth("1 ? 0 : 1").unwrap(), Some(false));
}

#[test]
fn unresolved_interpolation_or_checker_settings_do_not_become_clean_proofs() {
    assert_eq!(expression_truth("\"prefix [a]\"").unwrap(), Some(true));
    assert_eq!(
        observe("    if(\"[a]\")\n        a=1\n").unwrap().0,
        [ConditionKind::If]
    );
    // Checker annotations survive shared parsing; Compile rejects them separately.
    assert!(observe("    set SpacemanDMM_should_be_pure=1\n").is_ok());
}

#[test]
fn constructor_terms_and_later_follows_use_the_primary_ast_boundary() {
    for expression in ["new /datum().foo()", "new /datum()()", "new /datum()[1]"] {
        assert_eq!(expression_truth(expression).unwrap(), None, "{expression}");
    }
    for expression in ["new /datum()", "new a()", "new a.b()", "new a.b", "alist()"] {
        assert_eq!(
            expression_truth(expression).unwrap(),
            Some(true),
            "{expression}"
        );
    }
}

#[test]
fn primary_lexical_metadata_preserves_pinned_escape_and_interpolation_truthiness() {
    for expression in [r#""\ ""#, r#""\n""#, r#""prefix[a]""#, r#""\ []""#] {
        assert_eq!(
            expression_truth(expression).unwrap(),
            Some(true),
            "{expression}"
        );
    }
    for expression in [r#""[]""#, r#""[ ]""#, r#""[a]""#] {
        assert_eq!(expression_truth(expression).unwrap(), None, "{expression}");
    }
    assert_eq!(expression_truth("\"\\\n\"").unwrap(), Some(false));
    assert_eq!(expression_truth("\"\\\n \t\n \t\n\"").unwrap(), Some(true));
}

#[test]
fn try_goto_and_range_step_quirks_preserve_following_condition_visits() {
    let after = "    if(a)\n        return\n";
    for prefix in [
        "    goto done\n",
        "    try\n        return\n    catch\n        return\n",
        "    for(var/i=2 to 1 step a)\n        return\n",
    ] {
        assert_eq!(
            observe(&format!("{prefix}{after}")).unwrap().0,
            [ConditionKind::If],
            "{prefix}"
        );
    }
    // Pinned valid_for_range treats an integer step or non-term expression
    // as sufficient validity, even for reversed endpoints.
    for step in ["1", "a+1"] {
        assert!(observe(&format!(
            "    for(var/i=2 to 1 step {step})\n        return\n{after}"
        ))
        .unwrap()
        .0
        .is_empty());
    }
    assert_eq!(
        observe(&format!(
            "    for(var/i=0 to 0 step 1)\n        return\n{after}"
        ))
        .unwrap()
        .0,
        [ConditionKind::If]
    );
}

#[test]
fn original_cr_segments_are_distinct_from_runtime_cooked_templates() {
    for expression in ["\"\r\"", "@{\"\r\"}", "\"\\\r\n\n\"", "\"\r[a]\""] {
        assert_eq!(
            expression_truth(expression).unwrap(),
            Some(true),
            "{expression:?}"
        );
    }
    for expression in ["\"\\\r\n\"", "\"\\\n\n\""] {
        assert_eq!(
            expression_truth(expression).unwrap(),
            Some(false),
            "{expression:?}"
        );
    }
    assert_eq!(expression_truth("\"[a\r]\"").unwrap(), None);
    assert!(expression_truth("\"\\\r[a]\"").is_err());
}
