//! The numeric gas registry.
//!
//! Every gas has a fixed integer ID, generated into DM as `GAS_ID_<NAME>` by the
//! `@dm-define` scanner. DM passes these numbers across the FFI; strings never
//! cross it on a hot path (verdigris/README.md, rule 2). `GAS_PATHS` is the
//! name<->id table for registration, admin tools and the UI. Adding a gas means
//! adding a constant here, its path in `GAS_PATHS`, and `idx = GAS_ID_<NAME>` on
//! its `/datum/gas` subtype.

use super::GasIDX;

// The constants are `usize` (= `GasIDX`) so the @dm-define scanner can read them.

/// `/datum/gas/oxygen`.
/// @dm-define GAS_ID_OXYGEN
pub const GAS_OXYGEN: usize = 0;

/// `/datum/gas/nitrogen`.
/// @dm-define GAS_ID_NITROGEN
pub const GAS_NITROGEN: usize = 1;

/// `/datum/gas/carbon_dioxide`.
/// @dm-define GAS_ID_CARBON_DIOXIDE
pub const GAS_CARBON_DIOXIDE: usize = 2;

/// `/datum/gas/plasma`.
/// @dm-define GAS_ID_PLASMA
pub const GAS_PLASMA: usize = 3;

/// `/datum/gas/water_vapor`.
/// @dm-define GAS_ID_WATER_VAPOR
pub const GAS_WATER_VAPOR: usize = 4;

/// `/datum/gas/hypernoblium`.
/// @dm-define GAS_ID_HYPERNOBLIUM
pub const GAS_HYPERNOBLIUM: usize = 5;

/// `/datum/gas/nitrous_oxide`.
/// @dm-define GAS_ID_NITROUS_OXIDE
pub const GAS_NITROUS_OXIDE: usize = 6;

/// `/datum/gas/nitrium`.
/// @dm-define GAS_ID_NITRIUM
pub const GAS_NITRIUM: usize = 7;

/// `/datum/gas/tritium`.
/// @dm-define GAS_ID_TRITIUM
pub const GAS_TRITIUM: usize = 8;

/// `/datum/gas/bz`.
/// @dm-define GAS_ID_BZ
pub const GAS_BZ: usize = 9;

/// `/datum/gas/pluoxium`.
/// @dm-define GAS_ID_PLUOXIUM
pub const GAS_PLUOXIUM: usize = 10;

/// `/datum/gas/miasma`.
/// @dm-define GAS_ID_MIASMA
pub const GAS_MIASMA: usize = 11;

/// `/datum/gas/freon`.
/// @dm-define GAS_ID_FREON
pub const GAS_FREON: usize = 12;

/// `/datum/gas/hydrogen`.
/// @dm-define GAS_ID_HYDROGEN
pub const GAS_HYDROGEN: usize = 13;

/// `/datum/gas/healium`.
/// @dm-define GAS_ID_HEALIUM
pub const GAS_HEALIUM: usize = 14;

/// `/datum/gas/proto_nitrate`.
/// @dm-define GAS_ID_PROTO_NITRATE
pub const GAS_PROTO_NITRATE: usize = 15;

/// `/datum/gas/zauker`.
/// @dm-define GAS_ID_ZAUKER
pub const GAS_ZAUKER: usize = 16;

/// `/datum/gas/halon`.
/// @dm-define GAS_ID_HALON
pub const GAS_HALON: usize = 17;

/// `/datum/gas/helium`.
/// @dm-define GAS_ID_HELIUM
pub const GAS_HELIUM: usize = 18;

/// `/datum/gas/antinoblium`.
/// @dm-define GAS_ID_ANTINOBLIUM
pub const GAS_ANTINOBLIUM: usize = 19;

/// `/datum/gas/methane`.
/// @dm-define GAS_ID_METHANE
pub const GAS_METHANE: usize = 20;

/// `/datum/gas/volatile_fuel`.
/// @dm-define GAS_ID_VOLATILE_FUEL
pub const GAS_VOLATILE_FUEL: usize = 21;

/// Number of registered gases.
/// @dm-define GAS_ID_COUNT
pub const GAS_COUNT: usize = 22;

/// DM type path of each gas, indexed by its ID.
pub const GAS_PATHS: [&str; GAS_COUNT] = [
	"/datum/gas/oxygen",
	"/datum/gas/nitrogen",
	"/datum/gas/carbon_dioxide",
	"/datum/gas/plasma",
	"/datum/gas/water_vapor",
	"/datum/gas/hypernoblium",
	"/datum/gas/nitrous_oxide",
	"/datum/gas/nitrium",
	"/datum/gas/tritium",
	"/datum/gas/bz",
	"/datum/gas/pluoxium",
	"/datum/gas/miasma",
	"/datum/gas/freon",
	"/datum/gas/hydrogen",
	"/datum/gas/healium",
	"/datum/gas/proto_nitrate",
	"/datum/gas/zauker",
	"/datum/gas/halon",
	"/datum/gas/helium",
	"/datum/gas/antinoblium",
	"/datum/gas/methane",
	"/datum/gas/volatile_fuel",
];

/// The ID of the gas with this DM type path.
#[must_use]
pub fn gas_id_for_path(path: &str) -> Option<GasIDX> {
	GAS_PATHS.iter().position(|p| *p == path)
}

/// The DM type path of a gas ID.
#[must_use]
pub fn gas_path(idx: GasIDX) -> Option<&'static str> {
	GAS_PATHS.get(idx).copied()
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn ids_match_the_path_table() {
		assert_eq!(gas_id_for_path("/datum/gas/oxygen"), Some(GAS_OXYGEN));
		assert_eq!(
			gas_id_for_path("/datum/gas/volatile_fuel"),
			Some(GAS_VOLATILE_FUEL)
		);
		assert_eq!(gas_path(GAS_PLASMA), Some("/datum/gas/plasma"));
		assert_eq!(gas_path(GAS_COUNT), None);
		for (idx, path) in GAS_PATHS.iter().enumerate() {
			assert_eq!(gas_id_for_path(path), Some(idx));
		}
	}
}
