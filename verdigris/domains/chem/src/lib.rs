//! `vg-chem`: the chemistry domain (`doc/rewrite/reagents.md` §4). Host-buildable, no dependencies.
//!
//! DM keeps what chemistry *is* (the reagent and reaction tables, the per-reagent effects, the holders and their atoms); the numbers
//! that run every chemistry step for every holder are here:
//!
//! - [`reaction`]: how far one step of a reaction goes in a holder: the stoichiometric limit, the rate (`HALF_LIFE`/`REACTION_RATE`),
//!   the yield limit, and the completion rule for tiny remainders.
//! - [`metabolism`]: one Life cycle of a metabolism holder, batched: each reagent's uptake this cycle, its accumulated dose, and
//!   whether (and how hard) it overdoses.
//!
//! The maths is `f32`, in the order DM did it, so the numbers are DM's to the last bit (pinned by
//! `code/modules/unit_tests/dq_chem_math_pins.dm`, recorded on the DM implementation).

pub mod metabolism;
pub mod reaction;
