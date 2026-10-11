use super::*;

fn image() -> Dmb {
    Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap()
}

#[test]
fn inherited_headers_preserve_explicit_fields_and_unrelated_callback_bits() {
    let dmb = image();
    let mut parent = dmb.classes[0].clone();
    let mut child = parent.clone();
    parent.initial_ids[2] = 30;
    parent.initial_ids[4] = 40;
    parent.layer_bits = 2.0_f32.to_bits();
    parent.set_mouse_opacity(0).unwrap();
    child.initial_ids[4] = 99;
    child.layer_bits = 8.0_f32.to_bits();
    let prior_callbacks = (
        child.has_mouse_event_proc(),
        child.has_mouse_move_proc(),
        child.has_mouse_wheel_proc(),
    );
    inherit_record(
        &parent,
        &mut child,
        &HashSet::from(["icon", "layer"]),
        true,
        false,
    )
    .unwrap();
    assert_eq!(child.initial_ids[2], 30);
    assert_eq!(child.initial_ids[4], 99);
    assert_eq!(child.layer_bits, 8.0_f32.to_bits());
    assert_eq!(child.mouse_opacity(), 0);
    assert_eq!(
        (
            child.has_mouse_event_proc(),
            child.has_mouse_move_proc(),
            child.has_mouse_wheel_proc()
        ),
        prior_callbacks
    );
}

#[test]
fn native_subtype_layer_is_preserved_without_freezing_parent_defaults() {
    let dmb = image();
    let mut parent = dmb.classes[0].clone();
    let mut child = parent.clone();
    parent.layer_bits = 1.0_f32.to_bits();
    child.layer_bits = 2.0_f32.to_bits();
    let mut own = HashSet::new();
    native_header_differences(&dmb, &child, &parent, &mut own);
    assert!(own.contains("layer"));
    assert!(!own.contains("icon"));
    parent.initial_ids[4] = 51;
    inherit_record(&parent, &mut child, &own, false, false).unwrap();
    assert_eq!(child.layer_bits, 2.0_f32.to_bits());
    assert_eq!(child.initial_ids[4], 51);
}

#[test]
fn stale_cloned_builtin_defaults_yield_to_effective_parent_but_own_plane_wins() {
    let mut dmb = image();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let plane = pool.intern(&mut dmb, b"plane").unwrap();
    let parent = dmb.classes.len() as u32;
    let child = parent + 1;
    let record = dmb.classes[0].clone();
    dmb.classes.extend([record.clone(), record]);
    let value = |n: f32| byond_dmb::operands::Value {
        tag_word: 42,
        data_word: n.to_bits() >> 16,
        extra_word: Some(n.to_bits() & 0xffff),
    };
    let mut parent_words = vec![plane];
    parent_words.extend(value(7.0).encode());
    dmb.classes[parent as usize].overrides =
        crate::composition::append_list(&mut dmb, parent_words).unwrap();
    let mut stale = vec![plane];
    stale.extend(value(0.0).encode());
    let stale_id = crate::composition::append_list(&mut dmb, stale).unwrap();
    dmb.classes[child as usize].overrides = stale_id;
    inherit_overrides(&mut dmb, child, parent, &HashSet::new(), &HashSet::new()).unwrap();
    assert_eq!(
        dmb.class_builtin_overrides(child as usize).unwrap()[0].value,
        value(7.0)
    );
    dmb.classes[child as usize].overrides = stale_id;
    inherit_overrides(
        &mut dmb,
        child,
        parent,
        &HashSet::from(["plane"]),
        &HashSet::new(),
    )
    .unwrap();
    assert_eq!(
        dmb.class_builtin_overrides(child as usize).unwrap()[0].value,
        value(0.0)
    );
}

#[test]
fn parent_order_handles_forward_ids_and_rejects_cycles() {
    let mut dmb = image();
    let first = dmb.classes.len() as u32;
    let mut child = dmb.classes[0].clone();
    child.initial_ids[1] = first + 1;
    let mut parent = child.clone();
    parent.initial_ids[1] = NONE;
    dmb.classes.extend([child, parent]);
    let ids = BTreeSet::from([first, first + 1]);
    assert_eq!(parent_order(&dmb, &ids).unwrap(), [first + 1, first]);
    dmb.classes[(first + 1) as usize].initial_ids[1] = first;
    assert!(parent_order(&dmb, &ids).is_err());
}

