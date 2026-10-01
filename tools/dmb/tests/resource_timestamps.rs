use byond_dmb::{
    dmb::Dmb,
    od_emit::emit_with_baseline_named,
    opendream::OpenDreamProgram,
    rsc::{read_all, Entry},
};
use std::{
    fs::{File, FileTimes},
    path::Path,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

fn named(entries: &[Entry]) -> &byond_dmb::rsc::NamedResource {
    assert_eq!(entries.len(), 1);
    match &entries[0] {
        Entry::Named(resource) => resource,
        Entry::Opaque { .. } => panic!("fresh fixture contains an opaque resource"),
    }
}

#[test]
fn new_resource_timestamps_match_native_time_and_source_mtime() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let fixtures = root.join("fixtures/translation/resource_timestamps");
    let baseline =
        OpenDreamProgram::from_path(root.join("fixtures/native_template_savefile_5161687.json"))
            .unwrap();
    let input = OpenDreamProgram::from_path(fixtures.join("probe.json")).unwrap();
    let template =
        Dmb::from_bytes(&std::fs::read(root.join("fixtures/native_template.dmb")).unwrap())
            .unwrap();
    let native =
        Dmb::from_bytes(&std::fs::read(fixtures.join("probe.native.bin")).unwrap()).unwrap();
    let archive = read_all(&mut std::io::Cursor::new(
        std::fs::read(fixtures.join("probe.native.rsc.bin")).unwrap(),
    ))
    .unwrap();
    let expected = named(&archive);
    assert_eq!(expected.source_timestamp, 1_700_000_123);
    assert_ne!(expected.timestamp, 0);
    let unique = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let scratch = std::env::temp_dir().join(format!("dmb-resource-timestamps-{unique}"));
    std::fs::create_dir(&scratch).unwrap();
    let asset = scratch.join("asset.txt");
    std::fs::copy(fixtures.join("asset.txt"), &asset).unwrap();
    for (mtime, encoded) in [
        (1_700_000_123_u64, 1_700_000_123_u32),
        (4_294_967_419, 123),
        (4_294_967_296, 0),
    ] {
        File::options()
            .write(true)
            .open(&asset)
            .unwrap()
            .set_times(FileTimes::new().set_modified(UNIX_EPOCH + Duration::from_secs(mtime)))
            .unwrap();
        assert_eq!(
            std::fs::metadata(&asset).unwrap().modified().unwrap(),
            UNIX_EPOCH + Duration::from_secs(mtime),
        );
        let before = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as u32;
        let output =
            emit_with_baseline_named(&input, Some(&baseline), &template, &scratch, Some("probe"))
                .unwrap();
        let after = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as u32;
        let actual = named(&output.resources);
        assert!(actual.timestamp >= before && actual.timestamp <= after);
        assert_eq!(actual.source_timestamp, encoded, "mtime={mtime}");
        assert_eq!(actual.name, expected.name);
        assert_eq!(actual.id, expected.id);
        assert_eq!(actual.kind, expected.kind);
        assert_eq!(actual.data, expected.data);
        assert_eq!(actual.declared_size, expected.declared_size);
        assert_eq!(output.dmb.resources, native.resources);
    }
    std::fs::remove_file(asset).unwrap();
    std::fs::remove_dir(scratch).unwrap();
}
