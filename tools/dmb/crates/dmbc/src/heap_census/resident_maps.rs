//! Retained parsed maps and geometry: accessible owners, not wire-size proxies.
use super::*;
use crate::{lowering_memo::ResolverRead, map_projection::Projection};
use dm_ir::ReadDomain;
use dm_tree::maps::MapPlan;

impl HeapCensus {
    fn map_atom_owners(&mut self, atom: &dm_ir::map::MapAtom) {
        let dm_ir::map::MapAtom {
            type_path: _,
            initializer_present: _,
            assignments,
        } = atom;
        if self.slice("retained_maps.assignments", assignments, true) {
            for assignment in assignments.iter() {
                let dm_ir::map::MapAssignment { name: _, value } = assignment;
                self.expression("retained_maps.expressions", value);
            }
        }
    }
    /// Return separately conservative SymbolTable bucket charges. All other
    /// returned payloads are actual borrowed allocations, deduplicated by owner.
    pub(crate) fn retained_map_plan(&mut self, plan: &MapPlan) -> usize {
        let MapPlan {
            captured,
            source_identity: _,
            semantic_identity: _,
            model,
            symbols,
            template_origins,
            block_origins,
        } = plan;
        let dm_tree::maps::CapturedMap {
            path,
            include_occurrence: _,
            source,
        } = captured;
        self.arc_path("retained_maps.paths", path);
        self.arc_text("retained_maps.sources", source);
        if self.arc_object("retained_maps.models", model) {
            let dm_ir::map::SymbolicMap {
                templates,
                blocks,
                records,
                key_width: _,
            } = model.as_ref();
            if self.slice("retained_maps.templates", templates, true) {
                for template in templates.iter() {
                    let dm_ir::map::MapTemplate { key, atoms } = template;
                    self.arc_text("retained_maps.template_keys", key);
                    if self.slice("retained_maps.atoms", atoms, true) {
                        for atom in atoms.iter() {
                            self.map_atom_owners(atom);
                        }
                    }
                }
            }
            if self.slice("retained_maps.blocks", blocks, true) {
                for block in blocks.iter() {
                    let dm_ir::map::MapBlock { origin: _, cells } = block;
                    self.arc_text("retained_maps.cells", cells);
                }
            }
            self.slice("retained_maps.records", records, true);
        }
        let private_indexes = if self.arc_object("retained_maps.symbol_tables", symbols) {
            self.symbol_table_storage("retained_maps.symbols", symbols)
        } else {
            0
        };
        if self.slice("retained_maps.template_origins", template_origins, true) {
            for template in template_origins.iter() {
                let dm_tree::maps::TemplateOrigin {
                    span: _,
                    key_span: _,
                    payload_span: _,
                    atoms,
                } = template;
                if self.slice("retained_maps.atom_origins", atoms, true) {
                    for atom in atoms.iter() {
                        let dm_tree::maps::AtomOrigin {
                            span: _,
                            type_span: _,
                            assignments,
                        } = atom;
                        self.slice("retained_maps.assignment_origins", assignments, true);
                    }
                }
            }
        }
        self.slice("retained_maps.block_origins", block_origins, true);
        private_indexes
    }
    pub(crate) fn retained_map_projection(&mut self, projection: &Projection) {
        let Projection {
            dimensions: _,
            instances,
            grid,
            objects,
        } = projection;
        if self.slice("retained_maps.projected_instances", instances, true) {
            for instance in instances.iter() {
                let crate::map_projection::Instance {
                    kind: _,
                    atom,
                    origin: _,
                } = instance;
                self.map_atom_owners(atom);
            }
        }
        self.slice("retained_maps.grid", grid, true);
        self.slice("retained_maps.objects", objects, true);
    }
}
fn finish(census: HeapCensus, private_indexes: usize, envelope: usize) -> Option<usize> {
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    Some(
        usize::try_from(report.unique_known_capacity_bytes)
            .ok()?
            .saturating_add(private_indexes)
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(envelope)
            .saturating_add(4096),
    )
}
pub(crate) fn plan_weight(plan: &MapPlan, key: &Arc<[u8]>) -> Option<usize> {
    let mut census = HeapCensus::new("resident_map_parse_admission");
    census.slice("retained_maps.key", key, true);
    let private_indexes = census.retained_map_plan(plan);
    finish(census, private_indexes, size_of::<MapPlan>())
}
pub(crate) fn geometry_weight(
    plans: &Arc<[MapPlan]>,
    projection: &Projection,
    key: &Arc<[u8]>,
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_map_geometry_admission");
    census.slice("retained_maps.key", key, true);
    census.slice("retained_maps.plans", plans, true);
    let mut private_indexes = 0usize;
    for plan in plans.iter() {
        private_indexes = private_indexes.saturating_add(census.retained_map_plan(plan));
    }
    census.retained_map_projection(projection);
    census.vec_payload("retained_maps.reads", reads);
    census.vec_payload("retained_maps.versions", versions);
    for read in reads {
        super::resident_weight::answer(&mut census, &read.answer);
    }
    finish(
        census,
        private_indexes,
        size_of::<Projection>().saturating_add(size_of::<Arc<[MapPlan]>>()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    fn plan() -> MapPlan {
        dm_tree::maps::plan(dm_tree::maps::CapturedMap {
            path: Arc::new(PathBuf::from("maps/probe.dmm")),
            include_occurrence: 0,
            source: Arc::from("\"a\"=(/turf{amount=1})\n(1,1,1)={\"a\"}"),
        })
        .unwrap()
    }
    fn projection(plan: &MapPlan) -> Projection {
        Projection {
            dimensions: [1, 1, 1],
            instances: Arc::from([crate::map_projection::Instance {
                kind: crate::map_projection::InstanceKind::Turf,
                atom: plan.model.templates[0].atoms[0].clone(),
                origin: None,
            }]),
            grid: Arc::from([]),
            objects: Arc::from([]),
        }
    }
    #[test]
    fn shared_models_and_projected_assignments_are_counted_once() {
        let plan = plan();
        let projected = projection(&plan);
        let mut single = HeapCensus::new("single");
        let private = single.retained_map_plan(&plan);
        let before = single.finish().unique_known_capacity_bytes;
        let mut combined = HeapCensus::new("combined");
        assert_eq!(combined.retained_map_plan(&plan), private);
        assert_eq!(combined.retained_map_plan(&plan.clone()), 0);
        combined.retained_map_projection(&projected);
        let after = combined.finish().unique_known_capacity_bytes;
        assert_eq!(
            after - before,
            size_of::<crate::map_projection::Instance>() as u64
        );
        let key: Arc<[u8]> = Arc::from(b"key".as_slice());
        assert!(plan_weight(&plan, &key).is_some());
        let plans = Arc::from([plan]);
        let base = geometry_weight(&plans, &projected, &key, &Vec::new(), &Vec::new()).unwrap();
        let mut larger = projected.clone();
        larger.grid = Arc::from(vec![
            crate::map_projection::GridRun {
                turf: 0,
                area: 0,
                copies: 1
            };
            10000
        ]);
        assert!(
            geometry_weight(&plans, &larger, &key, &Vec::new(), &Vec::new()).unwrap()
                >= base + 10000 * size_of::<crate::map_projection::GridRun>()
        );
    }
}