#[test]
fn finalize_preserves_runtime_override_token_instead_of_parent_scalar() {
    let engine_bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = image();
    let mut symbols = dm_ir::SymbolTable::default();
    let parent_symbol = symbols.intern("/datum/runtime_default_parent").unwrap();
    let child_symbol = symbols
        .intern("/datum/runtime_default_parent/child")
        .unwrap();
    let plane_symbol = symbols.intern("plane").unwrap();
    let parent = dmb.classes.len() as u32;
    let child = parent + 1;
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let plane = pool.intern(&mut dmb, b"plane").unwrap();
    let mut parent_record = dmb.classes[0].clone();
    parent_record.initial_ids[0] = pool
        .intern(&mut dmb, b"/datum/runtime_default_parent")
        .unwrap();
    parent_record.initial_ids[1] = NONE;
    parent_record.layer_bits = 9.0f32.to_bits();
    let mut child_record = parent_record.clone();
    child_record.initial_ids[0] = pool
        .intern(&mut dmb, b"/datum/runtime_default_parent/child")
        .unwrap();
    child_record.initial_ids[1] = parent;
    child_record.layer_bits = 1.0f32.to_bits();
    let scalar = byond_dmb::operands::Value {
        tag_word: 42,
        data_word: 7.0f32.to_bits() >> 16,
        extra_word: Some(7.0f32.to_bits() & 0xffff),
    };
    let marker = byond_dmb::operands::Value {
        tag_word: 62,
        data_word: 123,
        extra_word: None,
    };
    let mut words = vec![plane];
    words.extend(scalar.encode());
    parent_record.overrides = crate::composition::append_list(&mut dmb, words).unwrap();
    let mut words = vec![plane];
    words.extend(marker.encode());
    child_record.overrides = crate::composition::append_list(&mut dmb, words).unwrap();
    dmb.classes.extend([parent_record, child_record]);
    let mut inventory = dm_link::LinkInventory::default();
    for (symbol, index) in [(parent_symbol, parent), (child_symbol, child)] {
        let key = Key::Type(symbol);
        inventory
            .spellings
            .push((symbol, Arc::from(symbols.text(symbol).unwrap().as_bytes())));
        inventory.entries.push(dm_link::Entry {
            key,
            content: Arc::<[u8]>::from([]).into(),
        });
        inventory.fixed.push((key, index));
    }
    let tables = dm_link::LinkTables::build(inventory).unwrap();
    let projection = ClassProjection {
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
        procedure_declarations: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: Arc::from([TypeProjection {
            path: child_symbol,
            parent: Some(parent_symbol),
        }]),
        fields: Arc::from([std::sync::Arc::new(FieldProjection {
            owner: child_symbol,
            declaring_owner: parent_symbol,
            name: plane_symbol,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: crate::initializer_policy::DefaultValue::InitializerExpression {
                token: 123,
                canonical: Arc::from([]),
            },
        })]),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
    };
    finalize_headers(&mut dmb, engine_bytes, &projection, &tables, &symbols).unwrap();
    let defaults = dmb.class_builtin_overrides(child as usize).unwrap();
    assert_eq!(defaults.len(), 1);
    assert_eq!(defaults[0].name_string_id, plane);
    assert_eq!(defaults[0].value, marker);
    assert_eq!(dmb.classes[child as usize].layer_bits, 9.0f32.to_bits());
}

