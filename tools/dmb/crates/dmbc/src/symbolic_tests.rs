#[test]
fn debug_inventory_retains_first_path_encounter_without_duplicate_lines() {
    let origins = crate::debug_sources::DebugOrigins {
        entries: ["code/a.dm", "code/a.dm", "code/b.dm", "code/a.dm"]
            .iter()
            .enumerate()
            .map(|(line, path)| crate::debug_sources::DebugOrigin {
                semantic_path: (*path).into(),
                line: line as u32 + 1,
            })
            .collect(),
    };
    let mut inventory = dm_link::LinkInventory::default();
    let mut strings = StringInventory::new(&inventory);
    super::append_debug_inventory(&origins, &mut inventory, &mut strings);
    assert_eq!(inventory.entries.len(), 2);
    assert_eq!(inventory.spellings.len(), 2);
    assert_eq!(inventory.entries[0].content.as_ref(), b"code/a.dm");
    assert_eq!(inventory.entries[1].content.as_ref(), b"code/b.dm");
    assert_eq!(origins.entries.len(), 4);
}
use super::*;
use crate::lowering::{lower_frontend, AbiPolicy, LoweringConfig};
use dm_codegen_byond::ProcedureInputs;
use dm_ir::{ProcedureMetadata, ResolveQuery, ResolvedMeaning, Resolver};
use dm_tree::frontend::{ColdFrontend, SourceLocation};
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/read()\n    return \"hello\"\n".into())
    }
}
struct Host;
impl Resolver for Host {
    fn resolve(&self, query: ResolveQuery) -> ResolvedMeaning {
        ResolvedMeaning::Unsupported(query)
    }
}
struct Policy;
impl AbiPolicy for Policy {
    fn inputs(
        &self,
        _: UnitIdentity,
        metadata: &ProcedureMetadata,
        _: &SymbolTable,
        _: &SourceLocation,
    ) -> Result<ProcedureInputs, String> {
        if !metadata.signature.parameters.is_empty() {
            return Err("unsupported parameters".into());
        }
        Ok(ProcedureInputs::default())
    }
}
fn frontend() -> ColdFrontend {
    dm_tree::frontend::build(Path::new("project.dme"), &Source, &BTreeMap::new(), 1).unwrap()
}

