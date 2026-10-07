use crate::{cold::*, engine::EngineSnapshot, engine_host::*, lowering::LoweringConfig};
use std::path::Path;

struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(concat!(
            "/obj/wcoat\n",
            "/datum/modifier_base\n",
            "    var/list/accessories\n    var/amount = 0\n",
            "    var/static/shared = 0\n    var/const/fixed = 0\n",
            "/datum/modifier_holder\n",
            "    var/list/datum/modifier_base/typed_items = new()\n",
            "    var/preset = /datum/modifier_base{accessories=list(/obj/wcoat);amount=1;shared=2;fixed=3}\n",
            "/proc/modified_first()\n",
            "    return (/datum/modifier_base{fixed=3;shared=2;amount=1;accessories=list(/obj/wcoat)})\n",
            "/proc/modified_repeated()\n",
            "    return (/datum/modifier_base{amount=1;amount=2})\n",
        ).into())
    }
}

#[test]
fn actual_cold_modified_descriptors_keep_type_dedup_and_src_override_writes() {
    let bytes = include_bytes!("../../../fixtures/native_template.bin");
    let engine = EngineSnapshot::from_bytes(bytes, 1)
        .unwrap()
        .with_bootstrap_catalog()
        .unwrap();
    let seed = engine.frontend_seed();
    let frontend = dm_tree::frontend::build_with_config(
        Path::new("project.dme"),
        &Source,
        &Default::default(),
        dm_tree::frontend::FrontendConfig {
            workers: 2,
            engine: Some(&seed),
            observer: None,
        },
    )
    .unwrap();
    let mut symbols = frontend.snapshot.tree.symbols().clone();
    let constants = ConstantCatalog::native_516_1687(&mut symbols).unwrap();
    let runtime = RuntimeAliasCatalog::new(
        engine.identity(),
        &symbols,
        vec![],
        frontend
            .snapshot
            .tree
            .types()
            .iter()
            .map(|node| node.path)
            .collect(),
        Completeness::Partial,
    )
    .unwrap();
    let host = EngineResolverHost::new(frontend.snapshot.tree.clone(), constants, runtime)
        .with_pinned_callables(&engine, &frontend)
        .unwrap()
        .with_pinned_variables(&engine, &frontend)
        .unwrap();
    let evaluator = crate::driver_facts::DriverEvaluator {
        resolver: &host,
        symbols: &symbols,
        resource_search_context: None,
        pure_calls: None,
    };
    let types = crate::type_values::CapturedTypeValues::pinned(&frontend, &engine).unwrap();
    let links = crate::engine_link::capture(bytes, &engine).unwrap();
    let order = crate::type_creation_order::collect(
        &frontend.allocation_ledger,
        &frontend.expanded.text,
        frontend.snapshot.tree.symbols(),
        &links.inventory,
    )
    .unwrap();
    let output = compile_captured_classified_with_pinned_abi(
        &frontend,
        &host,
        CapturedLinkInputs {
            engine_bytes: bytes,
            engine: &engine,
            references: &links.references,
            inventory: links.inventory,
        },
        CapturedDeclarationInputs {
            initializers: &evaluator,
            type_values: &types,
            resource_search_context: None,
            source_type_order: &order,
        },
        LoweringConfig {
            workers: 2,
            max_chunk: 1,
        },
        vec![],
        None,
    )
    .unwrap();
    let image = byond_dmb::dmb::Dmb::from_bytes(&output.dmb).unwrap();
    image.validate_references().unwrap();
    assert!(!image.classes.iter().any(|class| image.string(class.path_string_id()) == Some(b"/list/datum/modifier_base")),
        "authored list element hints must not become synthetic runtime classes");
    assert!(
        !image
            .classes
            .iter()
            .any(|class| image.string(class.path_string_id()) == Some(b"/list")),
        "native primitive list values have no class table row"
    );
    let holder = image
        .classes
        .iter()
        .find(|class| image.string(class.path_string_id()) == Some(b"/datum/modifier_holder"))
        .unwrap();
    let words = image
        .proc_code_words(holder.initializer_proc_id() as usize)
        .unwrap();
    let constructor = byond_dmb::bytecode::decode(&words).unwrap();
    assert!(constructor
        .iter()
        .any(|instruction| instruction.name == "New"));
    assert!(
        constructor
            .iter()
            .any(|instruction| instruction.name == "PushVal" && instruction.operands == [40, 0]),
        "implicit constructor must use the native list primitive operand"
    );
    let original = image
        .classes
        .iter()
        .position(|class| image.string(class.path_string_id()) == Some(b"/datum/modifier_base"))
        .unwrap() as u32;
    assert!(!image.classes.iter().any(|class| image
        .string(class.path_string_id())
        .is_some_and(|name| name.windows(17).any(|text| text == b"modified-instance"))));
    let descriptors = image
        .instances
        .iter()
        .enumerate()
        .filter(|(_, value)| value.class == original && value.kind == 32)
        .collect::<Vec<_>>();
    assert_eq!(
        descriptors.len(),
        2,
        "reordered equivalent fields share one descriptor; repeated writes differ"
    );
    let preset = image
        .variables
        .iter()
        .find(|variable| image.string(variable.name) == Some(b"preset"))
        .unwrap();
    assert_eq!(
        preset.kind, 41,
        "modified literal is a stored type descriptor default, not a null runtime placeholder"
    );
    assert!(descriptors
        .iter()
        .any(|(index, _)| preset.value == *index as u32));
    let mut lengths = vec![];
    for (_, descriptor) in &descriptors {
        let words = image
            .proc_code_words(descriptor.initializer as usize)
            .unwrap();
        let decoded = byond_dmb::bytecode::decode(&words).unwrap();
        let setters = decoded
            .iter()
            .filter(|instruction| instruction.name == "SetVar")
            .collect::<Vec<_>>();
        lengths.push(setters.len());
        for setter in setters {
            assert_eq!(
                &setter.operands[..2],
                &[65500, 65486],
                "modified fields use receiver setters even for static/const"
            );
        }
    }
    lengths.sort();
    assert_eq!(lengths, [2, 4]);
    let proc_id = image
        .procs
        .iter()
        .position(|proc| image.string(proc.strings[0]) == Some(b"/proc/modified_first"))
        .expect("source procedure must retain its exact canonical path");
    assert_eq!(
        image.string(image.procs[proc_id].strings[1]),
        Some(&b"modified first"[..]),
        "display metadata uses the native underscore-to-space default"
    );
    let words = image.proc_code_words(proc_id).unwrap();
    let decoded = byond_dmb::bytecode::decode(&words).unwrap();
    assert!(decoded
        .iter()
        .any(|instruction| instruction.name == "PushVal"
            && instruction.operands.first() == Some(&41)
            && descriptors
                .iter()
                .any(|(index, _)| instruction.operands.get(1) == Some(&(*index as u32)))));
}
