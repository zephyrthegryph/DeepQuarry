//! Actual ABI/input owners, with separately conservative opaque index charges.
use super::*;
use crate::{lowering_memo::ResolverRead, procedure_policy::PreparedAbi};
use dm_codegen_byond::lower_resolver::ProcedureInputs;
use dm_ir::ReadDomain;

pub(crate) fn weight(
    inputs: &ProcedureInputs,
    abi: &Arc<PreparedAbi>,
    key: &[u8],
    reads: &Vec<ResolverRead>,
    versions: &Vec<(ReadDomain, u128)>,
) -> Option<usize> {
    // Exhaustive destructuring makes a newly owned input field require an audit.
    let ProcedureInputs {
        procedure_identity: _,
        current_proc_path,
        current_type_path,
        parameters,
        parameter_type_flags,
        parameter_value_sources,
        parameter_defaults,
        parameter_types,
        readonly_parameters,
        resource_search_context: _,
    } = inputs;
    let mut census = HeapCensus::new("resident_abi_admission");
    let owner = "resident_abi.inputs";
    for path in [current_proc_path, current_type_path].into_iter().flatten() {
        census.string(owner, path);
    }
    census.strings(owner, parameters);
    census.vec_payload(owner, parameter_type_flags);
    census.vec_payload(owner, parameter_value_sources);
    census.vec_payload(owner, parameter_defaults);
    for default in parameter_defaults.iter().flatten() {
        census.string(owner, default);
    }
    for (name, path) in parameter_types {
        census.string(owner, name);
        census.string(owner, path);
    }
    // std exposes usable HashMap capacity, not its private bucket allocation.
    // The bucket upper bound and deliberately loose BTree node allowance are
    // admission charges, never presented as exact census payload measurements.
    let map_charge = if parameter_types.capacity() == 0 {
        0
    } else {
        parameter_types
            .capacity()
            .saturating_mul(2)
            .saturating_add(1)
            .saturating_mul(size_of::<(String, String)>().saturating_add(1))
            .saturating_add(64)
    };
    let set_charge = readonly_parameters
        .len()
        .saturating_mul(16 * size_of::<u32>() + 512);
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
            .saturating_add(map_charge)
            .saturating_add(set_charge)
            .saturating_add(size_of::<ProcedureInputs>())
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
        let mut inputs = ProcedureInputs::default();
        let reads = Vec::new();
        let versions = Vec::new();
        let base = weight(&inputs, &abi, b"key", &reads, &versions).unwrap();
        inputs.parameters.reserve_exact(100);
        inputs
            .parameter_defaults
            .push(Some(String::with_capacity(10000)));
        inputs
            .parameter_types
            .insert("argument".into(), "/obj".into());
        inputs.readonly_parameters.insert(0);
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
