//! Zero-frame initializer code: actual immutable owners, no byte-codec estimate.
use super::*;
use crate::lowering_memo::ResolverRead;
use crate::modified_initializers::ExpressionRecipe;
use dm_codegen_byond::lower_resolver::ResolverProc;
use dm_ir::ReadDomain;

impl HeapCensus {
    pub(crate) fn initializer_fragment_recipes(
        &mut self,
        recipes: &Vec<ExpressionRecipe>,
        references: &Vec<dm_ir::SymRef>,
    ) {
        let owner = "resident_initializer_fragment.recipes";
        self.vec_payload(owner, recipes);
        self.vec_payload(owner, references);
        for recipe in recipes {
            let (path, canonical) = recipe.retained_parts();
            self.vec_payload(owner, path);
            self.slice(owner, canonical, true);
        }
    }
}

fn nodes<K, V>(map: &BTreeMap<K, V>) -> usize {
    // Private BTree node layout is not an exact census capacity. Admission
    // deliberately charges a full maximum-fanout node for every live entry.
    map.len()
        .saturating_mul(size_of::<(K, V)>().saturating_mul(16).saturating_add(512))
}
pub(crate) fn weight(
    code: &ResolverProc,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
    recipes: &Vec<ExpressionRecipe>,
    references: &Vec<dm_ir::SymRef>,
) -> Option<usize> {
    // Private modifier AST/resource owners require current-source recipes and
    // a complete ownership walker. Do not admit them with a codec-size guess.
    if !code.modified_instances.is_empty() {
        return None;
    }
    let mut census = HeapCensus::new("resident_initializer_fragment_admission");
    census.resolver_code(code);
    census.initializer_fragment_recipes(recipes, references);
    census.owner("lowered_code").unknown.remove(
        "resolver BTreeMap nodes and modified-instance nested expression buffers not exposed",
    );
    census.vec_payload("resident_initializer_fragment.reads", reads);
    census.vec_payload("resident_initializer_fragment.versions", versions);
    for read in reads {
        super::resident_weight::answer(&mut census, &read.answer);
    }
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
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(size_of::<ResolverProc>())
            .saturating_add(key.len())
            .saturating_add(4096)
            .saturating_add(nodes(&code.procedure_values))
            .saturating_add(nodes(&code.procedure_statics))
            .saturating_add(nodes(&code.slots))
            .saturating_add(nodes(&code.resources))
            .saturating_add(nodes(&code.instances)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn actual_frame_string_capacity_and_fixed_resource_indexes_increase_charge() {
        let mut code = ResolverProc {
            procedure: Default::default(),
            slots: Default::default(),
            resources: Default::default(),
            instances: Default::default(),
            procedure_values: Default::default(),
            procedure_statics: Default::default(),
            modified_instances: Default::default(),
        };
        let reads = Vec::new();
        let versions = Vec::new();
        let recipes = Vec::new();
        let mut references = Vec::new();
        let base = weight(&code, b"key", &reads, &versions, &recipes, &references).unwrap();
        code.procedure
            .local_names
            .push(String::with_capacity(10000));
        code.resources.insert(dm_ir::SymbolId::of("resource"), 123);
        let after = weight(&code, b"key", &reads, &versions, &recipes, &references).unwrap();
        assert!(after >= base + 10000);
        assert_eq!(
            weight(
                &code,
                b"longer-key",
                &reads,
                &versions,
                &recipes,
                &references
            )
            .unwrap()
                - after,
            7
        );
        let descriptor = dm_ir::ModifiedInstance::capture_with_resources(
            dm_ir::SymbolId::of("/obj"),
            dm_ir::SymbolId::of("/"),
            None,
            &[],
            |_| None,
            None,
            |_| Err("unexpected resource".into()),
        )
        .unwrap();
        code.modified_instances.insert(
            dm_ir::SymRef::Instance(dm_ir::SymbolId::of("modified")),
            dm_codegen_byond::lower_resolver::CapturedModifiedInstance {
                descriptor,
                field_origins: Vec::new(),
                origin: None,
                source_span: None,
            },
        );
        assert!(weight(&code, b"key", &reads, &versions, &recipes, &references).is_none());
        code.modified_instances.clear();
        references.reserve_exact(1000);
        assert!(
            weight(&code, b"key", &reads, &versions, &recipes, &references).unwrap()
                >= after + 1000 * size_of::<dm_ir::SymRef>()
        );
    }
}
