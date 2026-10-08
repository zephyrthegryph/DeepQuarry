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
