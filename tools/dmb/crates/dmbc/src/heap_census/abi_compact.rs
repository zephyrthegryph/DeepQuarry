//! Charges exposed ABI payloads, not the separately retained shared engine.
//! Private scalar maps use conservative logical envelopes. Unknown nested
//! answers decline; the daemon's physical pressure monitor remains mandatory.
use super::*;
use crate::driver_facts::abi_artifacts::{
    observations::{Answer, Boundary, Domain, Query},
    Artifact, UnitArtifact,
};

fn map_charge<K, V>(len: usize) -> Option<usize> {
    len.checked_mul(size_of::<(K, V)>().checked_add(64)?.checked_mul(16)?)
}
fn boundary(c: &mut HeapCensus, value: &Boundary) {
    if let Boundary::Intrinsic { layout, .. } = value {
        for bytes in [&layout.display_name, &layout.description]
            .into_iter()
            .flatten()
        {
            c.vec_payload("compact.abi_boundary", bytes);
        }
        if let dm_codegen_byond::procedure_abi::Category::Text(bytes) = &layout.category {
            c.vec_payload("compact.abi_boundary", bytes);
        }
    }
}
fn receipt(
    c: &mut HeapCensus,
    reads: &dm_session::Receipt<Query, Answer, Domain>,
) -> Option<usize> {
    if !c.receipt("compact.abi_reads", reads) {
        return Some(0);
    }
    let mut private = 0usize;
    for read in reads.iter() {
        match &read.answer {
            Answer::Unissued => (),
            Answer::Semantic(answer) => super::super::resident_weight::answer(c, answer),
            Answer::Inputs(inputs) => {
                if inputs.engine.upgrade().is_none() {
                    return None;
                }
                if c.arc_object("compact.abi_inputs", inputs) {
                    c.procedure_metadata("compact.abi_metadata", &inputs.metadata);
                    if let Some(ancestry) = &inputs.ancestry {
                        c.slice("compact.abi_ancestry", ancestry, true);
                    }
                    if let Some(abi) = &inputs.predecessor {
                        c.abi(abi);
                    }
                    boundary(c, &inputs.boundary);
                    // Weak issuer handle/control allocation only; no decoded
                    // engine graph is retained through this receipt.
                    private = private.checked_add(
                        size_of::<crate::runner_host::EnginePayload>().checked_add(64)?,
                    )?;
                }
            }
            Answer::BatchInputs(inputs) => {
                if inputs.engine.upgrade().is_none() {
                    return None;
                }
                if c.arc_object("compact.abi_batch_inputs", inputs) {
                    c.callable_abi_graph(&inputs.graph);
                    for item in inputs.boundaries.values() {
                        boundary(c, item);
                    }
                    private = private
                        .checked_add(map_charge::<crate::lowering::UnitIdentity, Boundary>(
                            inputs.boundaries.len(),
                        )?)?
                        .checked_add(
                            size_of::<crate::runner_host::EnginePayload>().checked_add(64)?,
                        )?;
                }
            }
        }
    }
    Some(private)
}
fn unit(c: &mut HeapCensus, value: &Arc<UnitArtifact>) -> Option<usize> {
    if !c.arc_object("compact.abi_unit", value) {
        return Some(0);
    }
    c.shared_procedure_inputs(&value.inputs);
    c.abi(&value.abi);
    if let Some(canonical) = &value.canonical {
        c.prepared_canonical(canonical);
    }
    map_charge::<String, String>(value.inputs.parameter_types.len())?.checked_add(map_charge::<
        u32,
        (),
    >(
        value.inputs.readonly_parameters.len(),
    )?)
}
impl crate::driver_facts::AbiArtifacts {
    pub(crate) fn compact_payload_charge(
        key: &Arc<[u8]>,
        reads: &dm_session::Receipt<Query, Answer, Domain>,
        versions: &Arc<[(Domain, u128)]>,
        value: &Arc<Artifact>,
    ) -> Option<usize> {
        let mut c = HeapCensus::new("compact_abi_payload_charge");
        c.slice("compact.key", key, true);
        c.slice("compact.versions", versions, true);
        let mut private = receipt(&mut c, reads)?;
        c.arc_object("compact.abi_artifact", value);
        match value.as_ref() {
            Artifact::Unit(value) => private = private.checked_add(unit(&mut c, value)?)?,
            Artifact::Batch(recipe) => {
                // Dense current bindings are a recreatable facade; escaped readers
                // keep their owners. Detach and drop outside this mutex.
                let detached = recipe
                    .binding
                    .lock()
                    .unwrap_or_else(|e| e.into_inner())
                    .take();
                drop(detached);
                if c.arc_object("compact.abi_recipe", recipe) {
                    c.slice("compact.abi_units", &recipe.units, true);
                    for (_, value) in recipe.units.iter() {
                        private = private.checked_add(unit(&mut c, value)?)?;
                    }
                    c.slice("compact.abi_rows", &recipe.rows, true);
                    for row in recipe.rows.iter() {
                        private = private
                            .checked_add(unit(&mut c, &row.unit)?)?
                            .checked_add(receipt(&mut c, &row.reads)?)?;
                        c.slice("compact.abi_row_versions", &row.versions, true);
                    }
                    c.vec_payload("compact.abi_keys", &recipe.keys);
                    for key in &recipe.keys {
                        c.slice("compact.abi_key", key, true);
                    }
                }
            }
        }
        super::super::initializer_artifacts::compact_charge(c, private)
    }
}
