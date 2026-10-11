//! Independent declaration-only and custom-parent controls from native captures.
use super::*;
use crate::class_projection::{project, CapturedFieldEvaluator};
use dm_ir::{SemanticValue, SymbolicExpression};
use std::path::Path;

struct Source(String);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok(self.0.clone())
    }
}
struct NullFields;
impl CapturedFieldEvaluator for NullFields {
    fn evaluate(&self, _: SymbolId, _: &SymbolicExpression) -> Result<SemanticValue, String> {
        // These independent specimens contain only omitted or null field values.
        Ok(SemanticValue::Null)
    }
}

#[test]
fn declaration_only_graphics_and_custom_parent_controls_match_pinned_headers() {
    let root =
        Path::new(env!("CARGO_MANIFEST_DIR")).join("../../fixtures/translation/graphics_access");
    let seed = Dmb::from_bytes(include_bytes!("../../../../fixtures/native_template.bin")).unwrap();
    assert_eq!(seed.header.flags & 0x40, 0x40);
    let engine = crate::engine::EngineSnapshot::from_bytes(
        include_bytes!("../../../../fixtures/native_template.bin"),
        1,
    )
    .unwrap()
    .with_bootstrap_catalog()
    .unwrap();
    let frontend_seed = engine.frontend_seed();
    for name in [
        "declaration_only",
        "datum_custom",
        "false_alias",
        "global_custom",
    ] {
        let text = std::fs::read_to_string(root.join(format!("{name}.dm"))).unwrap();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("graphics.dme"),
            &Source(text),
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&frontend_seed),
                observer: None,
            },
        )
        .unwrap_or_else(|error| panic!("{name}: {error:?}"));
        let projection =
            project(&frontend.snapshot, &frontend.emission_order, &NullFields).unwrap();
        let expected =
            Dmb::from_bytes(&std::fs::read(root.join(format!("{name}.native.bin"))).unwrap())
                .unwrap();
        let mut actual = expected.clone();
        actual.header.flags = (actual.header.flags & !0x40) | (seed.header.flags & 0x40);
        let tables = dm_link::LinkTables::build(dm_link::LinkInventory::default()).unwrap();
        crate::class_projection::materialize_callback_flags(&mut actual, &projection, &tables)
            .unwrap();
        assert_eq!(actual.header.flags, expected.header.flags, "{name}");
        assert_eq!(
            actual.header.extended_flags, expected.header.extended_flags,
            "{name}"
        );
    }
}
