use super::*;
use crate::{build, MemberKind, OccurrenceTable};
#[test]
fn empty_formal_slots_and_missing_defaults_are_source_errors() {
    for prefix in ["", "// shifted\n\n"] {
        for arguments in [",value", "value,,second"] {
            let source = format!("{prefix}/proc/probe({arguments})\n    return 1\n");
            let errors = from_ast(&dm_syntax::parse(&source), SymbolTable::default(), FileId(3), 7, 11).unwrap_err();
            assert_eq!(errors.len(), 1);
            assert_eq!(errors[0].kind, dm_syntax::DiagnosticKind::Expression);
            assert_eq!(errors[0].message, "bad argument definition");
            assert_eq!(errors[0].span.start as usize, source.find("return").unwrap());
        }
        let source = format!("{prefix}/proc/probe(value = )\n    return 1\n");
        let errors = from_ast(&dm_syntax::parse(&source), SymbolTable::default(), FileId(3), 7, 11).unwrap_err();
        assert_eq!(errors[0].kind, dm_syntax::DiagnosticKind::Expression);
        assert_eq!(errors[0].message, "missing expression");
        assert_eq!(&source[errors[0].span.start as usize..errors[0].span.end as usize], "=");
    }
    for arguments in ["", "value,"] {
        let source = format!("/proc/probe({arguments})\n    return 1\n");
        assert!(from_ast(&dm_syntax::parse(&source), SymbolTable::default(), FileId(3), 7, 11).is_ok());
    }
}
#[test]
fn numeric_parameter_is_a_typed_source_error_at_its_current_token() {
    for prefix in ["", "// shifted source\n\n"] {
        let source = format!("{prefix}/proc/work(1)\n    return 1\n");
        let errors = from_ast(
            &dm_syntax::parse(&source),
            SymbolTable::default(),
            FileId(3),
            7,
            11,
        )
        .unwrap_err();
        assert_eq!(errors.len(), 1);
        assert_eq!(errors[0].kind, dm_syntax::DiagnosticKind::Expression);
        assert_eq!(errors[0].message, "bad argument definition");
        assert_eq!(
            &source[errors[0].span.start as usize..errors[0].span.end as usize],
            "1"
        );
        assert_eq!(errors[0].span.file, FileId(3));
    }
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/work(1)\n    return 1\n".into())
        }
    }
    let errors = crate::frontend::build_with_config(
        std::path::Path::new("probe.dme"),
        &Source,
        &Default::default(),
        crate::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap_err();
    assert_eq!(errors.len(), 1);
    assert_eq!(errors[0].kind, crate::frontend::DiagnosticKind::SourceError);
    // Numeric default expressions are valid; only the declaration path is rejected.
    let source = "/proc/work(value = 1 as num)\n    return 1\n";
    assert!(from_ast(
        &dm_syntax::parse(source),
        SymbolTable::default(),
        FileId(0),
        0,
        0
    )
    .is_ok());
}
#[test]
fn variable_input_annotations_are_not_initializer_tokens() {
    // Exact declaration spellings from the captured quantum/hyper pad sources.
    let source = "/datum/pad\n    var/map_pad_id = \"\" as text\n    var/map_pad_link_id = \"\" as text\n    var/control = list(\" as text\", list(\"as\")) as anything\n    var/plain = \" as text\"\n";
    let adapted = adapt(source);
    let values: Vec<_> = adapted
        .skeletons
        .iter()
        .filter_map(|row| match row {
            Skeleton::Member { name, metadata, .. } => Some((
                adapted.symbols.text(*name).unwrap(),
                metadata
                    .initializer
                    .as_ref()
                    .unwrap()
                    .tokens
                    .iter()
                    .map(|token| adapted.symbols.text(token.text).unwrap())
                    .collect::<Vec<_>>(),
            )),
            _ => None,
        })
        .collect();
    assert_eq!(
        values,
        vec![
            ("map_pad_id", vec!["\"\""]),
            ("map_pad_link_id", vec!["\"\""]),
            (
                "control",
                vec![
                    "list",
                    "(",
                    "\" as text\"",
                    ",",
                    "list",
                    "(",
                    "\"as\"",
                    ")",
                    ")"
                ]
            ),
            ("plain", vec!["\" as text\""]),
        ]
    );
    for row in &adapted.skeletons {
        if let Skeleton::Member { metadata, .. } = row {
            let expression = metadata.initializer.as_ref().unwrap();
            let first = &expression.tokens[0];
            assert_eq!(first.relative_span.start, 0);
        }
    }
}
#[test]
fn bare_nested_type_does_not_capture_following_sibling_defaults() {
    // Matches the captured clown declaration shape: the bare child and the
    // parent's defaults have equal indentation.
    let source = "/datum/base\n    var/value = 0\n    child\n        value = 2\n    value = 1\n    sibling\n    value = 3\n";
    let adapted = adapt(source);
    let assignments: Vec<_> = adapted
        .skeletons
        .iter()
        .zip(&adapted.origins)
        .filter_map(|(skeleton, origin)| match skeleton {
            Skeleton::Member {
                owner,
                name,
                mode: DefinitionMode::Override,
                ..
            } if *name == SymbolId::of("value") => Some((
                *owner,
                &source[origin.span.start as usize..origin.span.end as usize],
            )),
            _ => None,
        })
        .collect();
    assert_eq!(
        assignments,
        vec![
            (SymbolId::of("/datum/base/child"), "value = 2"),
            (SymbolId::of("/datum/base"), "value = 1"),
            (SymbolId::of("/datum/base"), "value = 3"),
        ]
    );
    let tree = build(adapted.symbols, &adapted.skeletons).unwrap();
    let base = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
    let child = tree.lookup_type(SymbolId::of("/datum/base/child")).unwrap();
    let value = SymbolId::of("value");
    let parent_field = tree.resolve(base, value, MemberKind::Var).unwrap();
    let child_field = tree.resolve(child, value, MemberKind::Var).unwrap();
    assert_ne!(parent_field, child_field);
    assert_eq!(tree.override_chain(parent_field).len(), 3);
}
#[test]
fn qualified_sibling_initializer_tokens_keep_original_expression_coordinates() {
    let source = "/datum/base\n    child\n    value = list(/proc/callback, \"literal /datum/path\", list(1, 2))\n";
    let adapted = adapt(source);
    let (expression, origin) = adapted
        .skeletons
        .iter()
        .zip(&adapted.origins)
        .find_map(|(skeleton, origin)| match skeleton {
            Skeleton::Member {
                owner,
                name,
                metadata,
                ..
            } if *owner == SymbolId::of("/datum/base") && *name == SymbolId::of("value") => {
                Some((metadata.initializer.as_ref().unwrap(), origin))
            }
            _ => None,
        })
        .unwrap();
    let original_header = &source[origin.span.start as usize..origin.span.end as usize];
    assert_eq!(
        original_header,
        "value = list(/proc/callback, \"literal /datum/path\", list(1, 2))"
    );
    let original_expression = original_header.split_once('=').unwrap().1.trim();
    for token in expression.tokens.iter() {
        assert_eq!(
            &original_expression[token.relative_span.start..token.relative_span.end],
            adapted.symbols.text(token.text).unwrap(),
        );
    }
}
#[test]
fn relative_assignment_trailing_slash_remains_an_invalid_target() {
    let source = "/datum/base\n    child\n    value/ = 1\n";
    let errors = from_ast(
        &dm_syntax::parse(source),
        SymbolTable::default(),
        FileId(3),
        7,
        11,
    )
    .unwrap_err();
    assert_eq!(errors.len(), 1);
    assert!(errors[0]
        .message
        .starts_with("unsupported field assignment:"));
    assert_eq!(
        &source[errors[0].span.start as usize..errors[0].span.end as usize],
        "value/ = 1"
    );
}
#[test]
fn absolute_root_members_do_not_inherit_last_type_anchor() {
    let adapted=adapt("/datum/anchor\n    var/local_value = 1\n    var/scoped_value = 3\n    proc/scoped_read()\n        return scoped_value\n/var/global_value = 2\n/proc/root_read()\n    return global_value\n");
    let root = SymbolId::of("/");
    for name in ["global_value", "root_read"] {
        assert!(adapted.skeletons.iter().any(|skeleton|matches!(skeleton,
                Skeleton::Member{owner,name:member,..} if *owner==root && *member==SymbolId::of(name))));
    }
    for name in ["scoped_value", "scoped_read"] {
        assert!(adapted.skeletons.iter().any(|skeleton|matches!(skeleton,
                Skeleton::Member{owner,name:member,..} if *owner==SymbolId::of("/datum/anchor") && *member==SymbolId::of(name))));
    }
}
#[test]
fn global_procedure_is_not_an_inherited_instance_method() {
    let adapted=adapt("/proc/shared_name()\n    return 1\n/datum/base\n/datum/base/proc/shared_name()\n    return 2\n/datum/base/child\n");
    let tree = build(adapted.symbols, &adapted.skeletons).unwrap();
    let root = tree.lookup_type(SymbolId::of("/")).unwrap();
    let base = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
    let child = tree.lookup_type(SymbolId::of("/datum/base/child")).unwrap();
    let name = SymbolId::of("shared_name");
    let global = tree.resolve(root, name, MemberKind::Proc).unwrap();
    let method = tree.resolve(base, name, MemberKind::Proc).unwrap();
    assert_ne!(global, method);
    assert_eq!(tree.override_chain(method), vec![method]);
    assert_eq!(tree.resolve(child, name, MemberKind::Proc), Some(method));
    let other = adapt("/proc/shared_name()\n    return 1\n/datum/other\n");
    let other = build(other.symbols, &other.skeletons).unwrap();
    assert_eq!(
        other.resolve(
            other.lookup_type(SymbolId::of("/datum/other")).unwrap(),
            name,
            MemberKind::Proc
        ),
        None
    );
}
fn adapt(source: &str) -> AdaptedDeclarations {
    from_ast(
        &dm_syntax::parse(source),
        SymbolTable::default(),
        FileId(3),
        7,
        11,
    )
    .unwrap()
}

