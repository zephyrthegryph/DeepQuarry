use super::*;
#[test]
fn cache_value_and_conditional_fallthrough_are_bounded() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let field = dmb.variables.first().unwrap().name;
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let instructions = vec![
        make(0, 0x33, "GetVar", Variable::World.encode()),
        make(2, 0x142, "PushCache", vec![]),
        make(3, 0x34, "SetVar", Variable::Cache.encode()),
        make(5, 0x11, "Jz", vec![20]),
        make(7, 0x33, "GetVar", Variable::Field(field).encode()),
        make(9, 0x29, "Call", {
            let mut words = Variable::SetCache(
                Box::new(Variable::Field(field)),
                Box::new(Variable::DynamicProc(field)),
            )
            .encode();
            words.push(0);
            words
        }),
        make(12, 0x33, "GetVar", Variable::Field(field).encode()),
        make(20, 0x33, "GetVar", Variable::Field(field).encode()),
    ];
    let empty = HashSet::new();
    let result = references(&dmb, &instructions, &[], &empty, &empty);
    let owner = Place::Root("World".into());
    assert_eq!(
        result[4],
        Some(vec![Some(Place::Field(
            Box::new(owner),
            dmb.string(field).unwrap().to_vec()
        ))])
    );
    assert_eq!(result[6], Some(vec![None]), "a call invalidates ownership");
    assert_eq!(
        result[7],
        Some(vec![None]),
        "the branch destination invalidates ownership"
    );
    let joined = vec![
        instructions[0].clone(),
        instructions[1].clone(),
        instructions[2].clone(),
        instructions[3].clone(),
        instructions[4].clone(),
        instructions[7].clone(),
    ];
    let joined_refs = references(&dmb, &joined, &[], &empty, &empty);
    assert_eq!(
        joined_refs[5], joined_refs[4],
        "identical forward branch/fallthrough ownership survives the meet"
    );
}
#[test]
fn numeric_alignment_rejects_changed_values() {
    let push = |opcode, operands| Instruction {
        offset: 0,
        opcode,
        name: "push",
        operands,
    };
    assert!(same_cache_step(
        &push(0x50, vec![7]),
        &push(0x60, vec![42, 7f32.to_bits()])
    ));
    assert!(!same_cache_step(
        &push(0x50, vec![7]),
        &push(0x60, vec![42, 8f32.to_bits()])
    ));
}
#[test]
fn native_paired_calls_retain_src_world_but_not_derived_owners() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/cache_call_context.bin"
    ))
    .unwrap();
    let empty = HashSet::new();
    for id in [1, 2, 4] {
        let instructions = code(&dmb, id).unwrap();
        let refs = references(&dmb, &instructions, &[], &empty, &empty);
        assert_eq!(
            refs[0], refs[4],
            "native call context {id} must retain its root receiver"
        );
        assert!(refs[4].as_ref().unwrap()[0].is_some());
    }
    let constructor = code(&dmb, 5).unwrap();
    let refs = references(&dmb, &constructor, &[], &empty, &empty);
    assert_eq!(
        refs[0], refs[5],
        "native New preserves the caller's Src binding"
    );
    let constructor_args = code(&dmb, 6).unwrap();
    let refs = references(&dmb, &constructor_args, &[], &empty, &empty);
    assert_eq!(refs[0], refs[8], "native NewArgList preserves Src");
    let argument = code(&dmb, 7).unwrap();
    let refs = references(&dmb, &argument, &[], &empty, &empty);
    assert_eq!(
        refs[0], refs[4],
        "a non-exposed argument binding survives the call"
    );
    let exposed = code(&dmb, 8).unwrap();
    let refs = references(&dmb, &exposed, &[], &empty, &empty);
    assert_eq!(
        refs[5],
        Some(vec![None]),
        "an exposed argument list remains unproved"
    );
    let local = code(&dmb, 9).unwrap();
    let names = vec![b"B".to_vec(), b"a".to_vec()];
    let unique = names.iter().cloned().collect();
    let refs = references(&dmb, &local, &names, &unique, &empty);
    assert_eq!(
        refs[2], refs[6],
        "a uniquely named single-write local receiver survives the call"
    );
    let list_set = code(&dmb, 10).unwrap();
    let names = vec![b"B".to_vec(), b"a".to_vec(), b"L".to_vec()];
    let unique = names.iter().cloned().collect();
    let refs = references(&dmb, &list_set, &names, &unique, &empty);
    assert_eq!(
        refs[2], refs[10],
        "native stack ListSet retains the immutable local receiver"
    );
    let mut spawned = local.clone();
    spawned.push(Instruction {
        offset: 100,
        opcode: 0x25,
        name: "Spawn",
        operands: vec![101],
    });
    assert!(
        stable_bindings(&spawned, &names, &unique).is_empty(),
        "spawned shared writes prevent the immutable-binding proof"
    );
    let mut state = State {
        cache: Some(Place::Field(
            Box::new(Place::Root("Src".into())),
            b"child".to_vec(),
        )),
        frames: vec![],
        top_value: None,
        cache_key: None,
        locals: &[],
        unique_locals: &empty,
        unique_globals: &empty,
        stable_bindings: HashSet::new(),
    };
    state.call_boundary();
    assert!(state.cache.is_none(), "callee may replace src.child");
    state.cache = Some(Place::Root("Usr".into()));
    state.call_boundary();
    assert!(
        state.cache.is_none(),
        "usr persistence is deliberately unproved"
    );
    state.cache = Some(Place::Field(
        Box::new(Place::Root("Src".into())),
        b"child".to_vec(),
    ));
    state.write(Some(&Place::Field(
        Box::new(Place::Root("arg:0".into())),
        b"child".to_vec(),
    )));
    assert!(
        state.cache.is_none(),
        "arg0 may alias src and replace the derived child receiver"
    );
}
#[test]
fn forward_diamond_requires_every_receiver_to_agree() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let field = dmb.variables.first().unwrap().name;
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let mut instructions = vec![
        make(
            0,
            0x33,
            "GetVar",
            Variable::SetCache(Box::new(Variable::World), Box::new(Variable::Field(field)))
                .encode(),
        ),
        make(5, 0x11, "Jz", vec![20]),
        make(7, 0x33, "GetVar", Variable::Field(field).encode()),
        make(9, 0xf, "Jmp", vec![30]),
        make(20, 0x33, "GetVar", Variable::Field(field).encode()),
        make(22, 0x33, "GetVar", Variable::Field(field).encode()),
        make(30, 0x33, "GetVar", Variable::Field(field).encode()),
    ];
    let empty = HashSet::new();
    let refs = references(&dmb, &instructions, &[], &empty, &empty);
    assert_eq!(
        refs[0], refs[4],
        "unconditional jump has no fallthrough into the else arm"
    );
    assert_eq!(refs[0], refs[6], "all incoming World receivers agree");
    instructions[5].operands =
        Variable::SetCache(Box::new(Variable::Arg(0)), Box::new(Variable::Field(field))).encode();
    let refs = references(&dmb, &instructions, &[], &empty, &empty);
    assert_eq!(
        refs[6],
        Some(vec![None]),
        "a conflicting receiver invalidates the diamond join"
    );
}
#[test]
fn duplicate_local_definition_mapping_is_bijective_and_detects_misreads() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let native = vec![
        make(0, 0x50, "PushInt", vec![1]),
        make(2, 0x34, "SetVar", Variable::Local(0).encode()),
        make(5, 0x50, "PushInt", vec![2]),
        make(7, 0x34, "SetVar", Variable::Local(1).encode()),
        make(10, 0x33, "GetVar", Variable::Local(0).encode()),
        make(13, 0x33, "GetVar", Variable::Local(1).encode()),
    ];
    let mut translated = native.clone();
    for index in [1, 4] {
        translated[index].operands = Variable::Local(1).encode();
    }
    for index in [3, 5] {
        translated[index].operands = Variable::Local(0).encode();
    }
    let mut nl = vec![b"value".to_vec(); 2];
    let mut tl = nl.clone();
    disambiguate_local_definitions(&native, &translated, &mut nl, &mut tl);
    assert_eq!(nl[0], tl[1]);
    assert_eq!(nl[1], tl[0]);
    assert_ne!(nl[0], nl[1]);
    let unique = nl.iter().cloned().collect();
    let empty = HashSet::new();
    let nr = references(&dmb, &native, &nl, &unique, &empty);
    let tr = references(&dmb, &translated, &tl, &unique, &empty);
    assert_eq!(nr[4], tr[4]);
    translated[4].operands = Variable::Local(0).encode();
    let tr = references(&dmb, &translated, &tl, &unique, &empty);
    assert_ne!(
        nr[4], tr[4],
        "slot renaming must not hide a wrong receiver read"
    );
    let mut incomplete = native.clone();
    incomplete[3] = make(7, 0x51, "Pop", vec![]);
    let mut nl = vec![b"value".to_vec(); 2];
    let mut tl = nl.clone();
    disambiguate_local_definitions(&incomplete, &incomplete, &mut nl, &mut tl);
    assert_eq!(
        nl[0], nl[1],
        "an unwritten ambiguous slot keeps the entire group unknown"
    );
}
#[test]
fn cache_key_write_is_a_register_target_but_index_write_needs_provenance() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let instructions = vec![
        Instruction {
            offset: 0,
            opcode: 0x34,
            name: "SetVar",
            operands: Variable::CacheKey.encode(),
        },
        Instruction {
            offset: 2,
            opcode: 0x34,
            name: "SetVar",
            operands: Variable::CacheIndex.encode(),
        },
    ];
    let empty = HashSet::new();
    let refs = references(&dmb, &instructions, &[], &empty, &empty);
    assert_eq!(
        refs[0],
        Some(vec![Some(Place::Root("CacheKeyRegister".into()))])
    );
    assert_eq!(
        refs[1],
        Some(vec![None]),
        "the computed list element is not a fixed register target"
    );
}
#[test]
fn whole_body_method_check_requires_actual_name_and_proc_verb_mode() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let id = dmb
        .procs
        .iter()
        .position(|proc| {
            dmb.string(proc.strings[1])
                .is_some_and(|name| !name.is_empty())
        })
        .unwrap();
    let display = dmb.procs[id].strings[1];
    assert_eq!(
        method_selector_name(&dmb, &Variable::StaticProc(id as u32)),
        method_selector_name(&dmb, &Variable::DynamicProc(display))
    );
    assert_ne!(
        method_selector_name(&dmb, &Variable::DynamicProc(display)),
        method_selector_name(&dmb, &Variable::DynamicVerb(display))
    );
    let different = if display == 1 { 2 } else { 1 };
    assert_ne!(
        method_selector_name(&dmb, &Variable::DynamicProc(display)),
        method_selector_name(&dmb, &Variable::DynamicProc(different))
    );
    assert!(method_selector_name(&dmb, &Variable::StaticProc(u32::MAX)).is_none());
}

