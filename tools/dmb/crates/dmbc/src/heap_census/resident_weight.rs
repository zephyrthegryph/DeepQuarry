//! Conservative resident admission from actual accessible owners. Unknown private
//! sidecars decline memory retention; disk replay remains independently available.
use super::*;
use crate::lowering_memo::ResolverRead;
use dm_ir::{ReadDomain, ResolvedMeaning};
fn source(c: &mut HeapCensus, location: &dm_tree::frontend::SourceLocation) {
    let owner = "resident_source";
    c.arc_path(owner, &location.path);
    c.arc_text(owner, &location.semantic_path);
    c.slice(owner, &location.include_chain, true);
    if c.arc_object(owner, &location.macro_expansions)
        && c.vec_payload(owner, &location.macro_expansions)
    {
        for expansion in location.macro_expansions.iter() {
            c.macro_trace(owner, expansion)
        }
    }
}
pub(super) fn answer(c: &mut HeapCensus, value: &ResolvedMeaning) {
    let owner = "resident_reads";
    match value {
        ResolvedMeaning::Symbols(values) => {
            c.vec_payload(owner, values);
        }
        ResolvedMeaning::Members(values) => {
            if c.vec_payload(owner, values) {
                for value in values {
                    answer(c, value)
                }
            }
        }
        ResolvedMeaning::Value(value) => c.semantic_value(owner, value),
        ResolvedMeaning::Member { data, .. } => {
            if c.arc_object(owner, data) {
                c.declaration(data)
            }
        }
        ResolvedMeaning::ProcedureStatic(value) => {
            if c.arc_object(owner, value) {
                if let Some(array) = &value.declared_array {
                    c.array(owner, array)
                }
                match &value.initializer {
                    dm_ir::InitializerValue::Expression(e) => c.expression(owner, e),
                    dm_ir::InitializerValue::ArrayAllocation(a) => c.array(owner, a),
                    dm_ir::InitializerValue::NoAuthoredValue => (),
                }
            }
        }
        ResolvedMeaning::Unsupported(_)
        | ResolvedMeaning::Missing
        | ResolvedMeaning::Presence(_)
        | ResolvedMeaning::DeclaredType(_)
        | ResolvedMeaning::InstanceField { .. }
        | ResolvedMeaning::Slot { .. }
        | ResolvedMeaning::Symbol(_)
        | ResolvedMeaning::IntrinsicProc { .. }
        | ResolvedMeaning::RetainedProc { .. }
        | ResolvedMeaning::Resource { .. } => (),
    }
}
fn nodes<K, V>(map: &BTreeMap<K, V>) -> usize {
    // Charge a complete maximum-fanout node PER entry, intentionally above
    // normal occupancy, including key/value inline slots and allocation padding.
    map.len()
        .saturating_mul(size_of::<(K, V)>().saturating_mul(16).saturating_add(512))
}
pub(crate) fn procedure(
    unit: &crate::lowering::LoweredUnit,
    relative: &Vec<usize>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    if !unit.code.modified_instances.is_empty() || !unit.source_helpers.is_empty() {
        return None;
    }
    let mut c = HeapCensus::new("resident_admission");
    c.resolver_code(&unit.code);
    if let Some(references) = &unit.selected_references {
        if c.arc_object("resident_reference_selections", references)
            && c.vec_payload("resident_reference_selections", &references.references)
        {
            for reference in &references.references {
                c.vec_payload("resident_reference_selections", &reference.path);
            }
        }
    }
    c.vec_payload("resident_helpers", &unit.source_helpers);
    // resolver_code's sole fixed-map limitation is covered explicitly below;
    // private modified values were rejected before this traversal.
    c.owner("lowered_code").unknown.remove(
        "resolver BTreeMap nodes and modified-instance nested expression buffers not exposed",
    );
    c.procedure_metadata("resident_metadata", &unit.metadata);
    if let Some(abi) = &unit.abi {
        c.abi(abi)
    }
    c.debug("resident_debug", &unit.debug_origins);
    source(&mut c, &unit.origin.source);
    c.slice("resident_source", &unit.origin.ast_path, true);
    if c.slice(
        "resident_source",
        &unit.origin.setting_context_origins,
        true,
    ) {
        for origin in unit.origin.setting_context_origins.iter() {
            source(&mut c, origin)
        }
    }
    c.vec_payload("resident_relative", relative);
    // insert_with converts these Vecs into exact Arc slices; original capacities
    // are conservative and avoid assuming the conversion reuses their backing.
    c.vec_payload("resident_reads", reads);
    c.vec_payload("resident_versions", versions);
    for read in reads {
        answer(&mut c, &read.answer)
    }
    let allocations = c.buffer_encounters;
    let report = c.finish();
    if report.owners.iter().any(|owner| !owner.unknown.is_empty()) {
        return None;
    }
    let capacity = usize::try_from(report.unique_known_capacity_bytes).ok()?;
    Some(
        capacity
            .saturating_add(allocations.saturating_mul(64))
            .saturating_add(size_of::<crate::lowering_memo::CachedProcedure>())
            .saturating_add(key.len())
            .saturating_add(4096)
            .saturating_add(nodes(&unit.code.procedure_values))
            .saturating_add(nodes(&unit.code.procedure_statics))
            .saturating_add(nodes(&unit.code.slots))
            .saturating_add(nodes(&unit.code.resources))
            .saturating_add(nodes(&unit.code.instances)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Source;
    impl dm_preprocess::SourceProvider for Source {
        fn read(&self, _: &std::path::Path) -> Result<String, String> {
            Ok("/proc/p()\n    return 1\n".into())
        }
    }
    struct Host;
    impl dm_ir::Resolver for Host {
        fn resolve(&self, q: dm_ir::ResolveQuery) -> ResolvedMeaning {
            ResolvedMeaning::Unsupported(q)
        }
    }
    struct Policy;
    impl crate::lowering::AbiPolicy for Policy {
        fn inputs(
            &self,
            _: crate::lowering::UnitIdentity,
            _: &dm_ir::ProcedureMetadata,
            _: &dm_ir::SymbolTable,
            _: &dm_tree::frontend::SourceLocation,
        ) -> Result<dm_codegen_byond::lower_resolver::ProcedureInputs, String> {
            Ok(Default::default())
        }
    }
    #[test]
    fn separate_empty_list_arcs_still_charge_control_encounters() {
        let first = dm_ir::SemanticValue::List(Arc::from([]));
        let second = dm_ir::SemanticValue::List(Arc::from([]));
        let mut census = HeapCensus::new("empty");
        census.semantic_value("empty", &first);
        let once = census.buffer_encounters;
        census.semantic_value("empty", &second);
        assert!(once > 0);
        assert!(census.buffer_encounters > once);
        assert_eq!(census.finish().unique_known_capacity_bytes, 0);
    }
    #[test]
    fn actual_operand_capacity_increases_resident_charge_and_unknown_sidecar_declines() {
        let frontend = dm_tree::frontend::build(
            std::path::Path::new("project.dme"),
            &Source,
            &BTreeMap::new(),
            1,
        )
        .unwrap();
        let mut batch =
            crate::lowering::lower_frontend(&frontend, &Host, &Policy, Default::default());
        assert!(batch.diagnostics.is_empty());
        let unit = &mut batch.units[0];
        let args = (Vec::new(), Vec::new(), Vec::new());
        let before = procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap();
        unit.code.procedure.code.items.reserve(10000);
        let after = procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap();
        assert!(after > before + 1000);
        unit.source_helpers
            .push(crate::argument_sources::LoweredHelper {
                owner: unit.identity,
                argument: 0,
                code: unit.code.clone(),
                debug_origins: unit.debug_origins.clone(),
            });
        assert!(procedure(unit, &args.0, b"key", &args.1, &args.2).is_none());

        let value =
            ResolvedMeaning::Value(dm_ir::SemanticValue::Text(Arc::from(b"text".as_slice())));
        let mut census = HeapCensus::new("read");
        answer(&mut census, &value);
        assert!(census.finish().unique_known_capacity_bytes >= 4);
    }
}
