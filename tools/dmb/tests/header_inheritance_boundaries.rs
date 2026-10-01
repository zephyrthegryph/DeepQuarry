use byond_dmb::{dmb::Dmb, opendream::OpenDreamProgram, translate::translate_named_debug};
use std::path::Path;
fn signature(d: &Dmb, id: usize) -> String {
    let c = &d.classes[id];
    let mut h = c.clone();
    let mut strings = Vec::new();
    for n in [0usize, 2, 3, 5] {
        strings.push(d.string(c.initial_ids[n]).map(|b| b.to_vec()));
        h.initial_ids[n] = 0;
    }
    strings.push(
        d.classes
            .get(c.initial_ids[1] as usize)
            .and_then(|p| d.string(p.initial_ids[0]))
            .map(|b| b.to_vec()),
    );
    h.initial_ids[1] = 0;
    for n in [c.text, c.maptext, c.suffix] {
        strings.push(d.string(n).map(|b| b.to_vec()));
    }
    h.text = 0;
    h.maptext = 0;
    h.suffix = 0;
    h.lists_and_procs = [0; 6];
    h.overrides = 0;
    let mut overrides: Vec<_> = d
        .class_builtin_overrides(id)
        .unwrap_or_default()
        .into_iter()
        .map(|v| {
            (
                d.string(v.name_string_id).unwrap().to_vec(),
                if v.value.tag() == 6 {
                    format!("{:?}", d.string(v.value.id()))
                } else {
                    format!("{:?}", v.value)
                },
            )
        })
        .collect();
    overrides.sort_by(|a, b| a.0.cmp(&b.0));
    format!("{h:?} {strings:?} {overrides:?}")
}
#[test]
fn native_root_headers_and_callbacks_match_native() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let f = root.join("fixtures/translation/header_inheritance_boundaries");
    let input = OpenDreamProgram::from_path(f.join("probe.json")).unwrap();
    let base =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.bin")).unwrap())
            .unwrap();
    let native = Dmb::from_bytes(&std::fs::read(f.join("probe.native.bin")).unwrap()).unwrap();
    let mut paths: Vec<_> = std::fs::read_to_string(f.join("probe.dm"))
        .unwrap()
        .lines()
        .filter(|s| s.starts_with('/') && !s.contains('(') && *s != "/world")
        .map(str::to_string)
        .collect();
    paths.extend(["/obj/drop", "/obj/move", "/obj/down"].map(str::to_string));
    paths.sort();
    paths.dedup();
    assert_eq!(paths.len(), 17);
    let find = |d: &Dmb, p: &str| {
        d.classes
            .iter()
            .position(|c| d.string(c.initial_ids[0]) == Some(p.as_bytes()))
            .unwrap()
    };
    for debug in [false, true] {
        let actual =
            translate_named_debug(&input, &base, &template, &f, Some("probe"), debug).unwrap();
        for p in &paths {
            assert_eq!(
                signature(&native, find(&native, p)),
                signature(&actual.dmb, find(&actual.dmb, p)),
                "{p} debug={debug}"
            );
        }
    }
    let mut broken = native.clone();
    let id = find(&broken, "/obj/zero_dir/child");
    broken.classes[id].direction = 1;
    assert_ne!(signature(&native, id), signature(&broken, id));
}