#[test]
fn equal_selector_bytes_mask_parent_even_with_different_string_ids() {
    let mut dmb = image();
    let mut pool = crate::composition::StringIndex::build(&dmb).unwrap();
    let parent_name = pool.intern(&mut dmb, b"plane").unwrap();
    let child_name = dmb.strings.len() as u32;
    dmb.strings.push(dmb.strings[parent_name as usize].clone());
    assert_ne!(parent_name, child_name);
    let marker = byond_dmb::operands::Value {
        tag_word: 62,
        data_word: 456,
        extra_word: None,
    };
    let scalar = byond_dmb::operands::Value {
        tag_word: 42,
        data_word: 3.0f32.to_bits() >> 16,
        extra_word: Some(3.0f32.to_bits() & 0xffff),
    };
    let parent = dmb.classes.len() as u32;
    let child = parent + 1;
    let record = dmb.classes[0].clone();
    dmb.classes.extend([record.clone(), record]);
    let mut words = vec![parent_name];
    words.extend(scalar.encode());
    dmb.classes[parent as usize].overrides =
        crate::composition::append_list(&mut dmb, words).unwrap();
    let mut words = vec![child_name];
    words.extend(marker.encode());
    dmb.classes[child as usize].overrides =
        crate::composition::append_list(&mut dmb, words).unwrap();
    inherit_overrides(
        &mut dmb,
        child,
        parent,
        &HashSet::from(["plane"]),
        &HashSet::new(),
    )
    .unwrap();
    let defaults = dmb.class_builtin_overrides(child as usize).unwrap();
    assert_eq!(defaults.len(), 1);
    assert_eq!(defaults[0].name_string_id, child_name);
    assert_eq!(defaults[0].value, marker);
}

#[test]
fn authored_ancestor_assignment_overrides_native_subtype_default_even_when_unchanged() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let mut dmb = image();
    let mut symbols = SymbolTable::default();
    let atom = symbols.intern("/atom").unwrap();
    let area = symbols.intern("/area").unwrap();
    let layer = symbols.intern("layer").unwrap();
    let index = |dmb: &Dmb, path: &[u8]| {
        dmb.classes
            .iter()
            .position(|class| dmb.string(class.path_string_id()) == Some(path))
            .unwrap()
    };
    let atom_id = index(&dmb, b"/atom");
    let area_id = index(&dmb, b"/area");
    let inherited = dmb.classes[atom_id].layer_bits;
    let native_area = dmb.classes[area_id].layer_bits;
    assert_ne!(
        inherited, native_area,
        "pinned engine must exercise native subtype default"
    );
    let mut projection = ClassProjection {
        type_construction: Default::default(),
        variable_records: Default::default(),
        field_placements: Default::default(),
        shared_slot_order: Arc::from([]),
        procedure_statics: Arc::from([]),
        runtime_writes: Arc::from([]),
        tree_identity: 0,
        occurrence_count: 0,
        types: vec![
            TypeProjection {
                path: atom,
                parent: None,
            },
            TypeProjection {
                path: area,
                parent: Some(atom),
            },
        ]
        .into(),
        fields: vec![std::sync::Arc::new(FieldProjection {
            owner: atom,
            declaring_owner: atom,
            name: layer,
            role: FieldRole::Assignment,
            wire_flags: None,
            intrinsic: true,
            shared: false,
            value: DefaultValue::Scalar(SemanticValue::NumberBits(inherited)),
        })]
        .into(),
        chains: Arc::from([]),
        procedure_membership: Arc::from([]),
        procedure_declarations: Arc::new(BTreeMap::new()),
    };
    let tables = dm_link::LinkTables::build(Default::default()).unwrap();
    finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    assert_eq!(dmb.classes[area_id].layer_bits, inherited);
    // A source child assignment still wins over the authored parent.
    dmb.classes[area_id].layer_bits = native_area;
    let mut fields = projection.fields.to_vec();
    fields.push(std::sync::Arc::new(FieldProjection {
        owner: area,
        declaring_owner: area,
        name: layer,
        role: FieldRole::Assignment,
        wire_flags: None,
        intrinsic: true,
        shared: false,
        value: DefaultValue::Scalar(SemanticValue::NumberBits(native_area)),
    }));
    projection.fields = fields.into();
    finalize_headers(&mut dmb, bytes, &projection, &tables, &symbols).unwrap();
    assert_eq!(dmb.classes[area_id].layer_bits, native_area);
}

