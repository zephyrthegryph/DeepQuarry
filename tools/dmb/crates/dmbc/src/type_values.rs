//! Pinned runtime-family policy over actual captured semantic ancestry.
//! Dense class/mob/resource IDs remain writer/link inventory responsibilities.
use crate::{
    class_projection::{ProjectionError, TypeValuePolicy},
    engine::EngineSnapshot,
};
use dm_ir::SymbolId;
use dm_tree::frontend::ColdFrontend;

pub struct CapturedTypeValues<'a> {
    frontend: &'a ColdFrontend,
}
impl<'a> CapturedTypeValues<'a> {
    pub fn pinned(
        frontend: &'a ColdFrontend,
        engine: &EngineSnapshot,
    ) -> Result<Self, ProjectionError> {
        const TEMPLATE: &[u8] = include_bytes!("../../../fixtures/native_template.bin");
        if !engine.matches_template(TEMPLATE, 1)
            || frontend.engine.as_ref().map(|status| status.identity) != Some(engine.identity())
        {
            return Err(ProjectionError::Unsupported(
                "runtime type policy requires same pinned engine capture/schema".into(),
            ));
        }
        Ok(Self { frontend })
    }
}
impl TypeValuePolicy for CapturedTypeValues<'_> {
    fn tag(&self, path: SymbolId) -> Result<u8, ProjectionError> {
        let tree = &self.frontend.snapshot.tree;
        let mut cursor = Some(tree.lookup_type(path).ok_or_else(|| {
            ProjectionError::Unsupported("runtime type is not in captured tree".into())
        })?);
        // Priority matches the established native family policy. Compare actual
        // parent symbols, not lexical path prefixes (parent_type can redirect).
        let families = [
            ("/list", 40),
            ("/savefile", 36),
            ("/file", 39),
            ("/client", 59),
            ("/alist", 89),
            ("/mob", 8),
            ("/obj", 9),
            ("/atom/movable", 9),
            ("/turf", 10),
            ("/area", 11),
            ("/image", 63),
            ("/mutable_appearance", 63),
            ("/atom", 10),
        ];
        let mut found = [false; 13];
        let mut known_root = false;
        while let Some(id) = cursor {
            let node = tree.type_node(id).ok_or_else(|| {
                ProjectionError::Unsupported("captured runtime ancestry missing".into())
            })?;
            for (index, (family, _)) in families.iter().enumerate() {
                found[index] |= node.path == SymbolId::of(family);
            }
            known_root |= node.path == SymbolId::of("/") || node.path == SymbolId::of("/datum");
            cursor = tree.parent(id);
        }
        families
            .iter()
            .zip(found)
            .find_map(|((_, tag), present)| present.then_some(*tag))
            .or(known_root.then_some(32))
            .ok_or_else(|| {
                ProjectionError::Unsupported("runtime family has no pinned ancestry rule".into())
            })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::Path;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &Path) -> Result<String, String> {
            Ok("/datum/mobile\n    parent_type = /mob\n/mob/not_mobile\n    parent_type = /datum\n".into())
        }
    }
    #[test]
    fn actual_parent_controls_family_and_mob_id_is_not_class_id() {
        let engine =
            EngineSnapshot::from_bytes(include_bytes!("../../../fixtures/native_template.bin"), 1)
                .unwrap();
        let seed = engine.frontend_seed();
        let frontend = dm_tree::frontend::build_with_config(
            Path::new("fixture.dme"),
            &Source,
            &Default::default(),
            dm_tree::frontend::FrontendConfig {
                workers: 1,
                engine: Some(&seed),
                observer: None,
            },
        )
        .unwrap();
        let policy = CapturedTypeValues::pinned(&frontend, &engine).unwrap();
        assert_eq!(policy.tag(SymbolId::of("/datum/mobile")).unwrap(), 8);
        assert_eq!(policy.tag(SymbolId::of("/mob/not_mobile")).unwrap(), 32);
        assert!(policy.tag(SymbolId::of("/mob/absent")).is_err());
        assert!(policy.mob_index(SymbolId::of("/datum/mobile")).is_err());
    }
}
