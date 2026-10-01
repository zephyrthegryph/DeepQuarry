use byond_dmb::{
    compare::{compare_dmbs, compare_maps_semantic, CompareOptions},
    dmb::Dmb,
    od_emit::emit_with_baseline,
    opendream::OpenDreamProgram,
};
use std::path::Path;

#[test]
fn authored_world_dimensions_generate_and_precede_included_maps() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/world_dimensions");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    for name in [
        "zero",
        "fraction_small",
        "fraction",
        "two",
        "z_zero",
        "shrink",
        "expand",
        "z_expand",
        "mapped_zero",
    ] {
        let input = OpenDreamProgram::from_path(fixtures.join(format!("{name}.json"))).unwrap();
        let native =
            Dmb::from_bytes(&std::fs::read(fixtures.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let output = emit_with_baseline(&input, Some(&baseline), &template, &fixtures).unwrap();
        assert_eq!(output.dmb.dimensions, native.dimensions, "{name}");
        assert!(
            compare_maps_semantic(&native, &output.dmb, 100).is_empty(),
            "{name}"
        );
        let differences = compare_dmbs(
            &native,
            &output.dmb,
            &CompareOptions {
                authored_prefixes: vec!["/world".into()],
                compare_bytecode: false,
                max_discrepancies: 20,
            },
        );
        assert!(differences.is_empty(), "{name}: {differences:#?}");
        output.dmb.validate_references().unwrap();
    }
}