#[test]
fn resolution_observer_borrows_exact_source_ledger_only_on_failure() {
    let adapted = adapt("/datum/a\n    parent_type = /datum\n/datum/a\n    parent_type = /obj\n");
    let skeleton_address = adapted.skeletons.as_ptr();
    let origin_address = adapted.origins.as_ptr();
    let expected_origins = adapted.origins.clone();
    let mut calls = 0;
    let result = adapted.finish_with_engine_observed(None, |error, skeletons, origins| {
        calls += 1;
        assert!(matches!(
            error,
            SnapshotError::Tree(crate::TreeError::ConflictingParent(_))
        ));
        assert_eq!(skeletons.as_ptr(), skeleton_address);
        assert_eq!(origins.as_ptr(), origin_address);
        assert_eq!(origins, expected_origins);
    });
    assert!(result.is_err());
    assert_eq!(calls, 1);
    adapt("/datum/a\n    var/value = 1\n")
        .finish_with_engine_observed(None, |_, _, _| {
            panic!("successful resolution notified observer")
        })
        .unwrap();
}
#[test]
fn qualified_assignment_preserves_owner_and_procedure_reference() {
    let result = adapt("/datum/base\n    var/callback\n/datum/base/callback = /proc/finish\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
    let field = tree
        .member(
            tree.resolve(owner, SymbolId::of("callback"), MemberKind::Var)
                .unwrap(),
        )
        .unwrap();
    assert!(field.previous.is_some());
    let initializer = field.metadata.initializer.as_ref().unwrap();
    let spelling: String = initializer
        .tokens
        .iter()
        .map(|token| tree.symbols.text(token.text).unwrap())
        .collect();
    assert_eq!(spelling, "/proc/finish");
}
#[test]
fn optional_separator_before_procedure_arguments_preserves_owner_and_name() {
    let result = adapt("/obj/machinery/status_display/supply_display/receive_signal/(datum/signal/signal)\n    return signal\n/obj/machinery/status_display/supply_display/proc/receive_formal/(datum/signal/signal)\n    return signal\n");
    let members = result
        .skeletons
        .iter()
        .filter_map(|row| match row {
            Skeleton::Member {
                owner,
                name,
                kind,
                metadata,
                ..
            } => Some((*owner, *name, *kind, metadata)),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(members.len(), 2);
    for (index, (owner, name, kind, metadata)) in members.iter().enumerate() {
        assert_eq!(
            *owner,
            SymbolId::of("/obj/machinery/status_display/supply_display")
        );
        assert_eq!(
            *name,
            SymbolId::of(if index == 0 {
                "receive_signal"
            } else {
                "receive_formal"
            })
        );
        assert_eq!(*kind, MemberKind::Proc);
        let parameter = &metadata.procedure.as_ref().unwrap().signature.parameters[0];
        assert_eq!(parameter.name, SymbolId::of("signal"));
        assert_eq!(parameter.declared_type, Some(SymbolId::of("/datum/signal")));
    }
}
#[test]
fn authored_parent_overrides_engine_default_but_source_conflicts_still_fail() {
    let mut symbols = SymbolTable::default();
    let root = symbols.intern("/").unwrap();
    let datum = symbols.intern("/datum").unwrap();
    let client = symbols.intern("/client").unwrap();
    let seed = crate::frontend::EngineSeed {
        identity: 7,
        symbols: symbols.clone(),
        hierarchy: crate::EngineHierarchy {
            schema: 7,
            parents: vec![(root, None), (datum, Some(root)), (client, Some(root))],
        },
        intrinsics: Arc::from([]),
        fields: Arc::from([]),
    };
    let prepare = |source: &str| {
        from_ast(&dm_syntax::parse(source), symbols.clone(), FileId(3), 7, 11)
            .unwrap()
            .finish_with_engine(Some(&seed))
    };
    let snapshot =
        prepare("/client\n    parent_type = /datum\n/client\n    var/example\n").unwrap();
    let owner = snapshot.tree.lookup_type(client).unwrap();
    assert_eq!(
        snapshot
            .tree
            .type_node(snapshot.tree.parent(owner).unwrap())
            .unwrap()
            .path,
        datum
    );
    assert_eq!(
        seed.hierarchy
            .parents
            .iter()
            .find(|row| row.0 == client)
            .unwrap()
            .1,
        Some(root)
    );
    assert!(
        matches!(prepare("/client\n    parent_type = /datum\n/client\n    parent_type = /\n"), Err(SnapshotError::Tree(crate::TreeError::ConflictingParent(path))) if path == client)
    );
    assert!(matches!(
        prepare("/client\n    parent_type = /datum\n/datum\n    parent_type = /client\n"),
        Err(SnapshotError::Tree(crate::TreeError::InheritanceCycle(_)))
    ));
}
#[test]
fn var_namespace_separator_does_not_split_owner_component_suffix() {
    let result = adapt("/datum/property_provider/type_var/var/variant_var = 1\n/datum/property_provider/type_var\n    var/var/obj/reference\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree
        .lookup_type(SymbolId::of("/datum/property_provider/type_var"))
        .unwrap();
    for name in ["variant_var", "reference"] {
        let field = tree
            .members()
            .iter()
            .find(|member| member.name == SymbolId::of(name))
            .unwrap();
        assert_eq!(field.owner, owner);
    }
    assert!(tree
        .lookup_type(SymbolId::of("/datum/property_provider/type_"))
        .is_none());
}
#[test]
fn repeated_var_namespace_keeps_declaring_owner_and_runtime_type() {
    let result = adapt("/datum/base\n    var/var/obj/reference\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let field = tree
        .members()
        .iter()
        .find(|member| member.name == SymbolId::of("reference"))
        .unwrap();
    assert_eq!(
        Some(field.owner),
        tree.lookup_type(SymbolId::of("/datum/base"))
    );
    assert_eq!(field.metadata.declared_type, Some(SymbolId::of("/obj")));
}
#[test]
fn typed_list_declarations_expose_the_runtime_container_type() {
    let result = adapt("/datum/base\n    var/list/datum/feedback_variable/feedback = new()\n    proc/read(list/datum/feedback_variable/values)\n        return values\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let field = tree
        .members()
        .iter()
        .find(|member| member.name == SymbolId::of("feedback"))
        .unwrap();
    assert_eq!(field.metadata.declared_type, Some(SymbolId::of("/list")));
    assert!(
        field.metadata.array.is_none(),
        "a typed list is not a sized array"
    );
    let procedure = tree
        .members()
        .iter()
        .find(|member| member.name == SymbolId::of("read"))
        .unwrap();
    assert_eq!(
        procedure
            .metadata
            .procedure
            .as_ref()
            .unwrap()
            .signature
            .parameters[0]
            .declared_type,
        Some(SymbolId::of("/list"))
    );
}
#[test]
fn namespaces_arrays_defaults_and_settings_bridge_to_tree() {
    let result=adapt("/datum/base\n    var\n        static/list\n            values[2][3]\n    proc\n        read(value = 3 as num)\n            set name = \"Reader\"\n            set waitfor = 0\n            return value\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
    let array = tree
        .member(
            tree.resolve(owner, SymbolId::of("values"), MemberKind::Var)
                .unwrap(),
        )
        .unwrap();
    assert_eq!(array.metadata.declared_type, Some(SymbolId::of("/list")));
    assert_eq!(array.metadata.flags & 1, 1);
    let proc = tree
        .member(
            tree.resolve(owner, SymbolId::of("read"), MemberKind::Proc)
                .unwrap(),
        )
        .unwrap();
    assert_eq!(proc.metadata.display_name, Some(SymbolId::of("Reader")));
    assert!(proc.metadata.procedure.is_some());
    assert_eq!(
        OccurrenceTable::build(&tree, result.origins)
            .unwrap()
            .source_order()
            .len(),
        3
    );
}
#[test]
fn inherited_field_assignment_preserves_type_and_flags() {
    let result=adapt("/datum/base\n    var/tmp/list/values = null\n/datum/child\n    parent_type = /datum/base\n    values = list(1, 2)\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/child")).unwrap();
    let field = tree
        .member(
            tree.resolve(owner, SymbolId::of("values"), MemberKind::Var)
                .unwrap(),
        )
        .unwrap();
    assert_eq!(field.metadata.declared_type, Some(SymbolId::of("/list")));
    assert_eq!(field.metadata.flags & 4, 4);
    assert!(field.previous.is_some());
}
#[test]
fn typed_list_hints_survive_formal_inheritance_without_changing_container() {
    let result = adapt("/datum/base\n    var/list/datum/item/values\n/datum/child\n    parent_type = /datum/base\n    values = list()\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    for path in ["/datum/base", "/datum/child"] {
        let owner = tree.lookup_type(SymbolId::of(path)).unwrap();
        let field = tree
            .member(
                tree.resolve(owner, SymbolId::of("values"), MemberKind::Var)
                    .unwrap(),
            )
            .unwrap();
        assert_eq!(field.metadata.declared_type, Some(SymbolId::of("/list")));
        assert_eq!(
            field.metadata.list_element_type,
            Some(SymbolId::of("/datum/item"))
        );
        assert!(field.metadata.array.is_none());
    }
}
#[test]
fn forward_multilevel_field_inheritance_resolves_in_dependency_order() {
    let result=adapt("/datum/child\n    parent_type = /datum/parent\n    value = 3\n/datum/parent\n    parent_type = /datum/grand\n    value = 2\n/datum/grand\n    var/tmp/list/value = null\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let child = tree.lookup_type(SymbolId::of("/datum/child")).unwrap();
    let id = tree
        .resolve(child, SymbolId::of("value"), MemberKind::Var)
        .unwrap();
    assert_eq!(
        tree.member(id).unwrap().metadata.declared_type,
        Some(SymbolId::of("/list"))
    );
    assert_eq!(tree.member(id).unwrap().metadata.flags & 4, 4);
    assert_eq!(tree.override_chain(id).len(), 3);
}

#[test]
fn observed_formal_base_and_encounter_override_chain_are_distinct() {
    let project = include_str!(
        "../../../fixtures/phase0/preprocess/manifest-order/proc-two-overrides/project.dme"
    );
    let child = include_str!(
        "../../../fixtures/phase0/preprocess/manifest-order/proc-two-overrides/child.dm"
    );
    let source = project.replace("#include \"child.dm\"", child);
    let result = adapt(&source);
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let effective = tree
        .resolve(owner, SymbolId::of("read"), MemberKind::Proc)
        .unwrap();
    let chain = tree.override_chain(effective);
    assert_eq!(chain.len(), 3);
    assert_eq!(
        tree.member(chain[0]).unwrap().definition,
        DefinitionMode::Implicit
    );
    assert_eq!(
        tree.member(chain[2]).unwrap().definition,
        DefinitionMode::Declare
    );
    let origins = OccurrenceTable::build(&tree, result.origins).unwrap();
    let texts: Vec<_> = chain
        .iter()
        .map(|id| {
            let origin = origins
                .get(origins.for_target(crate::Target::Member(*id))[0])
                .unwrap();
            &source[origin.provenance.span.start as usize..origin.provenance.span.end as usize]
        })
        .collect();
    assert!(texts[0].contains("return 2"));
    assert!(texts[1].contains("return 1"));
    assert!(texts[2].contains("return 0"));
}
#[test]
fn implicit_before_formal_still_resolves_to_override() {
    let source = "/datum/probe/read()\n    return 2\n/datum/probe/proc/read()\n    return 1\n";
    let result = adapt(source);
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let id = tree
        .resolve(owner, SymbolId::of("read"), MemberKind::Proc)
        .unwrap();
    let chain = tree.override_chain(id);
    assert_eq!(chain, vec![crate::MemberId(0), crate::MemberId(1)]);
    assert_eq!(
        tree.member(id).unwrap().definition,
        DefinitionMode::Implicit
    );
}
#[test]
fn observed_field_default_is_retained_beside_effective_class_assignment() {
    let project =
        include_str!("../../../fixtures/phase0/preprocess/manifest-order/field-before/project.dme");
    let child =
        include_str!("../../../fixtures/phase0/preprocess/manifest-order/field-before/child.dm");
    let result = adapt(&project.replace("#include \"child.dm\"", child));
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/probe")).unwrap();
    let id = tree
        .resolve(owner, SymbolId::of("value"), MemberKind::Var)
        .unwrap();
    let metadata = &tree.member(id).unwrap().metadata;
    assert_eq!(
        metadata
            .declared_initializer
            .as_ref()
            .unwrap()
            .source_text(tree.symbols())
            .as_deref(),
        Some("1")
    );
    assert_eq!(
        metadata
            .initializer
            .as_ref()
            .unwrap()
            .source_text(tree.symbols())
            .as_deref(),
        Some("2")
    );
}

#[test]
fn body_changes_reuse_tree_but_setting_changes_do_not() {
    let identity = |source| {
        let result = adapt(source);
        build(result.symbols, &result.skeletons).unwrap().identity()
    };
    let first = "/datum/base/proc/read(value = 3 as num)\n    set waitfor = 0\n    return 1\n";
    let second = first.replace("return 1", "return 222");
    assert_eq!(identity(first), identity(&second));
    assert_ne!(
        identity(first),
        identity(&first.replace("waitfor = 0", "waitfor = 1"))
    );
}
#[test]
fn unresolved_constant_is_explicitly_unsupported() {
    use dm_ir::{ResolveQuery, ResolvedMeaning, Resolver};
    let result = adapt("var/const/first = 1\nvar/const/second = first + 1\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let query = ResolveQuery::Constant {
        owner: SymbolId::of("/"),
        name: SymbolId::of("second"),
    };
    assert_eq!(
        Resolver::resolve(&tree, query),
        ResolvedMeaning::Unsupported(query)
    );
    assert!(matches!(
        Resolver::resolve(
            &tree,
            ResolveQuery::Constant {
                owner: SymbolId::of("/"),
                name: SymbolId::of("first")
            }
        ),
        ResolvedMeaning::Member { .. }
    ));
}
#[test]
fn absolute_field_assignment_is_owned_by_its_target() {
    let result = adapt("/datum/base\n    var/value = 1\n/datum/base/value = 2\n");
    let tree = build(result.symbols, &result.skeletons).unwrap();
    let owner = tree.lookup_type(SymbolId::of("/datum/base")).unwrap();
    let field = tree
        .resolve(owner, SymbolId::of("value"), MemberKind::Var)
        .unwrap();
    assert_eq!(tree.override_chain(field).len(), 2);
}

#[test]
fn absolute_header_type_effect_uses_exact_current_header_origin() {
    let source = "/datum/marker_target\n    var/value = 7\n/proc/probe(/datum/marker_target/target)\n    return 1\n";
    let adapted = adapt(source);
    let effect = adapted
        .skeletons
        .iter()
        .position(|skeleton| {
            matches!(skeleton,
        Skeleton::Type {path, ..} if *path == SymbolId::of("/datum/marker_target/target"))
        })
        .unwrap();
    let origin = &adapted.origins[effect];
    assert_eq!(
        &source[origin.span.start as usize..origin.span.end as usize],
        "/datum/marker_target/target"
    );
    assert_eq!(origin.include_occurrence, 7);
    assert_eq!(origin.region, 11);
    let procedure = adapted
        .skeletons
        .iter()
        .find_map(|skeleton| match skeleton {
            Skeleton::Member { name, metadata, .. } if *name == SymbolId::of("probe") => {
                metadata.procedure.as_ref()
            }
            _ => None,
        })
        .unwrap();
    assert!(procedure.signature.parameters.is_empty());
}