#[test]
fn current_link_image_reuses_only_exact_code_tables_and_source_roster() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    let mut batch = freeze_and_link_tables(
        lowered,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let first = batch.link_unit(0, &SourceBindings::default()).unwrap();
    let second = batch.link_unit(0, &SourceBindings::default()).unwrap();
    assert!(
        Arc::ptr_eq(&first.words, &second.words),
        "current image should be borrowed through Arc, not relinked"
    );
    let direct = batch
        .tables
        .link(
            batch.units[0].frozen.code(),
            &batch.units[0].lowered.debug_origins.source_bindings(),
        )
        .unwrap();
    assert_eq!(first, direct);
    let mut override_source = batch.units[0].lowered.debug_origins.source_bindings();
    for line in override_source.lines.values_mut() {
        *line += 20;
    }
    let overridden = batch.link_unit(0, &override_source).unwrap();
    assert!(!Arc::ptr_eq(&first.words, &overridden.words));
    let decoded = byond_dmb::bytecode::decode(&overridden.words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.name == "DbgLine" && instruction.operands[0] >= 21));
    for origin in &mut batch.units[0].lowered.debug_origins.entries {
        origin.line += 30;
    }
    let moved = batch.link_unit(0, &SourceBindings::default()).unwrap();
    assert!(!Arc::ptr_eq(&first.words, &moved.words));
    let direct = batch
        .tables
        .link(
            batch.units[0].frozen.code(),
            &batch.units[0].lowered.debug_origins.source_bindings(),
        )
        .unwrap();
    assert_eq!(moved, direct);
    batch.tables = LinkTables::build(LinkInventory::default()).unwrap();
    assert!(
        batch.link_unit(0, &SourceBindings::default()).is_err(),
        "changed tables must not reuse old dense bindings"
    );
}
#[test]
fn current_proc_values_link_each_repeated_body_to_its_exact_occurrence() {
    struct Repeated;
    impl dm_preprocess::SourceProvider for Repeated {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/base/proc/current()\n    return __PROC__\n/datum/base/current()\n    return __PROC__\n".into())
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Repeated, &BTreeMap::new(), 1).unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    let startup = crate::startup::capture(&frontend).unwrap();
    let host = startup.resolver(&frontend, tree).unwrap();
    let lowered = lower_frontend(&frontend, &host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    assert_eq!(lowered.units.len(), 2);
    let frozen = freeze_and_link_tables(
        lowered,
        tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let mut indices = Vec::new();
    for (index, unit) in frozen.units.iter().enumerate() {
        let reference = unit_reference(unit.lowered.identity);
        assert!(unit
            .frozen
            .code()
            .relocations()
            .iter()
            .any(|site| site.reference == reference));
        let dense = frozen
            .tables
            .index(unit_key(unit.lowered.identity))
            .unwrap();
        indices.push(dense);
        let image = frozen.link_unit(index, &SourceBindings::default()).unwrap();
        assert!(byond_dmb::bytecode::decode(&image.words)
            .unwrap()
            .iter()
            .any(
                |instruction| instruction.name == "PushVal" && instruction.operands == [38, dense]
            ));
    }
    assert_ne!(indices[0], indices[1]);
}
#[test]
fn runtime_list_procedure_literal_keeps_formal_body_identity() {
    struct Procedures;
    impl dm_preprocess::SourceProvider for Procedures {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/base/proc/callback()\n    return 1\n/datum/base/callback()\n    return 2\n/proc/caller()\n    return list(/datum/base/proc/callback)\n".into())
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Procedures, &BTreeMap::new(), 1)
            .unwrap();
    let tree = frontend.snapshot.tree.as_ref();
    let query = |formal| {
        Resolver::resolve(
            tree,
            ResolveQuery::ProcedureValue {
                owner: SymbolId::of("/datum/base"),
                name: SymbolId::of("callback"),
                verb: false,
                formal,
            },
        )
    };
    let ResolvedMeaning::Value(dm_ir::SemanticValue::Procedure(formal)) = query(true) else {
        panic!("formal identity unavailable")
    };
    let ResolvedMeaning::Value(dm_ir::SemanticValue::Procedure(effective)) = query(false) else {
        panic!("effective identity unavailable")
    };
    assert_ne!(formal, effective);
    let lowered = lower_frontend(&frontend, tree, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    let frozen = freeze_and_link_tables(
        lowered,
        tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let caller = frozen
        .units
        .iter()
        .position(|unit| unit.lowered.identity.name == SymbolId::of("caller"))
        .unwrap();
    let expected = SymRef::Proc {
        owner: formal.owner,
        name: formal.name,
        occurrence: formal.occurrence,
    };
    assert!(frozen.units[caller]
        .frozen
        .code()
        .relocations()
        .iter()
        .any(|site| site.reference == expected));
    let index = frozen
        .tables
        .index(Key::Proc {
            owner: formal.owner,
            name: formal.name,
            occurrence: formal.occurrence,
        })
        .unwrap();
    let linked = frozen
        .link_unit(caller, &SourceBindings::default())
        .unwrap();
    let decoded = byond_dmb::bytecode::decode(&linked.words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.name == "PushVal" && instruction.operands == [38, index]));
    assert!(decoded
        .iter()
        .any(|instruction| instruction.name == "NewList"));
}
#[test]
fn implicit_before_formal_binds_the_certified_effective_body() {
    struct Reopened;
    impl dm_preprocess::SourceProvider for Reopened {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/x/read()\n    return 2\n/datum/x/proc/read()\n    return 1\n/proc/caller()\n    return /datum/x/proc/read\n".into())
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("project.dme"), &Reopened, &Default::default(), 1)
            .unwrap();
    let batch = lower_frontend(
        &frontend,
        frontend.snapshot.tree.as_ref(),
        &Policy,
        LoweringConfig::default(),
    );
    assert!(batch.diagnostics.is_empty(), "{:?}", batch.diagnostics);
    let read = SymbolId::of("read");
    let effective = batch
        .units
        .iter()
        .find(|unit| unit.identity.name == read && unit.effective)
        .unwrap()
        .identity;
    // Identities count semantic override depth: formal base is 0 even when
    // encountered later; the earlier authored implicit override is 1.
    assert_eq!(effective.occurrence, 1);
    let selected = batch
        .units
        .iter()
        .find(|unit| unit.identity == effective)
        .unwrap();
    let executable = selected
        .code
        .procedure
        .code
        .items
        .iter()
        .filter_map(|item| match item {
            dm_codegen_byond::Item::Instruction(instruction)
                if !matches!(instruction.opcode, 0x84 | 0x85) =>
            {
                Some(instruction)
            }
            _ => None,
        })
        .collect::<Vec<_>>();
    // Small nonnegative integers use PUSH_INT rather than compound V.
    assert_eq!(
        executable[0].opcode,
        byond_dmb::bytecode::opcode::PUSH_INT,
        "{:?}",
        selected.code.procedure.code
    );
    assert_eq!(
        executable[0].operands,
        vec![dm_codegen_byond::Word::Immediate(2)]
    );
    assert_eq!(executable[1].opcode, byond_dmb::bytecode::opcode::RET);
    let batch_formal = batch
        .units
        .iter()
        .find(|unit| unit.identity.name == read && !unit.effective)
        .unwrap()
        .identity;
    let frozen = freeze_and_link_tables(
        batch,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let caller = frozen
        .units
        .iter()
        .find(|unit| unit.lowered.identity.name == SymbolId::of("caller"))
        .unwrap();
    assert!(caller
        .frozen
        .code()
        .relocations()
        .iter()
        .any(|site| site.reference == unit_reference(batch_formal)));
}

#[test]
fn actual_lowered_string_body_freezes_and_links_without_legacy_ledger() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    let batch = freeze_and_link_tables(
        lowered,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    assert_eq!(batch.units.len(), 1);
    assert!(batch
        .tables
        .index(Key::String(SymbolId::of("hello")))
        .is_some());
    let original = batch.units[0].frozen.code().words().to_vec();
    let first = batch.link_unit(0, &SourceBindings::default()).unwrap();
    let second = batch.link_unit(0, &SourceBindings::default()).unwrap();
    assert_eq!(first, second);
    assert_eq!(batch.units[0].frozen.code().words(), original);
}
#[test]
fn captured_binding_conflict_fails_before_table_assignment() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    let mut bindings = ReferenceBindings::default();
    bindings.references.insert(
        Symbol::new(Table::String, "hello"),
        SymRef::String(SymbolId::of("wrong")),
    );
    assert!(matches!(
        freeze_and_link_tables(
            lowered,
            frontend.snapshot.tree.symbols(),
            &bindings,
            LinkInventory::default()
        ),
        Err(IntegrationError::Freeze { .. })
    ));
}

#[test]
fn certified_feature_facts_match_decoded_images_and_decline_changed_origins() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty());
    let mut batch = freeze_and_link_tables(
        lowered,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let index = batch
        .tables
        .index(unit_key(batch.units[0].lowered.identity))
        .unwrap();
    {
        let images = batch.feature_images();
        let &(words, features) = images.get(&index).unwrap();
        let decoded = byond_dmb::bytecode::decode(words).unwrap();
        assert_eq!(
            features.external,
            decoded
                .iter()
                .any(|instruction| matches!(instruction.name, "LoadExt" | "CallExt"))
        );
        assert_eq!(
            features.debug,
            decoded
                .iter()
                .any(|instruction| matches!(instruction.name, "DbgFile" | "DbgLine"))
        );
        assert!(features.debug);
        let mut altered = words.to_vec();
        altered[0] ^= 1;
        assert_ne!(
            words,
            altered.as_slice(),
            "composer only reuses features on exact words"
        );
    }
    batch.units[0].lowered.debug_origins.entries[0].line += 1;
    assert!(!batch.feature_images().contains_key(&index));
}

#[test]
fn feature_facts_inspect_instruction_boundaries_not_immediate_operands() {
    use byond_dmb::bytecode::opcode;
    use dm_codegen_byond::{Instruction, Item, SymbolicProc, Word};
    let ordinary = SymbolicProc {
        items: vec![Item::Instruction(Instruction {
            opcode: opcode::PUSH_INT,
            operands: vec![Word::Immediate(opcode::LOAD_EXT)],
        })],
    };
    assert_eq!(BytecodeFeatures::of(&ordinary), BytecodeFeatures::default());
    let features = SymbolicProc {
        items: vec![
            Item::Instruction(Instruction {
                opcode: opcode::LOAD_EXT,
                operands: vec![],
            }),
            Item::Instruction(Instruction {
                opcode: opcode::DBG_LINE,
                operands: vec![Word::Immediate(1)],
            }),
        ],
    };
    assert_eq!(
        BytecodeFeatures::of(&features),
        BytecodeFeatures {
            external: true,
            debug: true
        }
    );
}

#[test]
fn request_string_inventory_reuses_exact_bytes_and_preserves_conflicts() {
    let id = SymbolId::of("shared spelling");
    let mut inventory = LinkInventory::default();
    let mut strings = StringInventory::new(&inventory);
    for _ in 0..4096 {
        strings.append(&mut inventory, id, b"shared spelling");
    }
    assert_eq!(inventory.spellings.len(), 1);
    assert_eq!(inventory.entries.len(), 1);
    assert!(Arc::ptr_eq(
        &inventory.spellings[0].1,
        &inventory.entries[0].content
    ));
    let tables = LinkTables::build(inventory.clone()).unwrap();
    assert_eq!(tables.index(Key::String(id)), Some(0));
    // Physical engine content conflicts remain errors even when the spelling
    // already existed before this request's exact-string index was created.
    inventory.entries[0].content = Arc::from(b"different physical content".as_slice());
    let mut strings = StringInventory::new(&inventory);
    strings.append(&mut inventory, id, b"shared spelling");
    assert!(
        matches!(LinkTables::build(inventory), Err(dm_link::LinkError::ContentCollision(key)) if key == Key::String(id))
    );
}

#[test]
fn consuming_current_image_transfers_unique_words_and_invalidates_feature_receipt() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    let mut batch = freeze_and_link_tables(
        lowered,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let pointer = batch.units[0]
        .current_image
        .as_ref()
        .unwrap()
        .image
        .words
        .as_ptr();
    let expected = batch
        .tables
        .link(
            batch.units[0].frozen.code(),
            &batch.units[0].lowered.debug_origins.source_bindings(),
        )
        .unwrap();
    let words = batch
        .take_unit_image(0, &SourceBindings::default())
        .unwrap()
        .into_words();
    assert_eq!(words.as_ptr(), pointer);
    assert_eq!(words.as_slice(), expected.words.as_slice());
    assert!(batch.units[0].current_image.is_none());
    assert!(batch.feature_images().is_empty());
}

#[test]
fn consuming_changed_origins_relinks_instead_of_taking_stale_image() {
    let frontend = frontend();
    let lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    let mut batch = freeze_and_link_tables(
        lowered,
        frontend.snapshot.tree.symbols(),
        &ReferenceBindings::default(),
        LinkInventory::default(),
    )
    .unwrap();
    let retained = batch.link_unit(0, &SourceBindings::default()).unwrap();
    for origin in &mut batch.units[0].lowered.debug_origins.entries {
        origin.line += 50;
    }
    let expected = batch
        .tables
        .link(
            batch.units[0].frozen.code(),
            &batch.units[0].lowered.debug_origins.source_bindings(),
        )
        .unwrap();
    let image = batch
        .take_unit_image(0, &SourceBindings::default())
        .unwrap();
    assert_eq!(image, expected);
    assert!(!Arc::ptr_eq(&image.words, &retained.words));
    assert_ne!(image.words, retained.words);
    assert!(batch.units[0].current_image.is_none());
    batch.tables = LinkTables::build(LinkInventory::default()).unwrap();
    assert!(batch
        .take_unit_image(0, &SourceBindings::default())
        .is_err());
}

fn parallel_fixture() -> (ColdFrontend, Vec<LoweredUnit>) {
    struct Many;
    impl dm_preprocess::SourceProvider for Many {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok((0..17)
                .map(|i| format!("/proc/unit_{i}()\n    return \"shared\"\n"))
                .collect())
        }
    }
    let frontend =
        dm_tree::frontend::build(Path::new("parallel.dme"), &Many, &BTreeMap::new(), 1).unwrap();
    let mut lowered = lower_frontend(&frontend, &Host, &Policy, LoweringConfig::default());
    assert!(lowered.diagnostics.is_empty(), "{:?}", lowered.diagnostics);
    for unit in &mut lowered.units {
        // Inventory must preserve binary template payloads rather than their
        // UTF-8 symbolic keys, including companion artifacts and duplicates.
        let key = "parallel-template".to_owned();
        unit.code
            .procedure
            .strings
            .extend([key.clone(), key.clone()]);
        unit.code
            .procedure
            .format_templates
            .insert(key, vec![0xff, 0x16, b'X']);
        unit.source_helpers
            .push(crate::argument_sources::LoweredHelper {
                owner: unit.identity,
                argument: 0,
                code: unit.code.clone(),
                debug_origins: unit.debug_origins.clone(),
            });
    }
    (frontend, lowered.units)
}
#[test]
fn parallel_freeze_preserves_tables_code_helpers_and_debug_at_one_two_eight_workers() {
    let (frontend, units) = parallel_fixture();
    let freeze = |workers| {
        freeze_artifact_tables_with_workers(
            LoweringBatch {
                units: units.clone(),
                diagnostics: Vec::new(),
            },
            frontend.snapshot.tree.symbols(),
            &ReferenceBindings::default(),
            LinkInventory::default(),
            Vec::new(),
            workers,
        )
        .unwrap()
    };
    let baseline = freeze(1);
    assert_eq!(
        baseline
            .tables
            .content(Key::String(SymbolId::of_bytes(&[0xff, 0x16, b'X']))),
        Some(&[0xff, 0x16, b'X'][..])
    );
    for workers in [2, 8] {
        let current = freeze(workers);
        assert_eq!(current.tables.assignments(), baseline.tables.assignments());
        assert_eq!(current.units.len(), baseline.units.len());
        assert_eq!(current.helpers.len(), baseline.helpers.len());
        for &key in baseline.tables.assignments().keys() {
            assert_eq!(current.tables.content(key), baseline.tables.content(key));
        }
        for (index, (left, right)) in baseline.units.iter().zip(&current.units).enumerate() {
            assert_eq!(left.lowered.identity, right.lowered.identity);
            assert_eq!(left.lowered.debug_origins, right.lowered.debug_origins);
            assert_eq!(
                baseline.link_unit(index, &Default::default()).unwrap(),
                current.link_unit(index, &Default::default()).unwrap()
            );
        }
        for (left, right) in baseline.helpers.iter().zip(&current.helpers) {
            assert_eq!((left.owner, left.argument), (right.owner, right.argument));
            assert_eq!(left.debug_origins, right.debug_origins);
            assert_eq!(
                baseline.link_helper(left).unwrap(),
                current.link_helper(right).unwrap()
            );
        }
    }
}
#[test]
fn parallel_freeze_returns_first_source_error_even_when_later_tasks_fail() {
    let (frontend, mut units) = parallel_fixture();
    let first = units[0].identity;
    units[0].source_helpers[0].owner = units[1].identity;
    units[2].code.procedure.code.items = vec![dm_codegen_byond::Item::Instruction(
        dm_codegen_byond::Instruction {
            opcode: u32::MAX,
            operands: Vec::new(),
        },
    )];
    for workers in [1, 2, 8] {
        let result = freeze_artifact_tables_with_workers(
            LoweringBatch {
                units: units.clone(),
                diagnostics: Vec::new(),
            },
            frontend.snapshot.tree.symbols(),
            &ReferenceBindings::default(),
            LinkInventory::default(),
            Vec::new(),
            workers,
        );
        match result {
            Err(IntegrationError::Freeze { unit, message }) => {
                assert_eq!(unit, first);
                assert_eq!(message, "invalid companion owner/formal frame");
            }
            _ => panic!("expected the first source-order helper error"),
        }
    }
}
