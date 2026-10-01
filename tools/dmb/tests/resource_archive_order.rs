use byond_dmb::{
    dmb::Dmb,
    opendream::OpenDreamProgram,
    rsc::{read_all, Entry},
    translate::translate_named_debug,
};
use std::path::Path;

type Signature = (u8, u32, Vec<u8>, u32, Vec<u8>);
fn signatures(entries: &[Entry]) -> Vec<Signature> {
    entries
        .iter()
        .map(|entry| match entry {
            Entry::Named(resource) => (
                resource.kind,
                resource.id,
                resource.name.clone(),
                resource.declared_size,
                resource.data.clone(),
            ),
            Entry::Opaque { .. } => {
                panic!("fresh fixture unexpectedly contains an opaque RSC entry")
            }
        })
        .collect()
}

#[test]
fn authored_resource_phases_preserve_complete_native_archive_order() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/resource_archive_order");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let mut comparisons = 0;
    for name in [
        "siblings_reopen",
        "parent_late",
        "global_proc_after_class",
        "global_new_forward",
        "const_static_procstatic",
        "dms_first",
        "skin_dms",
        "dms_map",
        "explicit_root",
        "ast_containers",
        "ancestor_subtrees",
        "parent_late_siblings",
        "parent_early_siblings",
        "cross_native_roots",
        "late_explicit_root",
        "reparent_next_pass",
        "explicit_lexical_parent",
        "reparent_parent_late",
        "implicit_parent_middle",
        "first_resource_body",
        "procedure_group_first",
        "field_group_first",
        "reparented_procedure_group",
        "reparented_descendants",
        "client_procedure_namespaces",
        "bare_method_empty_phase",
        "field_override_sequence",
        "empty_variable_namespace",
        "relative_variable_phase",
        "relative_typed_variable_phase",
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        assert!(
            input.native_resource_archive_order.is_some(),
            "{name}: actual exporter annotation"
        );
        let archive = read_all(&mut std::io::Cursor::new(
            std::fs::read(fixtures.join(format!("{name}.native.rsc.bin"))).unwrap(),
        ))
        .unwrap();
        let expected = signatures(&archive);
        assert!(expected.len() >= 2, "{name}: nonvacuous ordered archive");
        for debug in [false, true] {
            let output =
                translate_named_debug(&input, &baseline, &template, &fixtures, Some(name), debug)
                    .unwrap();
            assert_eq!(
                signatures(&output.resources),
                expected,
                "{name}, debug={debug}"
            );
            comparisons += 1;
        }
    }
    assert_eq!(comparisons, 60);
}
