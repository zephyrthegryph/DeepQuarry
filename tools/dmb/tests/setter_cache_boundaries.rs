use byond_dmb::{
    compare::compare_proc_code, dmb::Dmb, opendream::OpenDreamProgram,
    translate::translate_named_debug,
};
use std::path::Path;
#[test]
fn direct_setter_receiver_boundaries_match_native() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixture = root.join("fixtures/translation/setter_cache_boundaries");
    let input = OpenDreamProgram::from_path(fixture.join("probe.json")).unwrap();
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixture.join("probe.native.bin")).unwrap()).unwrap();
    let mut paths: Vec<_> = [
        "getter_first",
        "setter_reads",
        "setter_src_rebind",
        "setter_branch",
        "method_branch",
        "setter_other",
        "setter_derived",
        "setter_managed_old",
        "managed",
    ]
    .map(|n| format!("/datum/holder/proc/{n}"))
    .into_iter()
    .collect();
    paths.extend(
        [
            "world_getter_first",
            "world_setter_reads",
            "world_setter_branch",
            "world_setter_other",
        ]
        .map(|n| format!("/proc/{n}")),
    );
    paths.push("/datum/holder/Del".into());
    assert_eq!(paths.len(), 14);
    let find = |dmb: &Dmb, path: &str| {
        dmb.procs
            .iter()
            .position(|p| dmb.string(p.strings[0]) == Some(path.as_bytes()))
            .unwrap_or_else(|| panic!("missing {path}"))
    };
    let mut failures = Vec::new();
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &baseline, &template, &fixture, Some("probe"), debug)
                .unwrap();
        for path in &paths {
            let diff = compare_proc_code(
                &native,
                find(&native, path),
                &actual.dmb,
                find(&actual.dmb, path),
                path,
                100,
                true,
            );
            if !diff.is_empty() {
                failures.push(format!("debug={debug} {path}: {diff:#?}"));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}
