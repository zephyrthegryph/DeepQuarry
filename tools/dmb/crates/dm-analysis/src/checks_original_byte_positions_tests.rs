//! Seeded independently against pinned suite-1.11. These assert original byte
//! positions, including UTF8 before a diagnostic and TAB=one-byte columns.
use crate::checks::{BodyView, Diagnostic, Severity};
use dm_preprocess::{AcquiredSource, SourceProvider, SourceText};
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source(AcquiredSource);
impl SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Err("test requires original acquisition".into())
    }
    fn acquired_source(&self, _: &Path) -> Result<Option<AcquiredSource>, String> {
        Ok(Some(self.0.clone()))
    }
    fn source_acquisition(&self, _: &Path, text: &SourceText) -> Option<AcquiredSource> {
        self.0
            .lease()
            .source_text()
            .same_view(text)
            .then(|| self.0.clone())
    }
}
fn observe(source: &str, family: &str) -> Result<Vec<(&'static str, usize, usize)>, String> {
    let provider = Source(AcquiredSource::from_original_bytes(
        source.as_bytes().to_vec(),
        (),
    ));
    let f = build(
        Path::new("byte_positions.dme"),
        &provider,
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&f, |_| true);
    let mut out = Vec::new();
    for occurrence in f.bodies.iter() {
        arena
            .with_parsed(occurrence, |body| -> Result<(), String> {
                let view = BodyView::new(&f, body)?;
                let rows: Vec<Diagnostic> = match family {
                    "bitwise" => view.ambiguous_not_bitwise(Severity::Warning),
                    "membership" => view.ambiguous_in_lhs(Severity::Warning)?,
                    "settings" => crate::checks_invalid_set::check(&view, Severity::Warning)?,
                    "control" => crate::checks_control_policies::check(
                        &view,
                        &[
                            (super::Family::Static, Severity::Error),
                            (super::Family::Unreachable, Severity::Error),
                            (super::Family::LoopDeterminate, Severity::Error),
                            (super::Family::IfDeterminate, Severity::Error),
                            (super::Family::SettingPlacement, Severity::Error),
                        ],
                    )?,
                    _ => unreachable!(),
                };
                for row in rows {
                    let source = f
                        .source_export_mapping()
                        .ok_or("mapping absent")?
                        .original_note_origin(row.span.start)?;
                    out.push((row.family, source.line, source.byte_column));
                }
                Ok(())
            })
            .map_err(|e| e.message)??;
    }
    Ok(out)
}
#[test]
fn all_eight_families_use_issued_utf8_byte_and_tab_positions() {
    let cases = [
        (
            "bitwise",
            include_str!("../../../fixtures/unified_checks/byte_bitwise/probe.dm"),
            vec![("ambiguous_not_bitwise", 2, 17)],
        ),
        (
            "membership",
            include_str!("../../../fixtures/unified_checks/byte_membership/probe.dm"),
            vec![("ambiguous_in_lhs", 2, 17)],
        ),
        (
            "settings",
            include_str!("../../../fixtures/unified_checks/byte_settings/probe.dm"),
            vec![("invalid_set_value", 2, 20)],
        ),
        (
            "control",
            include_str!("../../../fixtures/unified_checks/byte_control/probe.dm"),
            vec![
                ("control_condition_static", 2, 19),
                ("if_condition_determinate", 2, 19),
                ("loop_condition_determinate", 4, 17),
                ("control_condition_static", 4, 17),
                ("set_has_no_effect", 6, 17),
                ("unreachable_code", 7, 18),
            ],
        ),
    ];
    for (family, source, expected) in cases {
        assert_eq!(observe(source, family).unwrap(), expected, "{family}");
    }
}
#[test]
fn macro_transformed_diagnostic_is_unsupported_not_a_wrong_original_column() {
    let source = "#define MASK !a & b\n/proc/probe(a,b)\n\tlist(1); MASK\n";
    assert!(observe(source, "bitwise").is_err());
}
