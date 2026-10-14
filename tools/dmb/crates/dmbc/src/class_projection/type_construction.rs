//! Latest symbolic readiness recipe on the admitted type-roster owner.
//! Current dense IDs, spelling checks and retained class validation stay outside.
use super::*;
use std::sync::Mutex;
#[derive(Clone, Debug, PartialEq, Eq)]
struct Input {
    path: SymbolId,
    parent: SymbolId,
    retained_parent: bool,
}
#[derive(Debug)]
struct Recipe {
    inputs: Vec<Input>,
    waves: Vec<Vec<SymbolId>>,
}
#[derive(Default, Debug)]
pub(crate) struct TypeConstruction {
    current: Mutex<Option<Arc<Recipe>>>,
}
impl TypeConstruction {
    pub(super) fn waves(
        &self,
        planned: &BTreeMap<u32, &TypeProjection>,
        parents: &BTreeMap<u32, u32>,
        retained: usize,
    ) -> Result<Vec<Vec<u32>>, ProjectionError> {
        let inputs = planned
            .iter()
            .map(|(&index, ty)| Input {
                path: ty.path,
                // The ordinary parent binder already rejected absent parents.
                parent: ty.parent.expect("validated current parent"),
                retained_parent: (parents[&index] as usize) < retained,
            })
            .collect::<Vec<_>>();
        let unique: HashSet<_> = inputs.iter().map(|input| input.path).collect();
        if unique.len() != inputs.len() {
            *self.current.lock().unwrap_or_else(|e| e.into_inner()) = None;
            return class_construction_waves(parents, retained);
        }
        let mut current = self.current.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(recipe) = current.as_ref().filter(|recipe| recipe.inputs == inputs) {
            // Input order is the exact current dense encounter order. Rebinding
            // symbolic waves never uses numeric IDs from an earlier request.
            let ids: HashMap<_, _> = planned.iter().map(|(&id, ty)| (ty.path, id)).collect();
            return Ok(recipe
                .waves
                .iter()
                .map(|wave| wave.iter().map(|path| ids[path]).collect())
                .collect());
        }
        *current = None;
        let waves = class_construction_waves(parents, retained)?;
        let symbolic = waves
            .iter()
            .map(|wave| wave.iter().map(|id| planned[id].path).collect())
            .collect();
        *current = Some(Arc::new(Recipe {
            inputs,
            waves: symbolic,
        }));
        Ok(waves)
    }
    pub(crate) fn census(&self, census: &mut crate::heap_census::HeapCensus) {
        if let Some(recipe) = self
            .current
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
        {
            if census.arc_object("class_projection.type_construction", recipe) {
                census.vec_payload("class_projection.type_construction_inputs", &recipe.inputs);
                if census.vec_payload("class_projection.type_construction_waves", &recipe.waves) {
                    for wave in &recipe.waves {
                        census.vec_payload("class_projection.type_construction_wave", wave);
                    }
                }
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn run(owner: &TypeConstruction, ids: &[u32], root: u32) -> Vec<Vec<u32>> {
        let types = [
            TypeProjection {
                path: SymbolId::of("/a"),
                parent: Some(SymbolId::of("/root")),
            },
            TypeProjection {
                path: SymbolId::of("/a/child"),
                parent: Some(SymbolId::of("/a")),
            },
            TypeProjection {
                path: SymbolId::of("/b"),
                parent: Some(SymbolId::of("/root")),
            },
        ];
        let planned = ids.iter().zip(&types).map(|(&id, ty)| (id, ty)).collect();
        let parents = [(ids[0], root), (ids[1], ids[0]), (ids[2], root)]
            .into_iter()
            .collect();
        let actual = owner.waves(&planned, &parents, root as usize + 1).unwrap();
        assert_eq!(
            actual,
            class_construction_waves(&parents, root as usize + 1).unwrap()
        );
        actual
    }
    #[test]
    fn changed_parent_cycle_declines_recipe_and_preserves_original_failure() {
        let owner = TypeConstruction::default();
        run(&owner, &[3, 4, 5], 2);
        let a = TypeProjection {
            path: SymbolId::of("/a"),
            parent: Some(SymbolId::of("/b")),
        };
        let b = TypeProjection {
            path: SymbolId::of("/b"),
            parent: Some(SymbolId::of("/a")),
        };
        let planned = [(3, &a), (4, &b)].into_iter().collect();
        let parents = [(3, 4), (4, 3)].into_iter().collect();
        assert_eq!(
            owner.waves(&planned, &parents, 3).unwrap_err(),
            class_construction_waves(&parents, 3).unwrap_err()
        );
        assert!(owner.current.lock().unwrap().is_none());
        run(&owner, &[3, 4, 5], 2);
    }
    #[test]
    fn symbolic_wave_owner_rebinds_dense_ids_and_declines_changed_order() {
        let owner = TypeConstruction::default();
        assert_eq!(run(&owner, &[3, 4, 5], 2), vec![vec![3, 5], vec![4]]);
        let first = owner.current.lock().unwrap().as_ref().unwrap().clone();
        assert_eq!(run(&owner, &[9, 10, 11], 8), vec![vec![9, 11], vec![10]]);
        assert!(Arc::ptr_eq(
            &first,
            owner.current.lock().unwrap().as_ref().unwrap()
        ));
        run(&owner, &[10, 9, 11], 8);
        assert!(!Arc::ptr_eq(
            &first,
            owner.current.lock().unwrap().as_ref().unwrap()
        ));
        let empty = BTreeMap::new();
        assert!(owner.waves(&empty, &BTreeMap::new(), 0).unwrap().is_empty());
    }
}
