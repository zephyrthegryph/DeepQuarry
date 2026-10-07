//! One explicit nontext capture/plan boundary shared by compile and analysis.
use dm_tree::{
    frontend::ColdFrontend,
    maps::MapPlan,
    non_text::{CapturedSkin, NonTextInput},
};
use std::{collections::BTreeMap, path::PathBuf, sync::Arc};
pub struct CapturedNonText {
    pub inputs: Arc<[NonTextInput]>,
    pub maps: Arc<[MapPlan]>,
    pub skins: Arc<[CapturedSkin]>,
    pub assets: crate::assets::ExtraAssets,
    pub skin: crate::skin::Plan,
}
#[derive(Debug)]
pub enum Error {
    Capture(Vec<dm_tree::non_text::CaptureError>),
    Map {
        path: Arc<PathBuf>,
        include_occurrence: u32,
        diagnostic: dm_tree::maps::MapDiagnostic,
    },
    Assets(dm_resources::capture::CaptureError),
    Skin(String),
}
/// Map/skin files are read once by dm-tree capture. Repeated same-path includes
/// reuse their exact parsed model and source Arc while retaining include IDs.
pub fn capture<P: dm_preprocess::SourceProvider>(
    frontend: &ColdFrontend,
    provider: &P,
) -> Result<CapturedNonText, Error> {
    let inputs = dm_tree::non_text::capture(frontend, provider).map_err(Error::Capture)?;
    let mut cached = BTreeMap::<Arc<PathBuf>, MapPlan>::new();
    let mut maps = Vec::new();
    let mut skins = Vec::new();
    for input in inputs.iter() {
        match input {
            NonTextInput::Map(source) => {
                let planned = if let Some(previous) = cached.get(&source.path) {
                    if previous.captured.source != source.source {
                        return Err(Error::Map {
                            path: source.path.clone(),
                            include_occurrence: source.include_occurrence,
                            diagnostic: dm_tree::maps::MapDiagnostic {
                                kind: dm_tree::maps::DiagnosticKind::Internal,
                                span: dm_syntax::Span::new(0, 0),
                                message: "same nontext path returned conflicting captures".into(),
                            },
                        });
                    }
                    let mut plan = previous.clone();
                    plan.captured = source.clone();
                    plan
                } else {
                    let plan =
                        dm_tree::maps::plan(source.clone()).map_err(|diagnostic| Error::Map {
                            path: source.path.clone(),
                            include_occurrence: source.include_occurrence,
                            diagnostic,
                        })?;
                    cached.insert(source.path.clone(), plan.clone());
                    plan
                };
                maps.push(planned);
            }
            NonTextInput::Skin(source) => skins.push(source.clone()),
        }
    }
    let assets = crate::assets::discover_extra(&frontend.plan.project_dir, &maps, &skins)
        .map_err(Error::Assets)?;
    let skin = crate::skin::plan(frontend, &skins).map_err(Error::Skin)?;
    Ok(CapturedNonText {
        inputs,
        maps: maps.into(),
        skins: skins.into(),
        assets,
        skin,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::map_projection::{InstanceClassifier, InstanceKind, WorldDefaults};
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, path: &Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("project.dme") => Ok(
                    "#include \"first.dmm\"\n#include \"second.dmm\"\n#include \"first.dmm\"\n"
                        .into(),
                ),
                Some("first.dmm" | "second.dmm") => {
                    Ok("\"a\"=(/obj{},/turf,/area)\n(1,1,1)={\"a\"}".into())
                }
                _ => Err("missing source".into()),
            }
        }
    }
    struct Kinds;
    impl InstanceClassifier for Kinds {
        fn classify(&self, path: dm_ir::SymbolId) -> Result<InstanceKind, String> {
            if path == dm_ir::SymbolId::of("/turf") {
                Ok(InstanceKind::Turf)
            } else if path == dm_ir::SymbolId::of("/area") {
                Ok(InstanceKind::Area)
            } else {
                Ok(InstanceKind::Object)
            }
        }
    }
    #[test]
    fn one_capture_preserves_repeat_occurrences_and_distinct_debug_paths() {
        let frontend = dm_tree::frontend::build(
            Path::new("game/project.dme"),
            &Source,
            &Default::default(),
            1,
        )
        .unwrap();
        let captured = capture(&frontend, &Source).unwrap();
        assert_eq!(captured.maps.len(), 3);
        assert!(Arc::ptr_eq(
            &captured.maps[0].model,
            &captured.maps[2].model
        ));
        assert_ne!(
            captured.maps[0].captured.include_occurrence,
            captured.maps[2].captured.include_occurrence
        );
        let first = crate::map_identity::capture(&frontend, &captured.maps[0]).unwrap();
        let second = crate::map_identity::capture(&frontend, &captured.maps[1]).unwrap();
        let repeated = crate::map_identity::capture(&frontend, &captured.maps[2]).unwrap();
        assert_eq!(first.identity, repeated.identity);
        assert_ne!(first.identity, second.identity);
        let projection = crate::map_projection::project(
            &captured.maps,
            WorldDefaults {
                turf: dm_ir::SymbolId::of("/turf"),
                area: dm_ir::SymbolId::of("/area"),
                minimum_dimensions: [1, 1, 1],
            },
            &Kinds,
        )
        .unwrap();
        let descriptors =
            crate::map_output::descriptors(&frontend, &projection, &captured.maps).unwrap();
        assert_ne!(descriptors.initializers[2], descriptors.initializers[5]);
        assert_eq!(descriptors.initializers[2], descriptors.initializers[8]);
    }
}