#[test]
fn safe_owner_fallthrough_requires_a_getter_and_null_joins_remain_unknown() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let field = dmb.variables[0].name;
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let empty = HashSet::new();
    for opcode in [0x13d, 0x13e] {
        let mut code = vec![
            make(0, 0x33, "GetVar", Variable::Arg(0).encode()),
            make(3, opcode, "safe-owner", vec![20]),
            make(5, 0x33, "GetVar", Variable::Field(field).encode()),
            make(7, 0xf, "Jmp", vec![30]),
            make(20, 0x33, "GetVar", Variable::Field(field).encode()),
            make(30, 0x33, "GetVar", Variable::Field(field).encode()),
        ];
        let refs = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(
            refs[2],
            Some(vec![Some(Place::Field(
                Box::new(Place::Root("arg:0".into())),
                dmb.string(field).unwrap().to_vec()
            ))])
        );
        assert_eq!(
            refs[4],
            Some(vec![None]),
            "null target does not receive the non-null owner proof"
        );
        assert_eq!(
            refs[5],
            Some(vec![None]),
            "a shared null/non-null join remains unresolved"
        );
        code.insert(1, make(2, 0x30, "CallGlob", vec![0, 0]));
        let interrupted = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(
            interrupted[3],
            Some(vec![None]),
            "an intervening call breaks the immediate-getter proof"
        );
    }
}

