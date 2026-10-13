use super::*;

fn image(path: &[u8], verb: bool) -> Dmb {
    let mut dmb = Dmb::from_bytes(include_bytes!("../../../fixtures/native_template.bin")).unwrap();
    let id = dmb.strings.len() as u32;
    dmb.strings.push(byond_dmb::dmb::DmString {
        data: path.to_vec(),
        long_chunks: 0,
    });
    dmb.procs[0].strings[0] = id;
    let lists: BTreeSet<_> = dmb
        .classes
        .iter()
        .map(|class| class.verb_list_id())
        .collect();
    for list in lists {
        if let Some(row) = dmb.lists.get_mut(list as usize) {
            row.retain(|id| *id != 0);
        }
    }
    if verb {
        dmb.classes[0].lists_and_procs[0] = dmb.lists.len() as u32;
        dmb.lists.push(vec![0]);
    }
    dmb
}

#[test]
fn calls_and_reflective_values_use_canonical_proc_references() {
    let a = image(b"/datum/a/proc/f", false);
    let b = image(b"/datum/a/f", false);
    let a = NormalizationContext::new(&a);
    let b = NormalizationContext::new(&b);
    assert_eq!(a.reference_path(0), b.reference_path(0));
    let call = byond_dmb::bytecode::Instruction {
        offset: 0,
        opcode: 0x30,
        name: "CallGlob",
        operands: vec![2, 0],
    };
    assert_eq!(
        instruction(&a, &call).unwrap(),
        instruction(&b, &call).unwrap()
    );
    let reference = byond_dmb::operands::Value {
        tag_word: 38,
        data_word: 0,
        extra_word: None,
    };
    assert_eq!(value(&a, reference), value(&b, reference));
    for other in [
        b"/datum/b/f".as_slice(),
        b"/datum/a/g".as_slice(),
        b"/datum/a/verb/f".as_slice(),
    ] {
        let image = image(other, false);
        assert_ne!(
            a.reference_path(0),
            NormalizationContext::new(&image).reference_path(0)
        );
    }
}

#[test]
fn bare_current_verb_binding_preserves_namespace() {
    let explicit = image(b"/datum/a/verb/f", true);
    let bare = image(b"/datum/a/f", true);
    let ordinary = image(b"/datum/a/f", false);
    assert_eq!(
        NormalizationContext::new(&explicit).reference_path(0),
        NormalizationContext::new(&bare).reference_path(0)
    );
    assert_ne!(
        NormalizationContext::new(&ordinary).reference_path(0),
        NormalizationContext::new(&bare).reference_path(0)
    );
}
