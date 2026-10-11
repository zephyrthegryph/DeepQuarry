//! Source-bound selected DMF resource projection, with no filesystem queries.
use crate::assets::ResourceProjection;
use dm_ir::skin::{SkinInterface, SkinSelection};
use dm_tree::{frontend::ColdFrontend, non_text::CapturedSkin};
use std::sync::Arc;
#[derive(Clone, Debug)]
pub struct Plan {
    pub model: SkinSelection,
    pub sources: Arc<[CapturedSkin]>,
}
pub fn plan(frontend: &ColdFrontend, skins: &[CapturedSkin]) -> Result<Plan, String> {
    let includes = frontend
        .plan
        .items
        .iter()
        .filter_map(|item| match item {
            dm_preprocess::regions::OrderedItem::NonText {
                occurrence,
                kind: dm_preprocess::regions::NonTextKind::Skin,
            } => Some(*occurrence),
            _ => None,
        })
        .collect::<Vec<_>>();
    if includes.len() != skins.len() {
        return Err("skin manifest capture coverage mismatch".into());
    }
    let mut interfaces = Vec::new();
    for (skin, occurrence) in skins.iter().zip(includes) {
        if usize::try_from(skin.include_occurrence).ok() != Some(occurrence)
            || frontend.plan.occurrences[occurrence].path != skin.path
        {
            return Err("skin source differs from current manifest occurrence".into());
        }
        if xxhash_rust::xxh3::xxh3_128(skin.source.as_bytes()) != skin.source_identity {
            return Err("skin source identity differs from captured payload".into());
        }
        let alias = dm_preprocess::regions::relative_filesystem_path(
            &skin.path,
            &frontend.plan.project_dir,
        )
        .ok_or("skin outside project requires explicit archive alias")?
        .to_str()
        .ok_or("skin archive alias is not UTF-8")?
        .replace('\\', "/");
        let dependencies = dm_resources::capture::discover_literals(&skin.source)
            .map_err(|error| error.to_string())?
            .into_iter()
            .map(|literal| Arc::<str>::from(literal.path.replace('\\', "/")))
            .collect::<Vec<_>>();
        interfaces.push(SkinInterface {
            archive_alias: alias.into(),
            resource_dependencies: dependencies.into(),
        });
    }
    Ok(Plan {
        model: SkinSelection {
            interfaces: interfaces.into(),
        },
        sources: skins.to_vec().into(),
    })
}
/// Requires the same captured raw skin payload that entered the resource writer.
/// Output IDs are assigned only by the common frozen linker.
pub fn attach(
    dmb: &mut byond_dmb::dmb::Dmb,
    plan: &Plan,
    resources: &ResourceProjection,
    tables: &dm_link::LinkTables,
) -> Result<(), String> {
    if plan.model.interfaces.len() != plan.sources.len() {
        return Err("skin model/source occurrence coverage mismatch".into());
    }
    let Some(selected) = plan.model.selected() else {
        return Ok(());
    };
    let source = plan.sources.last().ok_or("selected skin source absent")?;
    let content = xxhash_rust::xxh3::xxh3_128(source.source.as_bytes());
    if content != source.source_identity {
        return Err("selected skin capture identity mismatch".into());
    }
    let record = resources
        .records
        .iter()
        .find(|(identity, _)| *identity == content)
        .ok_or("selected skin content absent from captured resource projection")?;
    let index = tables
        .index(dm_link::Key::Resource(content))
        .ok_or("selected skin linker resource absent")?;
    if dmb.resources.get(index as usize) != Some(&record.1) {
        return Err("selected skin output resource differs from frozen content".into());
    }
    if !resources
        .inventory
        .iter()
        .any(|entry| entry.key == dm_link::Key::Resource(content))
    {
        return Err(format!(
            "selected skin resource inventory absent: {}",
            selected.archive_alias
        ));
    }
    dmb.world.hub_channel_skin[2] = index;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(windows)]
    #[test]
    fn mixed_prefix_model_preserves_capture_authority_and_external_rejection() {
        struct AbsoluteSkin(&'static str);
        impl dm_preprocess::SourceProvider for AbsoluteSkin {
            fn read(&self, path: &std::path::Path) -> Result<String, String> {
                if path.extension().is_some_and(|ext| ext == "dme") {
                    Ok(format!("#include \"{}\"\n", self.0))
                } else {
                    Ok("window \"main\"\n".into())
                }
            }
        }
        let build = |provider: &AbsoluteSkin| {
            dm_tree::frontend::build(
                std::path::Path::new(r"\\?\E:\game\project.dme"),
                provider,
                &Default::default(),
                1,
            )
            .unwrap()
        };
        let provider = AbsoluteSkin("E:/game/interface/main.dmf");
        let frontend = build(&provider);
        let captured = dm_tree::non_text::capture(&frontend, &provider).unwrap();
        let dm_tree::non_text::NonTextInput::Skin(skin) = &captured[0] else {
            panic!("skin capture")
        };
        let model = plan(&frontend, std::slice::from_ref(skin)).unwrap();
        assert_eq!(
            model.model.selected().unwrap().archive_alias.as_ref(),
            "interface/main.dmf"
        );
        assert_eq!(model.sources[0].path, skin.path);
        let mut changed = skin.clone();
        changed.source_identity ^= 1;
        assert!(plan(&frontend, &[changed]).is_err());
        let provider = AbsoluteSkin("E:/game-other/interface/main.dmf");
        let frontend = build(&provider);
        let captured = dm_tree::non_text::capture(&frontend, &provider).unwrap();
        let dm_tree::non_text::NonTextInput::Skin(skin) = &captured[0] else {
            panic!("skin capture")
        };
        assert!(plan(&frontend, std::slice::from_ref(skin))
            .unwrap_err()
            .contains("outside project"));
    }
    struct Files;
    impl dm_preprocess::SourceProvider for Files {
        fn read(&self, path: &std::path::Path) -> Result<String, String> {
            match path.file_name().and_then(|name| name.to_str()) {
                Some("project.dme") => {
                    Ok("#include \"first.dmf\"\n#include \"second.dmf\"\n".into())
                }
                Some("first.dmf") => Ok("window \"first\"\n".into()),
                Some("second.dmf") => Ok("window \"second\"\n    icon = 'tiny.png'\n".into()),
                _ => Err("missing".into()),
            }
        }
    }
    #[test]
    fn source_bound_model_preserves_last_skin_and_dependencies() {
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("game/project.dme"),
            &Files,
            &Default::default(),
            1,
        )
        .unwrap();
        let capture = crate::non_text::capture(&frontend, &Files).unwrap();
        assert_eq!(capture.skin.model.interfaces.len(), 2);
        let selected = capture.skin.model.selected().unwrap();
        assert_eq!(selected.archive_alias.as_ref(), "second.dmf");
        assert_eq!(selected.resource_dependencies[0].as_ref(), "tiny.png");
        let mut changed = capture.skin.sources.to_vec();
        changed[1].source = "changed".into();
        assert!(plan(&frontend, &changed).is_err());
        changed.reverse();
        assert!(plan(&frontend, &changed).is_err());
    }
    #[test]
    fn selected_raw_dmf_is_attached_by_exact_frozen_content() {
        let bytes = include_bytes!("../../../fixtures/phase0/resources/raw_skin_control/skin.dmf");
        let source = std::str::from_utf8(bytes).unwrap();
        let identity = xxhash_rust::xxh3::xxh3_128(bytes);
        let input = dm_resources::encoding::encode_raw(
            dm_resources::ResourceRequest {
                archive_name: "skin.dmf".into(),
                disk_path: "skin.dmf".into(),
            },
            bytes,
            &dm_resources::encoding::byond516_raw_policy(),
        )
        .unwrap()
        .input;
        let resources = dm_resources::ResourceSet {
            inputs: vec![input],
            fingerprint: [0; 32],
        };
        let projection = crate::assets::project_resources(&resources, &[0]).unwrap();
        let mut inventory = dm_link::LinkInventory::default();
        projection.extend_inventory(&mut inventory);
        let tables = dm_link::LinkTables::build(inventory).unwrap();
        let mut output = byond_dmb::dmb::Dmb::from_bytes(include_bytes!(
            "../../../fixtures/native_template.bin"
        ))
        .unwrap();
        crate::assets::attach_resources(&mut output, &projection, &tables).unwrap();
        let captured = CapturedSkin {
            path: Arc::new("skin.dmf".into()),
            include_occurrence: 0,
            source: source.into(),
            source_identity: identity,
        };
        let plan = Plan {
            model: SkinSelection {
                interfaces: vec![SkinInterface {
                    archive_alias: "skin.dmf".into(),
                    resource_dependencies: vec!["tiny.png".into()].into(),
                }]
                .into(),
            },
            sources: vec![captured].into(),
        };
        attach(&mut output, &plan, &projection, &tables).unwrap();
        assert_eq!(
            output.world.skin_resource_id(),
            tables.index(dm_link::Key::Resource(identity)).unwrap()
        );
        assert_eq!(
            output.resources[output.world.skin_resource_id() as usize].kind,
            0
        );
        let native = byond_dmb::rsc::read_all(
            &mut include_bytes!("../../../fixtures/phase0/resources/raw_skin_control/probe.rsc")
                .as_slice(),
        )
        .unwrap();
        let byond_dmb::rsc::Entry::Named(native_skin) = native
            .iter()
            .find(|entry| {
                matches!(entry,
            byond_dmb::rsc::Entry::Named(named) if named.name == b"skin.dmf")
            })
            .unwrap()
        else {
            panic!()
        };
        assert_eq!(
            output.resources[output.world.skin_resource_id() as usize].id,
            native_skin.id
        );
        let mut wrong = plan.clone();
        wrong.sources = vec![CapturedSkin {
            source: "changed".into(),
            ..wrong.sources[0].clone()
        }]
        .into();
        assert!(attach(&mut output, &wrong, &projection, &tables).is_err());
    }
}
