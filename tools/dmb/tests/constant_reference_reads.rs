use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn direct_constant_reads_and_local_lifetime_match_native() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation/constant_reference_reads");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template = Dmb::from_bytes(include_bytes!("../fixtures/native_template.bin")).unwrap();
    let native = Dmb::from_bytes(include_bytes!(
        "../fixtures/translation/constant_reference_reads/probe.native.bin"
    ))
    .unwrap();
    let input = OpenDreamProgram::from_path(dir.join("probe.json")).unwrap();
    for debug in [false, true] {
        let output =
            translate_named_debug(&input, &baseline, &template, &dir, Some("probe"), debug)
                .unwrap();
        for name in [
            "global_number",
            "global_text",
            "global_type",
            "field_number",
            "field_text",
            "field_type",
            "fold_global",
            "fold_field",
            "get_owner",
            "computed_number",
            "safe_number",
            "colon_number",
            "computed_collision",
            "typed_collision",
            "nested_local_lifetime",
            "nested_local_spawn",
            "computed_text_math",
            "computed_text_condition",
            "safe_text_condition",
            "computed_text_while",
            "list_type",
            "client_type",
            "list_initial",
            "client_initial",
        ] {
            let path = format!("/proc/{name}");
            let find = |dmb: &Dmb| {
                dmb.procs
                    .iter()
                    .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
                    .unwrap()
            };
            let differences = compare_proc_code(
                &native,
                find(&native),
                &output.dmb,
                find(&output.dmb),
                &path,
                100,
                true,
            );
            assert!(
                differences.is_empty(),
                "{path} debug={debug}: {differences:#?}"
            );
        }
    }
}
