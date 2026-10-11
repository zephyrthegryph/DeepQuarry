//! Actual ABI/input owners, with separately conservative opaque index charges.
use super::*;
use crate::{lowering_memo::ResolverRead, procedure_policy::PreparedAbi};
use dm_codegen_byond::lower_resolver::ProcedureInputs;
use dm_ir::ReadDomain;

pub(crate) fn weight(
    inputs: &Arc<ProcedureInputs>,
    abi: &Arc<PreparedAbi>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    let mut census = HeapCensus::new("resident_abi_admission");
    census.shared_procedure_inputs(inputs);
    // std exposes usable HashMap capacity, not its private bucket allocation.
    // The bucket upper bound and deliberately loose BTree node allowance are
    // admission charges, never presented as exact census payload measurements.
    let indexes = super::abi_certificates::input_indexes::charge(inputs)?;
    census.abi(abi);
    census.vec_payload("resident_abi.reads", reads);
    census.vec_payload("resident_abi.versions", versions);
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
            .saturating_add(indexes)
            // Conservative admission includes shared Arc control overhead;
            // diagnostic census still reports actual exposed payload only.
            .saturating_add(2 * size_of::<usize>() + std::mem::align_of::<ProcedureInputs>())
            .saturating_add(encounters.saturating_mul(64))
            .saturating_add(key.len())
            .saturating_add(4096),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn retained_input_capacity_and_abi_metadata_are_charged_without_serialization() {
        let abi = Arc::new(PreparedAbi {
            layout: Default::default(),
            argument_sources: Vec::new(),
            source_helpers: Vec::new(),
        });
        let mut inputs = Arc::new(ProcedureInputs::default());
        let reads = Vec::new();
        let versions = Vec::new();
        let base = weight(&inputs, &abi, b"key", &reads, &versions).unwrap();
        Arc::make_mut(&mut inputs).parameters.reserve_exact(100);
        Arc::make_mut(&mut inputs)
            .parameter_defaults
            .push(Some(String::with_capacity(10000)));
        Arc::make_mut(&mut inputs)
            .parameter_types
            .insert("argument".into(), "/obj".into());
        Arc::make_mut(&mut inputs).readonly_parameters.insert(0);
        let expanded = weight(&inputs, &abi, b"key", &reads, &versions).unwrap();
        assert!(expanded >= base + 10000 + 100 * size_of::<String>());
        let mut larger_abi = (*abi).clone();
        larger_abi.layout.description = Some(Vec::with_capacity(20000));
        let larger = weight(&inputs, &Arc::new(larger_abi), b"key", &reads, &versions).unwrap();
        assert!(larger >= expanded + 20000);
        assert_eq!(
            weight(&inputs, &abi, b"longer-key", &reads, &versions).unwrap() - expanded,
            7
        );
    }
}
