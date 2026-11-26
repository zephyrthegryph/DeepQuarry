use super::*;
struct Source(&'static str);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn build(state: &mut RetainedSemanticTree, text: &'static str) -> ColdFrontend {
    let executor = dm_exec::BuildExecutor::new(1).unwrap();
    build_with_executor_and_semantic_state(
        Path::new("settings.dme"),
        &Source(text),
        &BTreeMap::new(),
        FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
        None,
        &executor,
        Some(state),
    )
    .unwrap()
}
#[test]
fn parser_settings_receipts_bind_current_nodes_and_decline_foreign_or_changed_settings() {
    let mut state = RetainedSemanticTree::default();
    let before = build(
        &mut state,
        "/datum/example/proc/read()\n    if(1)\n        set waitfor = 0\n    return 1\n",
    );
    let current = build(
        &mut state,
        "// shift\n/datum/example/proc/read()\n    if(1)\n        set waitfor = 0\n    return 1\n",
    );
    let old_body = &before.bodies[0];
    let body = &current.bodies[0];
    let proof = current
        .procedure_settings(body)
        .unwrap()
        .expect("production recipe must issue settings");
    let compact = current.compact_body(body).unwrap();
    let metadata = current
        .snapshot
        .tree
        .member(body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    assert!(proof.authenticates(compact, metadata));
    assert!(!proof.authenticates(before.compact_body(old_body).unwrap(), metadata));
    let mut changed = metadata.as_ref().clone();
    changed.settings = Arc::from([]);
    assert!(!proof.authenticates(compact, &changed));
    let mut symbols = SymbolTable::default();
    assert_eq!(
        crate::settings::extract_settings_view(compact, &mut symbols)
            .unwrap()
            .as_ref(),
        metadata.settings.as_ref()
    );
    let owner = current.settings_owner_storage()[0].as_ref().unwrap();
    assert!(
        Arc::ptr_eq(&owner.settings, &metadata.settings),
        "recipe must share producer settings instead of copying nodes"
    );
    let next = build(
        &mut state,
        "/datum/example/proc/read()\n    set waitfor = 1\n    return 1\n",
    );
    let next_body = &next.bodies[0];
    let next_metadata = next
        .snapshot
        .tree
        .member(next_body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    assert!(!proof.authenticates(compact, next_metadata));
    let mut tampered = current.clone();
    tampered.syntax = before.syntax.clone();
    assert!(tampered.procedure_settings(body).is_err());
}

#[test]
fn inconsistent_producer_settings_decline_issuance_without_replacing_validation() {
    let mut state = RetainedSemanticTree::default();
    let current = build(
        &mut state,
        "/proc/read()\n    set waitfor = 0\n    return 1\n",
    );
    let body = &current.bodies[0];
    let original = current
        .snapshot
        .tree
        .member(body.member)
        .unwrap()
        .metadata
        .procedure
        .as_ref()
        .unwrap();
    let mut changed = original.as_ref().clone();
    changed.settings = Arc::from([]);
    let source = "/proc/read()\n    set waitfor = 0\n    return 1\n";
    let parsed = dm_syntax::parse_declaration_skeleton(source);
    let owners = [(parsed.items[0].span.start, Arc::new(changed))].into();
    let relative = Arc::new(
        RelativeSyntax::capture_with_settings(parsed.items, source.into(), &owners).unwrap(),
    );
    let syntax = DeclarationSyntax::new(vec![relative.bind(source.len(), 0).unwrap()]).unwrap();
    assert!(syntax
        .body_recipes()
        .next()
        .unwrap()
        .settings_owner()
        .is_none());
}
