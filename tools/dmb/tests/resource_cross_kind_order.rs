use byond_dmb::{
    dmb::Dmb,
    od_emit::emit_diagnostic_hashed_with_baseline_named,
    opendream::OpenDreamProgram,
    rsc::{read_all, Entry},
    translate::translate_named_debug,
};
use std::path::Path;
#[path = "support/reference_inputs.rs"]
mod reference_inputs;

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
            Entry::Opaque { .. } => panic!("fixture unexpectedly contains an opaque RSC entry"),
        })
        .collect()
}

#[test]
fn first_archive_crc_kind_survives_native_phase_reordering() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/resource_cross_kind_order");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for (name, kind, first_name) in [
        ("global_generic", 0, "same.txt"),
        ("global_image", 6, "same.png"),
        ("global_dmi", 3, "same.dmi"),
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let archive = read_all(&mut std::io::Cursor::new(
            std::fs::read(fixtures.join(format!("{name}.native.rsc.bin"))).unwrap(),
        ))
        .unwrap();
        let expected = signatures(&archive);
        let mut authored_archive = archive.clone();
        // All three source spellings intentionally contain identical PNG bytes.
        // Git may treat the .txt alias as text while keeping .png/.dmi binary.
        let asset = archive
            .iter()
            .find_map(|entry| match entry {
                Entry::Named(asset) => Some(asset),
                _ => None,
            })
            .unwrap();
        for alias in ["same.txt", "same.png", "same.dmi"] {
            let mut alias_asset = asset.clone();
            alias_asset.name = alias.as_bytes().to_vec();
            authored_archive.push(Entry::Named(alias_asset));
        }
        let inputs = reference_inputs::prepare(&fixtures, &authored_archive, |_| true);
        assert_eq!(expected.len(), 2, "{name}");
        assert_eq!(expected[0].2, first_name.as_bytes(), "{name}");
        assert_eq!(expected[0].0, kind, "{name}");
        assert_eq!(expected[0].1, expected[1].1, "{name}");
        assert_eq!(expected[0].4, expected[1].4, "{name}");
        assert_eq!(native.resources.len(), 1, "{name}");
        assert_eq!(native.resources[0].kind, kind, "{name}");
        assert_eq!(native.resources[0].id, expected[0].1, "{name}");
        let hashed = emit_diagnostic_hashed_with_baseline_named(
            &input,
            Some(&baseline),
            &template,
            &inputs.0,
            Some(name),
        )
        .unwrap();
        assert!(hashed.resources.is_empty());
        assert_eq!(hashed.dmb.resources, native.resources, "{name}: hash only");
        for debug in [false, true] {
            let output =
                translate_named_debug(&input, &baseline, &template, &inputs.0, Some(name), debug)
                    .unwrap();
            assert_eq!(
                signatures(&output.resources),
                expected,
                "{name}, debug={debug}"
            );
            assert_eq!(
                output.dmb.resources, native.resources,
                "{name}, debug={debug}"
            );
            assert_eq!(hashed.ids.resources, output.ids.resources, "{name}");
        }
    }
}
