use super::*;
use std::path::Path;

struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn capture(source: &'static str) -> LinkInventory {
    let frontend = dm_tree::frontend::build(
        Path::new("probe.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap();
    let mut inventory = LinkInventory::default();
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        &frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    contribute_source_strings(&frontend, &bodies, &mut inventory).unwrap();
    inventory
}

#[test]
fn string_allocation_captures_only_first_root_body_including_unreachable_literals() {
    let inventory = capture(
        "/datum/orderholder/var/before = 1\n/proc/first()\n    return 1\n    return \"a_second\"\n/proc/second()\n    return \"z_first\"\n/world/New()\n    return \"type_value\"\n/datum/orderholder\n    var/z_first = 1\n    var/static/type_value = 2\n    var/a_second = 3\n",
    );
    let events = &inventory.string_registration.as_ref().unwrap().events;
    assert!(matches!(events[0], Event::FieldName { name, .. } if name == SymbolId::of("before")));
    let early: Vec<_> = events
        .iter()
        .filter_map(|event| match event {
            Event::FirstRootCallable {
                callable, strings, ..
            } => Some((*callable, strings.as_ref())),
            _ => None,
        })
        .collect();
    assert_eq!(early.len(), 1);
    assert_eq!(
        early[0].0,
        Key::Proc {
            owner: SymbolId::of("/"),
            name: SymbolId::of("first"),
            occurrence: 0,
        }
    );
    assert_eq!(early[0].1, &[SymbolId::of("a_second")]);
    for name in ["before", "z_first", "type_value", "a_second"] {
        assert!(inventory
            .entry_iter()
            .any(|entry| entry.key == Key::String(SymbolId::of(name))));
    }
}

#[test]
fn string_allocation_preserves_first_occurrence_in_overridden_root_chain() {
    let inventory = capture(
        "/proc/first()\n    return \"a_second\"\n/first()\n    return \"z_first\"\n/datum/orderholder\n    var/z_first = 1\n    var/a_second = 2\n",
    );
    let Event::FirstRootCallable {
        callable,
        strings,
        declaration,
        ..
    } = &inventory.string_registration.as_ref().unwrap().events[0]
    else {
        panic!("first root callable absent");
    };
    assert!(matches!(callable, Key::Proc { occurrence: 0, .. }));
    assert_eq!(*declaration, 0);
    assert_eq!(strings.as_ref(), &[SymbolId::of("a_second")]);
}

#[test]
fn string_allocation_field_name_precedes_own_initializer_and_decodes_cooked_literals() {
    let inventory = capture(
        "/var/global/before = \"a_second\"\n/proc/first()\n    return \"\\x74ype_value\"\n/datum/orderholder\n    var/z_first = 1\n    var/static/type_value = 2\n    var/a_second = 3\n",
    );
    let events = &inventory.string_registration.as_ref().unwrap().events;
    assert!(matches!(events[0], Event::FieldName { name, .. } if name == SymbolId::of("before")));
    assert!(
        matches!(&events[1], Event::DeclarationStrings { strings, .. }
        if strings.as_ref() == [SymbolId::of("a_second")])
    );
    assert!(
        matches!(&events[2], Event::FirstRootCallable { strings, .. }
        if strings.as_ref() == [SymbolId::of("type_value")])
    );
}

#[test]
fn string_allocation_numeric_first_root_does_not_read_later_body_literals() {
    let inventory = capture(
        "/proc/first()\n    return 1\n/proc/second()\n    return \"a_second\"\n/datum/orderholder\n    var/z_first = 1\n    var/type_value = 2\n    var/a_second = 3\n",
    );
    assert!(
        matches!(&inventory.string_registration.as_ref().unwrap().events[0],
        Event::FirstRootCallable { strings, .. } if strings.is_empty())
    );
}

#[test]
fn string_allocation_raw_literals_and_comments_keep_exact_candidate_content() {
    let names = [SymbolId::of("a_second"), SymbolId::of("type_value")]
        .into_iter()
        .collect();
    assert_eq!(candidate_literals(
        "// \"type_value\"\nreturn @\"a_second\"\nreturn \"\\x74ype_value\"\nreturn \"a_second\"\n",
        &names,
    ).unwrap(), [SymbolId::of("a_second"), SymbolId::of("type_value")]);
    // A template's raw text is not a constant field-name spelling.
    assert!(candidate_literals("return \"[x]a_second\"\n", &names)
        .unwrap()
        .is_empty());
}

#[test]
fn string_allocation_captures_nested_literals_in_current_first_root_even_unselected() {
    let inventory = capture(
        r#"/proc/first()
    return "[1 ? "a_second" : "type_value"]"
/datum/orderholder
    var/z_first = 1
    var/type_value = 2
    var/a_second = 3
"#,
    );
    assert!(
        matches!(&inventory.string_registration.as_ref().unwrap().events[0],
        Event::FirstRootCallable { strings, .. }
            if strings.as_ref() == [SymbolId::of("a_second"), SymbolId::of("type_value")])
    );
}

fn first_root_strings(source: &'static str) -> Vec<SymbolId> {
    capture(source)
        .string_registration
        .unwrap()
        .events
        .into_iter()
        .find_map(|event| match event {
            Event::FirstRootCallable { strings, .. } => Some(strings.to_vec()),
            _ => None,
        })
        .unwrap()
}

#[test]
fn string_allocation_formal_and_local_names_precede_later_literals_from_current_body() {
    for source in [
        "/proc/first(z_first)\n    return \"a_second\"\n/datum/orderholder\n    var/z_first = 1\n    var/a_second = 2\n",
        "/proc/first()\n    var/z_first = 7\n    return \"a_second\"\n/datum/orderholder\n    var/z_first = 1\n    var/a_second = 2\n",
    ] {
        assert_eq!(first_root_strings(source), [SymbolId::of("z_first"), SymbolId::of("a_second")]);
    }
}

#[test]
fn string_allocation_literal_before_local_is_not_reordered_by_complete_frame_names() {
    assert_eq!(first_root_strings(
        "/proc/first()\n    var/temporary = \"a_second\"\n    var/z_first = 7\n    return z_first\n/datum/orderholder\n    var/z_first = 1\n    var/a_second = 2\n",
    ), [SymbolId::of("a_second"), SymbolId::of("z_first")]);
}

#[test]
fn string_allocation_loop_and_catch_declarations_interleave_with_literals() {
    assert_eq!(first_root_strings(
        "/proc/first()\n    for(var/z_first in list(\"a_second\"))\n        try\n            throw 7\n        catch(var/type_value)\n            return type_value\n/datum/orderholder\n    var/z_first = 1\n    var/type_value = 2\n    var/a_second = 3\n",
    ), [SymbolId::of("z_first"), SymbolId::of("a_second"), SymbolId::of("type_value")]);
}

#[test]
fn string_allocation_uses_the_same_parsed_slot_consumed_by_lowering() {
    let frontend = dm_tree::frontend::build(Path::new("probe.dme"), &Source(
        "/proc/first()\n    var/z_first = 7\n    return \"a_second\"\n/datum/orderholder\n    var/z_first = 1\n    var/a_second = 2\n",
    ), &Default::default(), 1).unwrap();
    let bodies = dm_tree::frontend::BodyArena::new_typed(
        &frontend,
        dm_codegen_byond::typed_statements_supported_for_capture,
    );
    let body = &frontend.bodies[0];
    let before = bodies
        .with_parsed(body, |parsed| {
            Arc::as_ptr(&parsed.shared_statement_body().unwrap()) as usize
        })
        .unwrap();
    let mut inventory = LinkInventory::default();
    contribute_source_strings(&frontend, &bodies, &mut inventory).unwrap();
    let consumed = bodies.take_parsed(body).unwrap();
    assert_eq!(
        Arc::as_ptr(&consumed.shared_statement_body().unwrap()) as usize,
        before
    );
    assert!(bodies.take_parsed(body).is_err());
}
