use super::*;
#[test]
fn native_reserved_list_padding_preserves_code_and_argument_links_roundtrip() {
    let mut dmb =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    dmb.lists.resize(byond_dmb::ids::NONE as usize, Vec::new());
    let code = append_list(&mut dmb, vec![0]).unwrap();
    let locals = append_list(&mut dmb, Vec::new()).unwrap();
    let args = append_list(&mut dmb, Vec::new()).unwrap();
    assert_eq!([code, locals, args], [0x10000, 0x10001, 0x10002]);
    assert!(dmb.lists[0xffff].is_empty());
    dmb.procs[0].code_locals_args = [code, locals, args];
    dmb.header.flags |= 0x4000_0000;
    dmb.validate_references().unwrap();
    let decoded = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
    decoded.validate_references().unwrap();
    assert_eq!(decoded.procs[0].code_locals_args, [code, locals, args]);
    assert_eq!(decoded.proc_code_words(0), Some([0].as_slice()));
    assert!(decoded.lists[0xffff].is_empty());
}
#[test]
fn native_reserved_procedure_padding_roundtrips_and_preserves_next_proc() {
    let mut dmb =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    let template = dmb.procs[0].clone();
    dmb.procs
        .resize(byond_dmb::ids::NONE as usize, template.clone());
    reserve_procedure_sentinel(&mut dmb);
    assert!(dmb.is_reserved_proc_slot(byond_dmb::ids::NONE as usize));
    let count = dmb.procs.len();
    reserve_procedure_sentinel(&mut dmb);
    assert_eq!(dmb.procs.len(), count);
    dmb.procs.push(template.clone());
    dmb.header.flags |= 0x4000_0000;
    dmb.validate_references().unwrap();
    let decoded = Dmb::from_bytes(&dmb.to_bytes().unwrap()).unwrap();
    decoded.validate_references().unwrap();
    assert!(decoded.is_reserved_proc_slot(byond_dmb::ids::NONE as usize));
    assert_eq!(decoded.procs[0x10000], template);
}
#[test]
fn writer_string_interning_preserves_reserved_holes_and_safe_field_decoding() {
    let mut image =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    image.strings.resize(
        0xffcd,
        DmString {
            data: Vec::new(),
            long_chunks: 0,
        },
    );
    let mut pool = StringIndex::build(&image).unwrap();
    let first = pool.intern(&mut image, b"field_after_modifiers").unwrap();
    assert_eq!(first, 0xfff2);
    assert!(image.strings[0xffcd..=0xfff1]
        .iter()
        .all(|row| row.data.is_empty()));
    assert_eq!(
        byond_dmb::operands::Variable::decode(&[first]).unwrap(),
        (byond_dmb::operands::Variable::Field(first), 1)
    );
    image.strings.resize(
        0xffff,
        DmString {
            data: Vec::new(),
            long_chunks: 0,
        },
    );
    let second = pool.intern(&mut image, b"field_after_absent").unwrap();
    assert_eq!(second, 0x10000);
    assert!(image.strings[0xffff].data.is_empty());
    assert_eq!(
        byond_dmb::operands::Variable::decode(&[second]).unwrap(),
        (byond_dmb::operands::Variable::Field(second), 1)
    );
    let rebuilt = StringIndex::build(&image).unwrap();
    assert!(!rebuilt
        .buckets
        .values()
        .flatten()
        .any(|id| dm_link::is_reserved_string_index(*id)));
}
#[test]
fn map_initializer_attachment_coverage_uses_exact_index_and_domain() {
    let mut image =
        Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    assert!(!image.instances.is_empty());
    image.instances[0].initializer = 17;
    let index: HashSet<u32> = image
        .instances
        .iter()
        .map(|instance| instance.initializer)
        .collect();
    let key = Key::Initializer(dm_link::InitializerIdentity::Map {
        source: 1,
        descriptor: 2,
    });
    assert!(attached_key_present(&image, key, 17, &index));
    assert!(!attached_key_present(&image, key, 999_999, &index));
    assert!(!attached_key_present(
        &image,
        Key::Initializer(dm_link::InitializerIdentity::Global),
        17,
        &index
    ));
    assert!(attached_key_present(
        &image,
        Key::MapInstance {
            source: 1,
            descriptor: 2
        },
        0,
        &index
    ));
    assert!(!attached_key_present(
        &image,
        Key::MapInstance {
            source: 1,
            descriptor: 2
        },
        image.instances.len() as u32,
        &index
    ));
}
#[test]
fn every_captured_engine_named_procedure_binding_is_validated() {
    let bytes = include_bytes!("../../../../fixtures/native_template.bin");
    let engine = crate::engine::EngineSnapshot::from_bytes(bytes, 1).unwrap();
    let dmb = Dmb::from_bytes(bytes).unwrap();
    let links = crate::engine_link::capture(bytes, &engine).unwrap();
    for (key, index) in links.inventory.fixed {
        if !matches!(key, Key::Proc { .. } | Key::Verb { .. }) {
            continue;
        }
        let result = validate_binding(&dmb, key, index, engine.symbols(), None);
        let record = &dmb.procs[index as usize];
        assert!(
            result.is_ok(),
            "{result:?}; index={index}; strings={:?}; key={key:?}; layouts={:?}",
            record.strings.map(|id| dmb.string(id)),
            engine
                .procedure_layouts()
                .iter()
                .filter(|layout| layout.wire_proc == index)
                .map(|layout| (
                    engine.symbols().text(layout.owner),
                    layout.name.and_then(|name| engine.symbols().text(name)),
                    layout.kind
                ))
                .collect::<Vec<_>>()
        );
    }
}
#[test]
fn builtin_global_vars_uses_variable_record_domain_without_footer_allocation() {
    let bytes = include_bytes!(
        "../../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
    );
    let pinned = Dmb::from_bytes(bytes).unwrap();
    let record = pinned.variables.len() as u32;
    let mut inventory = dm_link::LinkInventory::default();
    inventory
        .reserved_prefixes
        .insert(dm_link::Table::VariableRecord, record);
    inventory.entries.push(dm_link::Entry {
        key: Key::BuiltinGlobalVars,
        content: std::sync::Arc::from(b"builtin-vars-kind82".as_slice()),
    });
    let batch = FrozenBatch {
        units: vec![],
        helpers: vec![],
        initializers: vec![],
        tables: dm_link::LinkTables::build(inventory).unwrap(),
    };
    let result = compose_global_fixture(bytes, &batch, &SymbolTable::default()).unwrap();
    let decoded = Dmb::from_bytes(&result).unwrap();
    assert_eq!(decoded.variables[record as usize].kind, 82);
    assert_eq!(
        decoded.string(decoded.variables[record as usize].name),
        Some(b"vars".as_slice())
    );
    assert_eq!(
        decoded.lists.get(decoded.variable_footer as usize),
        pinned.lists.get(pinned.variable_footer as usize)
    );
}
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &std::path::Path) -> Result<String, String> {
        Ok(self.0.into())
    }
}
fn frontend(source: &'static str) -> dm_tree::frontend::ColdFrontend {
    dm_tree::frontend::build(
        std::path::Path::new("project.dme"),
        &Source(source),
        &Default::default(),
        1,
    )
    .unwrap()
}
#[test]
fn full_source_admission_rejects_globals_classes_and_missing_bodies() {
    assert!(validate_global_program(&frontend("/var/x = 1\n")).is_err());
    assert!(validate_global_program(&frontend("/datum/x\n")).is_err());
    assert!(validate_global_program(&frontend("/datum/x/proc/read()\n    return 1\n")).is_err());
    let source = frontend("/proc/read()\n    return 1\n");
    assert!(validate_global_program(&source).is_ok());
    let batch = FrozenBatch {
        units: vec![],
        helpers: vec![],
        initializers: vec![],
        tables: dm_link::LinkTables::build(Default::default()).unwrap(),
    };
    assert!(
        matches!(compose_global_program(b"invalid",&batch,&source),Err(CompositionError::Unsupported(message)) if message.contains("coverage"))
    );
}

