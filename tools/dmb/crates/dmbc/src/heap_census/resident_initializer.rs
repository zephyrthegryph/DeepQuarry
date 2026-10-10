//! Conservative charge of retained initializer semantics, excluding current ASTs.
use super::*;
use crate::initializer_policy::DefaultValue;
use crate::lowering_memo::ResolverRead;
use dm_ir::ReadDomain;

pub(crate) fn weight(
    default: &DefaultValue,
    dimensions: Option<&Arc<[u16]>>,
    token_key: Option<&Vec<u8>>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_initializer_admission");
    match default {
        DefaultValue::Transform(_) => {}
        DefaultValue::Scalar(value) => census.semantic_value("resident_initializer.default", value),
        DefaultValue::InitializerExpression { canonical, .. } => {
            census.slice("resident_initializer.canonical", canonical, true);
        }
    }
    if let Some(dimensions) = dimensions {
        census.slice("resident_initializer.dimensions", dimensions, true);
    }
    if let Some(token_key) = token_key {
        census.vec_payload("resident_initializer.token_key", token_key);
    }
    // The store converts these vectors to exact Arc slices. Charging original
    // capacities conservatively covers either reused or newly allocated backing.
    census.vec_payload("resident_initializer.reads", reads);
    census.vec_payload("resident_initializer.versions", versions);
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
    let capacity = usize::try_from(report.unique_known_capacity_bytes).ok()?;
    // The private recipe's fixed envelope is bounded by these field slots. Its
    // index/control/allocator padding is deliberately conservative, not measured
    // heap usage. Every encounter includes zero-length Arc owners.
    let envelope = size_of::<DefaultValue>()
        .saturating_add(size_of::<Option<crate::initializer_policy::Phase>>())
        .saturating_add(size_of::<Option<(bool, Arc<[u16]>)>>())
        .saturating_add(size_of::<Option<Vec<u8>>>());
    Some(
        capacity
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(envelope)
            .saturating_add(key.len())
            .saturating_add(4096),
    )
}

/// Modifier facts are fixed Copy scalars. Reuse the same actual-ledger traversal;
/// its initializer envelope is intentionally a conservative upper charge here.
pub(crate) fn modifier_weight(
    input: &Arc<dm_ir::InitializerWrite>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let envelope = weight(
        &DefaultValue::Scalar(dm_ir::SemanticValue::Null),
        None,
        None,
        key,
        reads,
        versions,
    )?;
    let mut census = HeapCensus::new("resident_modifier_input");
    census.shared_initializer_write("resident_modifier_input", input);
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    Some(
        envelope
            .saturating_add(usize::try_from(report.unique_known_capacity_bytes).ok()?)
            .saturating_add(encounters.saturating_mul(64)),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn actual_token_capacity_and_nested_semantic_owners_raise_initializer_charge() {
        let default = DefaultValue::Scalar(dm_ir::SemanticValue::Null);
        let small = Vec::new();
        let mut large = Vec::new();
        large.reserve_exact(10000);
        let empty = (Vec::new(), Vec::new());
        let before = weight(&default, None, Some(&small), b"key", &empty.0, &empty.1).unwrap();
        let after = weight(&default, None, Some(&large), b"key", &empty.0, &empty.1).unwrap();
        assert!(after >= before + 10000);
        let nested = DefaultValue::Scalar(dm_ir::SemanticValue::List(Arc::from([(
            Some(dm_ir::SemanticValue::Text(Arc::from(b"key".as_slice()))),
            dm_ir::SemanticValue::Text(Arc::from(b"value".as_slice())),
        )])));
        assert!(weight(&nested, None, None, b"key", &empty.0, &empty.1).unwrap() > before);
        let dimensions: Arc<[u16]> = Arc::from([2, 4]);
        assert!(
            weight(
                &default,
                Some(&dimensions),
                None,
                b"key",
                &empty.0,
                &empty.1
            )
            .unwrap()
                > weight(&default, None, None, b"key", &empty.0, &empty.1).unwrap()
        );
    }
    #[test]
    fn unknown_modified_instance_ownership_declines_initializer_retention() {
        let value = dm_ir::ModifiedInstance::capture_with_resources(
            dm_ir::SymbolId::of("/obj"),
            dm_ir::SymbolId::of("/"),
            None,
            &[],
            |_| None,
            None,
            |_| Err("unexpected resource".into()),
        )
        .unwrap();
        let default = DefaultValue::Scalar(dm_ir::SemanticValue::ModifiedInstance(Arc::new(value)));
        assert!(weight(&default, None, None, b"key", &Vec::new(), &Vec::new()).is_none());
    }
}

/// Actual shared expression/source owners; caller adds this to semantic admission.
pub(crate) fn syntax_weight(source: &Arc<str>, expression: &Arc<dm_syntax::Expr>) -> Option<usize> {
    let mut census = HeapCensus::new("resident_initializer_syntax");
    census.arc_text("resident_initializer.source", source);
    if census.arc_object("resident_initializer.expression", expression) {
        census.typed_expression("resident_initializer.expression", expression);
    }
    let encounters = census.buffer_encounters;
    let report = census.finish();
    if report.unknown_capacity_payload_bytes != 0
        || report.owners.iter().any(|owner| !owner.unknown.is_empty())
    {
        return None;
    }
    usize::try_from(report.unique_known_capacity_bytes)
        .ok()?
        .checked_add(encounters.checked_mul(64)?)
        .and_then(|bytes| bytes.checked_add(256))
}
