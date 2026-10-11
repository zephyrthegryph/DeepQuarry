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
            c.slice(owner, values, true);
        }
        ResolvedMeaning::Members(values) => {
            if c.slice(owner, values, true) {
                for value in values.iter() {
                    answer(c, value)
                }
            }
        }
        ResolvedMeaning::Value(value) => c.semantic_value(owner, value),
        ResolvedMeaning::Member { data, .. } | ResolvedMeaning::Declaration { data, .. } => {
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
fn code(c: &mut HeapCensus, code: &dm_codegen_byond::lower_resolver::ResolverProc) -> usize {
    c.resolver_code(code);
    let owner = "resident_modified";
    let mut overhead = nodes(&code.procedure_values)
        .saturating_add(nodes(&code.procedure_statics))
        .saturating_add(nodes(&code.slots))
        .saturating_add(nodes(&code.resources))
        .saturating_add(nodes(&code.instances))
        .saturating_add(nodes(&code.modified_instances));
    for captured in code.modified_instances.values() {
        let descriptor = &captured.descriptor;
        if c.slice(owner, descriptor.fields(), true) {
            for (name, value) in descriptor.fields() {
                c.string(owner, name);
                c.typed_expression(owner, value);
            }
        }
        // The public descriptor exposes every resource key/value. Its shared
        // map node capacity is private: charge a maximum-fanout node per row,
        // plus the Arc/map allocation even for an empty map.
        overhead = overhead
            .saturating_add(nodes(descriptor.resources()))
            .saturating_add(128);
        for name in descriptor.resources().keys() {
            c.string(owner, name);
        }
    }
    overhead
}
#[cfg(test)]
pub(crate) fn procedure(
    unit: &crate::lowering::LoweredUnit,
    relative: &Vec<crate::debug_sources::RelativeDebugAnchor>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    procedure_core(unit, relative, key, reads, |c| {
        c.vec_payload("resident_reads", reads);
        c.vec_payload("resident_versions", versions);
    })
}
pub(crate) fn procedure_shared(
    unit: &crate::lowering::LoweredUnit,
    relative: &Vec<crate::debug_sources::RelativeDebugAnchor>,
    key: &[u8],
    reads: &std::sync::Arc<[ResolverRead]>,
    versions: &std::sync::Arc<[(ReadDomain, u128)]>,
) -> Option<usize> {
    procedure_core(unit, relative, key, reads, |c| {
        c.slice("resident_reads", reads, true);
        c.slice("resident_versions", versions, true);
    })
}
fn procedure_core(
    unit: &crate::lowering::LoweredUnit,
    relative: &Vec<crate::debug_sources::RelativeDebugAnchor>,
    key: &[u8],
    reads: &[ResolverRead],
    ledger: impl FnOnce(&mut HeapCensus),
) -> Option<usize> {
    let mut c = HeapCensus::new("resident_admission");
    let mut map_overhead = code(&mut c, &unit.code);
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
    for helper in &unit.source_helpers {
        map_overhead = map_overhead.saturating_add(code(&mut c, &helper.code));
        c.debug("resident_helper_debug", &helper.debug_origins);
    }
    // Every resolver map has a conservative node charge above; modified
    // expression buffers use the same complete typed syntax walker.
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
    ledger(&mut c);
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
            .saturating_add(map_overhead),
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
    fn actual_operand_and_helper_capacity_increases_resident_charge() {
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
        let with_helper = procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap();
        assert!(with_helper > after);
        unit.source_helpers[0]
            .code
            .procedure
            .code
            .items
            .reserve(20000);
        assert!(procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap() > with_helper);
        let before_modified = procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap();
        let expression = dm_syntax::Expr {
            kind: dm_syntax::ExprKind::Group(Box::new(dm_syntax::Expr {
                kind: dm_syntax::ExprKind::Literal("x".repeat(10000)),
                span: dm_syntax::Span::new(0, 10000),
            })),
            span: dm_syntax::Span::new(0, 10000),
        };
        let descriptor = dm_ir::ModifiedInstance::capture(
            dm_ir::SymbolId::of("/obj"),
            dm_ir::SymbolId::of("/"),
            None,
            &[(String::from("field"), expression)],
        );
        unit.source_helpers[0].code.modified_instances.insert(
            dm_ir::SymRef::Instance(dm_ir::SymbolId::of("modified")),
            dm_codegen_byond::lower_resolver::CapturedModifiedInstance {
                descriptor,
                field_origins: vec![Some(0)],
                origin: Some(0),
                source_span: None,
            },
        );
        assert!(
            procedure(unit, &args.0, b"key", &args.1, &args.2).unwrap() > before_modified + 10000
        );

        let value =
            ResolvedMeaning::Value(dm_ir::SemanticValue::Text(Arc::from(b"text".as_slice())));
        let mut census = HeapCensus::new("read");
        answer(&mut census, &value);
        assert!(census.finish().unique_known_capacity_bytes >= 4);
    }
}
