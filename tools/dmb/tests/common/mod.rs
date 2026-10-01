use byond_dmb::{dmb::Dmb, opendream::OpenDreamProgram};
use std::path::{Path, PathBuf};

pub struct TranslationFixture {
    pub dir: PathBuf,
    pub input: OpenDreamProgram,
    pub baseline: OpenDreamProgram,
    pub template: Dmb,
    pub native: Dmb,
}

pub fn translation_fixture(name: &str) -> TranslationFixture {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = root.join("fixtures/translation").join(name);
    TranslationFixture {
        input: OpenDreamProgram::from_path(dir.join("probe.json")).unwrap(),
        baseline: OpenDreamProgram::from_path(
            root.join("fixtures/native_template_savefile_5161687.json"),
        )
        .unwrap(),
        template: Dmb::from_bytes(
            &std::fs::read(root.join("fixtures/native_template.bin")).unwrap(),
        )
        .unwrap(),
        native: Dmb::from_bytes(&std::fs::read(dir.join("probe.native.bin")).unwrap()).unwrap(),
        dir,
    }
}
