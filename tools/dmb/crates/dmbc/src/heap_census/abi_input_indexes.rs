//! Shared scalar backing charge for production ABI retention and its test adapter.
use dm_codegen_byond::ProcedureInputs;
use std::mem::size_of;

/// Exposed usable HashMap capacity plus modeled scalar hash/set backing.
/// This is a logical admission envelope, not a physical allocator measurement.
pub(crate) fn charge(inputs: &ProcedureInputs) -> Option<usize> {
    let capacity = inputs.parameter_types.capacity();
    let map = if capacity == 0 {
        0
    } else {
        capacity
            .checked_mul(2)?
            .checked_add(1)?
            .checked_mul(size_of::<(String, String)>().checked_add(1)?)?
            .checked_add(64)?
    };
    map.checked_add(
        inputs
            .readonly_parameters
            .len()
            .checked_mul(16 * size_of::<u32>() + 512)?,
    )
}