#[test]
fn typed_dispatch_snapshots_actual_owner_and_rejects_conflicting_shared_joins() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let field = dmb.variables[0].name;
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let empty = HashSet::new();
    for (opcode, table) in [
        (0x78, vec![1, 42, 0, 0, 20, 30]),
        (0x79, vec![1, 32767, 20, 30]),
        (0x7a, vec![1, 42, 0, 0, 42, 16256, 0, 20, 0, 30]),
        (0xb1, vec![2, 20, 30]),
    ] {
        let mut code = vec![
            make(
                0,
                0x33,
                "GetVar",
                Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(field)))
                    .encode(),
            ),
            // The dispatch snapshots this later weight/key receiver, not
            // the original Src selected before expression evaluation.
            make(
                5,
                0x33,
                "GetVar",
                Variable::SetCache(Box::new(Variable::Arg(0)), Box::new(Variable::Field(field)))
                    .encode(),
            ),
            make(10, opcode, "dispatch", table),
            make(20, 0x33, "GetVar", Variable::Field(field).encode()),
            make(22, 0xf, "Jmp", vec![40]),
            make(30, 0x33, "GetVar", Variable::Field(field).encode()),
            make(32, 0xf, "Jmp", vec![40]),
            make(40, 0x33, "GetVar", Variable::Field(field).encode()),
        ];
        let refs = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(refs[1], refs[3], "case entry retains actual selected Arg0");
        assert_eq!(
            refs[1], refs[5],
            "default entry has the same dispatch snapshot"
        );
        assert_eq!(refs[1], refs[7], "agreeing arms meet at the shared join");
        code[5].operands =
            Variable::SetCache(Box::new(Variable::World), Box::new(Variable::Field(field)))
                .encode();
        let conflict = references(&dmb, &code, &[], &empty, &empty);
        assert_eq!(
            conflict[7],
            Some(vec![None]),
            "conflicting arm receivers invalidate the join"
        );
    }
}