#[test]
fn invisibility_header_inherits_and_explicit_zero_reset_stays_visible() {
    let dmb = image();
    let mut parent = dmb.classes[0].clone();
    parent.set_normally_visible(false);
    let mut child = parent.clone();
    child.set_normally_visible(true);
    inherit_record(&parent, &mut child, &HashSet::new(), false, false).unwrap();
    assert!(!child.is_normally_visible());
    child.set_normally_visible(true);
    inherit_record(
        &parent,
        &mut child,
        &HashSet::from(["invisibility"]),
        false,
        false,
    )
    .unwrap();
    assert!(child.is_normally_visible());
    let mut own = HashSet::new();
    native_header_differences(&dmb, &child, &parent, &mut own);
    assert!(own.contains("invisibility"));
    assert_eq!(child.flags ^ parent.flags, 4);
}

#[test]
fn retained_header_selectors_bind_current_values_and_preserve_callback_bits() {
    let store = HeaderRecipes::default();
    let parent_recipe = Arc::new(header_recipes::HeaderRecipe {
        owner: b"/atom".to_vec(),
        authored_name: true,
        ..Default::default()
    });
    let authored = BTreeSet::from(["icon".to_owned(), "layer".to_owned()]);
    let (_, recipe) = store.obtain(
        b"/obj/example",
        &authored,
        &authored,
        authored.clone(),
        BTreeSet::new(),
        &parent_recipe,
    );
    for current in [30, 400] {
        let dmb = image();
        let mut parent = dmb.classes[0].clone();
        parent.initial_ids[2] = current;
        parent.initial_ids[4] = current + 1;
        parent.direction = 4;
        parent.set_mouse_opacity(0).unwrap();
        let mut actual = dmb.classes[0].clone();
        actual.initial_ids[4] = 99;
        actual.layer_bits = 8.0_f32.to_bits();
        let mut expected = actual.clone();
        inherit_record(
            &parent,
            &mut expected,
            &HashSet::from(["icon", "layer"]),
            true,
            false,
        )
        .unwrap();
        inherit_record_selected(&parent, &mut actual, |name| {
            recipe.inherited_fields.iter().any(|field| field == name)
        })
        .unwrap();
        assert_eq!(actual, expected);
        assert_eq!(actual.initial_ids[2], current);
        assert_eq!(actual.initial_ids[4], 99);
    }
}
#[test]
fn retained_builtin_selectors_bind_changed_current_values_in_original_merge_order() {
    let store = HeaderRecipes::default();
    for number in [7.0_f32, 11.0] {
        let mut ordinary = image();
        let mut pool = crate::composition::StringIndex::build(&ordinary).unwrap();
        let plane = pool.intern(&mut ordinary, b"plane").unwrap();
        let alpha = pool.intern(&mut ordinary, b"alpha").unwrap();
        let parent = ordinary.classes.len() as u32;
        let child = parent + 1;
        let record = ordinary.classes[0].clone();
        ordinary.classes.extend([record.clone(), record]);
        let value = |n: f32| byond_dmb::operands::Value {
            tag_word: 42,
            data_word: n.to_bits() >> 16,
            extra_word: Some(n.to_bits() & 0xffff),
        };
        let mut parent_words = vec![plane];
        parent_words.extend(value(number).encode());
        parent_words.push(alpha);
        parent_words.extend(value(2.0).encode());
        ordinary.classes[parent as usize].overrides =
            crate::composition::append_list(&mut ordinary, parent_words).unwrap();
        let mut own = vec![alpha];
        own.extend(value(4.0).encode());
        ordinary.classes[child as usize].overrides =
            crate::composition::append_list(&mut ordinary, own).unwrap();
        let mut retained = ordinary.clone();
        inherit_overrides(
            &mut ordinary,
            child,
            parent,
            &HashSet::from(["alpha"]),
            &HashSet::new(),
        )
        .unwrap();
        let mut keys = Vec::new();
        inherit_overrides_retained(
            &mut retained,
            child,
            parent,
            &HashSet::from(["alpha"]),
            &HashSet::new(),
            Some((&store, b"/obj/example")),
            &mut keys,
        )
        .unwrap();
        assert_eq!(retained.to_bytes().unwrap(), ordinary.to_bytes().unwrap());
        assert_eq!(
            retained.class_builtin_overrides(child as usize).unwrap()[0].value,
            value(number)
        );
        assert_eq!(keys.len(), 1);
    }
}
