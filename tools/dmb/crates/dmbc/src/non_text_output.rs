//! Captured map/resource output stage over the common frozen linker inventory.
use crate::{
    assets::{self, ResourceProjection},
    map_output::{self, DescriptorPlan},
    map_projection::{InstanceKind, Projection},
    symbolic::FrozenBatch,
};
use dm_link::Key;
use dm_tree::{frontend::ColdFrontend, maps::MapPlan};
use std::collections::{BTreeMap, BTreeSet};
pub struct CapturedOutputStage<'a> {
    pub source: &'a ColdFrontend,
    pub maps: &'a [MapPlan],
    pub map: Option<&'a Projection>,
    pub descriptors: Option<&'a DescriptorPlan>,
    pub resources: &'a ResourceProjection,
    pub skin: Option<&'a crate::skin::Plan>,
}
impl crate::composition::NonTextOutputStage for CapturedOutputStage<'_> {
    fn validate_source(&self, frontend: &ColdFrontend) -> Result<(), String> {
        if frontend.snapshot.tree.identity() != self.source.snapshot.tree.identity()
            || frontend.snapshot.occurrences.tree_identity()
                != self.source.snapshot.occurrences.tree_identity()
        {
            return Err("nontext stage differs from source model".into());
        }
        let mut included = Vec::new();
        for item in &frontend.plan.items {
            if let dm_preprocess::regions::OrderedItem::NonText { occurrence, kind } = *item {
                match kind {
                    dm_preprocess::regions::NonTextKind::Map => included.push(occurrence),
                    dm_preprocess::regions::NonTextKind::Skin => {}
                }
            }
        }
        let expected_skin_count = frontend
            .plan
            .non_text(dm_preprocess::regions::NonTextKind::Skin)
            .count();
        match self.skin {
            Some(skin) => {
                let expected = crate::skin::plan(frontend, &skin.sources)?;
                if expected.model != skin.model {
                    return Err("skin projection source identity mismatch".into());
                }
            }
            None if expected_skin_count != 0 => {
                return Err("included skin output projection absent".into())
            }
            None => (),
        }
        if included.len() != self.maps.len() {
            return Err("nontext map occurrence coverage mismatch".into());
        }
        for (map, occurrence) in self.maps.iter().zip(included) {
            if usize::try_from(map.captured.include_occurrence).ok() != Some(occurrence) {
                return Err("map encounter order differs from manifest".into());
            }
            crate::map_identity::capture(frontend, map)?;
        }
        match (self.map, self.descriptors, self.maps.is_empty()) {
            (None, None, true) => (),
            (Some(map), Some(descriptors), false) => {
                let expected = map_output::descriptors(frontend, map, self.maps)
                    .map_err(|error| format!("map descriptor coverage: {error:?}"))?;
                if expected.keys != descriptors.keys
                    || expected.initializers != descriptors.initializers
                    || expected.entries.len() != descriptors.entries.len()
                    || expected
                        .entries
                        .iter()
                        .zip(&descriptors.entries)
                        .any(|(left, right)| left.key != right.key || left.content != right.content)
                {
                    return Err("map descriptor source identity mismatch".into());
                }
            }
            _ => return Err("map projection/descriptors occurrence coverage mismatch".into()),
        }
        Ok(())
    }
    fn apply(
        &self,
        dmb: &mut byond_dmb::dmb::Dmb,
        batch: &FrozenBatch,
    ) -> Result<BTreeSet<Key>, String> {
        assets::attach_resources(dmb, self.resources, &batch.tables)
            .map_err(|error| format!("resource composition: {error:?}"))?;
        if let Some(skin) = self.skin {
            crate::skin::attach(dmb, skin, self.resources, &batch.tables)?;
        }
        let mut covered = self
            .resources
            .inventory
            .iter()
            .map(|entry| entry.key)
            .collect::<BTreeSet<_>>();
        if let (Some(projection), Some(descriptors)) = (self.map, self.descriptors) {
            // Wire identity validation after class projection, not a source
            // ancestry query against mutable output records.
            let mut class_mobs = BTreeMap::new();
            for (index, mob) in dmb.mobs.iter().enumerate() {
                let index = u32::try_from(index).map_err(|_| "mob descriptor index overflow")?;
                if class_mobs.insert(mob.class, index).is_some() {
                    return Err("ambiguous emitted mob class descriptor".into());
                }
            }
            let mut mob_descriptors = BTreeMap::new();
            for instance in projection
                .instances
                .iter()
                .filter(|instance| instance.kind == InstanceKind::Mob)
            {
                let class = batch
                    .tables
                    .index(Key::Type(instance.atom.type_path))
                    .ok_or("map mob type binding absent")?;
                let descriptor = *class_mobs
                    .get(&class)
                    .ok_or("emitted map mob descriptor absent")?;
                mob_descriptors.insert(instance.atom.type_path, descriptor);
            }
            map_output::attach(
                dmb,
                projection,
                descriptors,
                &batch.tables,
                &mob_descriptors,
            )
            .map_err(|error| format!("map composition: {error:?}"))?;
            covered.extend(descriptors.keys.iter().copied());
            covered.extend(
                descriptors
                    .initializers
                    .iter()
                    .flatten()
                    .copied()
                    .map(Key::Initializer),
            );
        }
        Ok(covered)
    }
}