#[test]
fn adjacent_constant_index_setup_requires_the_same_list_and_key() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let fields = [dmb.variables[0].name, dmb.variables[1].name];
    assert_ne!(dmb.string(fields[0]), dmb.string(fields[1]));
    assert_ne!(dmb.string(1), dmb.string(2));
    let make = |field, key, interrupted| {
        let mut words = vec![0x33];
        words.extend(
            Variable::SetCache(Box::new(Variable::Src), Box::new(Variable::Field(field))).encode(),
        );
        words.extend([0x60, 6, key]);
        if interrupted {
            words.extend([0x30, 0, 0]);
        }
        words.push(0x34);
        words.extend(Variable::CacheKey.encode());
        words.push(0x34);
        words.extend(Variable::Cache.encode());
        words.push(0x33);
        words.extend(Variable::CacheIndex.encode());
        bytecode::decode(&words).unwrap()
    };
    let empty = HashSet::new();
    let resolved = |field, key, interrupted| {
        references(&dmb, &make(field, key, interrupted), &[], &empty, &empty)
            .last()
            .unwrap()
            .clone()
    };
    let reference = resolved(fields[0], 1, false);
    assert!(matches!(&reference, Some(values) if matches!(&values[0], Some(Place::Index(_, _)))));
    assert_eq!(reference, resolved(fields[0], 1, false));
    assert_ne!(
        reference,
        resolved(fields[0], 2, false),
        "changed constant keys must differ"
    );
    assert_ne!(
        reference,
        resolved(fields[1], 1, false),
        "changed list getters must differ"
    );
    assert_eq!(
        resolved(fields[0], 1, true),
        Some(vec![None]),
        "an intervening call breaks the bounded stack proof"
    );
}