#[test]
fn real_pinned_image_composes_and_retains_external_feature_bit() {
    let engine = include_bytes!(
        "../../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
    );
    let batch = FrozenBatch {
        units: vec![],
        helpers: vec![],
        initializers: vec![],
        tables: dm_link::LinkTables::build(Default::default()).unwrap(),
    };
    let bytes = compose_global_fixture(engine, &batch, &SymbolTable::default()).unwrap();
    let decoded = Dmb::from_bytes(&bytes).unwrap();
    decoded.validate_references().unwrap();
    assert_ne!(decoded.header.flags & 0x2000_0000, 0);
    assert_eq!(
        decoded.procs.len(),
        Dmb::from_bytes(engine).unwrap().procs.len()
    );
}
#[test]
fn canonical_indexes_cannot_overwrite_pinned_strings() {
    let engine = include_bytes!(
        "../../../../fixtures/translation/client_header_probe/feature_load_ext.native.bin"
    );
    let mut symbols = SymbolTable::default();
    let wrong = symbols.intern("not-the-engine-string").unwrap();
    let inventory = dm_link::LinkInventory {
        entries: vec![dm_link::Entry {
            key: Key::String(wrong),
            content: std::sync::Arc::from(b"not-the-engine-string".as_slice()),
        }],
        spellings: vec![(
            wrong,
            std::sync::Arc::from(b"not-the-engine-string".as_slice()),
        )],
        ..Default::default()
    };
    let batch = FrozenBatch {
        units: vec![],
        helpers: vec![],
        initializers: vec![],
        tables: dm_link::LinkTables::build(inventory).unwrap(),
    };
    assert!(matches!(
        compose_global_fixture(engine, &batch, &symbols),
        Err(CompositionError::InvalidBinding(Key::String(_), 0))
    ));
}

