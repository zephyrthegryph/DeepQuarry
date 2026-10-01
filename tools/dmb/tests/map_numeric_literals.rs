use byond_dmb::{
    compare::compare_maps_semantic, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;

#[test]
fn map_numeric_literals_preserve_signed_and_wide_values() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/map_numeric_literals");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    let native = Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        let differences = compare_maps_semantic(&native, &output.dmb, 50);
        assert!(differences.is_empty(), "debug={debug}: {differences:#?}");
        output.dmb.validate_references().unwrap();
    }
    // Reproduce the old emitter: compact PushInt is unsigned WORD at runtime.
    // The comparison must reject it rather than interpreting it as signed i32.
    let mut corrupt =
        Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap();
    let list_id = corrupt
        .instances
        .iter()
        .find_map(|instance| {
            if instance.initializer == 0xffff {
                return None;
            }
            let proc_ = &corrupt.procs[instance.initializer as usize];
            let id = proc_.code_locals_args[0] as usize;
            corrupt.lists[id]
                .windows(4)
                .any(|w| w == [0x60, 42, 49616, 0])
                .then_some(id)
        })
        .expect("native negative map initializer");
    let at = corrupt.lists[list_id]
        .windows(4)
        .position(|w| w == [0x60, 42, 49616, 0])
        .unwrap();
    corrupt.lists[list_id].splice(at..at + 4, [0x50, (-26i32) as u32]);
    assert!(
        !compare_maps_semantic(&native, &corrupt, 50).is_empty(),
        "negative compact-integer corruption was hidden"
    );
}