#[test]
fn loop_owner_invariant_requires_a_known_preheader_and_unchanged_body() {
    let dmb = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let field = Variable::Field(0);
    let make = |offset, opcode, name, operands| Instruction {
        offset,
        opcode,
        name,
        operands,
    };
    let mut code = vec![
        make(
            0,
            0x33,
            "GetVar",
            Variable::SetCache(Box::new(Variable::Src), Box::new(field.clone())).encode(),
        ),
        make(5, 0x11, "Jz", vec![30]),
        make(7, 0x33, "GetVar", field.clone().encode()),
        make(20, 0xf, "Jmp", vec![5]),
        make(30, 0, "End", vec![]),
    ];
    let empty = HashSet::new();
    let known = references(&dmb, &code, &[], &empty, &empty);
    assert!(known[2].as_ref().unwrap()[0].is_some());
    code.insert(
        3,
        make(
            10,
            0x33,
            "GetVar",
            Variable::SetCache(Box::new(Variable::Arg(0)), Box::new(field.clone())).encode(),
        ),
    );
    let conflict = references(&dmb, &code, &[], &empty, &empty);
    assert_eq!(
        conflict[2],
        Some(vec![None]),
        "different backedge owner must invalidate the header"
    );
    code.remove(3);
    code[0].operands = field.encode();
    let unseeded = references(&dmb, &code, &[], &empty, &empty);
    assert_eq!(
        unseeded[2],
        Some(vec![None]),
        "entry cache is never assumed Src"
    );
}
#[test]
fn captured_method_result_requires_same_site_receiver_name_and_literal_argument() {
    let dmb = Dmb::from_bytes(include_bytes!(
        "../fixtures/lowering/cache_call_context.bin"
    ))
    .unwrap();
    let empty = HashSet::new();
    let name = dmb.procs[1].strings[1];
    let argument = dmb.procs[2].strings[0];
    let field = dmb.procs[1].strings[0];
    let words = vec![
        0x60, 6, argument, 0x29, 0xffdc, 0xffce, 0xffdd, name, 1, 0x34, 0xffd8, 0x33, field,
    ];
    let resolve = |words: &[u32]| {
        let instructions = bytecode::decode(words).unwrap();
        references(&dmb, &instructions, &[], &empty, &empty)
            .last()
            .cloned()
            .unwrap()
    };
    let known = resolve(&words);
    assert!(matches!(known.as_ref().unwrap().as_slice(),
            [Some(Place::Field(owner, _))] if matches!(owner.as_ref(), Place::CallResult(1, _, false, _, _))));
    let mut changed_name = words.clone();
    changed_name[7] = argument;
    assert_ne!(resolve(&changed_name), known);
    let mut changed_argument = words.clone();
    changed_argument[2] = name;
    assert_ne!(resolve(&changed_argument), known);
    let mut changed_owner = words.clone();
    changed_owner[5] = 0xffcf;
    assert_ne!(resolve(&changed_owner), known);
    let mut interrupted = words.clone();
    interrupted.splice(9..9, [0x51]);
    assert_eq!(resolve(&interrupted), Some(vec![None]));
    let mut joined = words.clone();
    joined.splice(9..9, [0x11, 11]);
    assert_eq!(resolve(&joined), Some(vec![None]));
    let mut non_literal = words.clone();
    non_literal.splice(0..3, [0x33, 0xffd9, 0]);
    assert_eq!(resolve(&non_literal), Some(vec![None]));
}
