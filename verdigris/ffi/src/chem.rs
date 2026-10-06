//! Binds for `vg_chem` (`doc/rewrite/reagents.md` §4): pure, stateless chemistry maths. Nothing is kept between calls, so no entity
//! and no world: DM sends a step's numbers and applies the answer to its holders as it always did.

// The reaction step's argument count is the DM call convention (one parameter per reaction setting); the warning is raised inside
// the bind macro's expansion, where an item-level allow does not reach (ffi/src/heat_regulator.rs).
#![allow(clippy::too_many_arguments)]

use byondapi::prelude::*;
use eyre::{Result, bail};
use vg_chem::metabolism::{self, Uptake};
use vg_chem::reaction::{self, Reactant, Step};

use crate::world::num;

/// How far one step of a reaction goes, in reaction units (`vg_chem::reaction::progress`; DM's `calc_reaction_progress()`).
/// `reactants` is a flat list `have, ratio, ...`. The caller still takes `min(limit, progress)`.
#[auxmacros::bind("/proc/chem_reaction_progress")]
fn chem_reaction_progress(
    limit: ByondValue,
    rate: ByondValue,
    multiplier: ByondValue,
    yield_: ByondValue,
    result_amount: ByondValue,
    product_have: ByondValue,
    min_reaction: ByondValue,
    reactants: ByondValue,
) -> Result<ByondValue> {
    let flat = if reactants.is_list() { reactants.get_list_values()? } else { Vec::new() };
    if flat.len() % 2 != 0 {
        bail!("reactants must hold 2 values per reactant");
    }
    let mut rs = Vec::with_capacity(flat.len() / 2);
    for pair in flat.chunks_exact(2) {
        rs.push(Reactant { have: num(&pair[0])?, ratio: num(&pair[1])? });
    }
    let step = Step {
        limit: num(&limit)?,
        rate: num(&rate)?,
        multiplier: if multiplier.is_num() { num(&multiplier)? } else { 1.0 },
        yield_: num(&yield_)?,
        result_amount: if result_amount.is_num() { num(&result_amount)? } else { 0.0 },
        product_have: if product_have.is_num() { num(&product_have)? } else { 0.0 },
        min_reaction: num(&min_reaction)?,
    };
    Ok(reaction::progress(&step, &rs).into())
}

/// Values per reagent in and out of [`chem_metabolism_cycle`].
const IN: usize = 7;
/// @dm-define CHEM_CYCLE_OUT
pub const CHEM_CYCLE_OUT: usize = 5;

/// One Life cycle of a metabolism holder (`vg_chem::metabolism::cycle`). `args` is flat, 7 values per reagent:
/// `volume, rate, dose, max_dose, overdose_at, overdose, overdose_mod`. Returns a flat list, 5 per reagent in the same order:
/// `removed, dose, max_dose, overdosing (0/1), overdose_injury`.
#[auxmacros::bind("/proc/chem_metabolism_cycle")]
fn chem_metabolism_cycle(args: ByondValue) -> Result<ByondValue> {
    let flat = args.get_list_values()?;
    if flat.len() % IN != 0 {
        bail!("args must hold {IN} values per reagent");
    }
    let mut uptakes = Vec::with_capacity(flat.len() / IN);
    for c in flat.chunks_exact(IN) {
        uptakes.push(Uptake {
            volume: num(&c[0])?,
            rate: num(&c[1])?,
            dose: num(&c[2])?,
            max_dose: num(&c[3])?,
            overdose_at: num(&c[4])?,
            overdose: num(&c[5])?,
            overdose_mod: num(&c[6])?,
        });
    }
    let mut out = Vec::with_capacity(uptakes.len() * CHEM_CYCLE_OUT);
    for t in metabolism::cycle(&uptakes) {
        out.push(ByondValue::from(t.removed));
        out.push(ByondValue::from(t.dose));
        out.push(ByondValue::from(t.max_dose));
        out.push(ByondValue::from(if t.overdosing { 1.0f32 } else { 0.0 }));
        out.push(ByondValue::from(t.overdose_injury));
    }
    let list = ByondValue::new_list()?;
    list.write_list(&out)?;
    Ok(list)
}

/// The base overdose injury of one uptake (`vg_chem::metabolism::overdose_injury`), for an overdose() called outside a holder's cycle.
#[auxmacros::bind("/proc/chem_overdose_injury")]
fn chem_overdose_injury(removed: ByondValue, overdose_mod: ByondValue, volume: ByondValue, overdose: ByondValue) -> Result<ByondValue> {
    let od = num(&overdose)?;
    if od <= 0.0 {
        return Ok(0.0f32.into());
    }
    Ok(metabolism::overdose_injury(num(&removed)?, num(&overdose_mod)?, num(&volume)?, od).into())
}