#[test]
fn physical_procedure_namespace_preserves_declarations_and_implicit_overrides() {
    let mut symbols = SymbolTable::default();
    let owner = symbols.intern("/datum/probe").unwrap();
    let name = symbols.intern("work").unwrap();
    let root = symbols.intern("/").unwrap();
    let declared = proc_path(&symbols, owner, name, Namespace::Proc, true).unwrap();
    let overridden = proc_path(&symbols, owner, name, Namespace::Proc, false).unwrap();
    assert_eq!(declared, "/datum/probe/proc/work");
    assert_eq!(overridden, "/datum/probe/work");
    // Same callable name, different physical typesof namespace membership.
    assert!(declared.starts_with("/datum/probe/proc/"));
    assert!(!overridden.starts_with("/datum/probe/proc/"));
    assert_eq!(
        proc_path(&symbols, owner, name, Namespace::Verb, true).unwrap(),
        "/datum/probe/verb/work"
    );
    assert_eq!(
        proc_path(&symbols, owner, name, Namespace::Verb, false).unwrap(),
        "/datum/probe/work"
    );
    assert_eq!(
        proc_path(&symbols, root, name, Namespace::Proc, false).unwrap(),
        "/proc/work"
    );
}

#[test]
fn captured_override_chain_keeps_physical_namespace_and_super_occurrences_distinct() {
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/probe\n/datum/probe/proc/work()\n    return 1\n/datum/probe/work()\n    return ..() + 1\n".into())
        }
    }
    struct NoFields;
    impl crate::class_projection::CapturedFieldEvaluator for NoFields {
        fn evaluate(
            &self,
            _: SymbolId,
            _: &dm_ir::SymbolicExpression,
        ) -> Result<dm_ir::SemanticValue, String> {
            Err("fixture has no field initializers".into())
        }
    }
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("fixture.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 1,
            engine: None,
            observer: None,
        },
    )
    .unwrap();
    let plan =
        crate::class_projection::project(&frontend.snapshot, &frontend.emission_order, &NoFields)
            .unwrap();
    let chain = plan
        .chains
        .iter()
        .find(|chain| chain.name == SymbolId::of("work"))
        .unwrap();
    assert_eq!(chain.entries.len(), 2);
    let paths = chain
        .entries
        .iter()
        .map(|key| {
            let declared = *plan.procedure_declarations.get(key).unwrap();
            proc_path(
                frontend.snapshot.tree.symbols(),
                chain.owner,
                chain.name,
                Namespace::Proc,
                declared,
            )
            .unwrap()
        })
        .collect::<Vec<_>>();
    // The overriding body remains first; its ..() target retains the distinct
    // formal occurrence/key and explicit namespace identity underneath it.
    assert_eq!(paths, ["/datum/probe/work", "/datum/probe/proc/work"]);
    assert_ne!(chain.entries[0], chain.entries[1]);
}
