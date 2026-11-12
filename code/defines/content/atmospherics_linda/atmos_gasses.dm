#define GAS_N2 "n2"
#define GAS_O2 "o2"
#define GAS_CO2 "co2"
#define GAS_PLASMA "plasma"
#define GAS_N2O "n2o"
#define GAS_NITRIUM "nitrium"
#define GAS_BZ "bz"
#define GAS_AIR "air"
#define GAS_WATER_VAPOR "water_vapor"
#define GAS_TRITIUM "tritium"
#define GAS_HYPER_NOBLIUM "hypernoblium"
#define GAS_PLUOXIUM "pluoxium"
#define GAS_MIASMA "miasma"
#define GAS_FREON "freon"
#define GAS_HYDROGEN "hydrogen"
#define GAS_HEALIUM "healium"
#define GAS_PROTO_NITRATE "proto_nitrate"
#define GAS_ZAUKER "zauker"
#define GAS_HELIUM "helium"
#define GAS_ANTINOBLIUM "antinoblium"
#define GAS_HALON "halon"

// Phoron is LINDA's plasma: GAS_PHORON is the same gas id. Methane and volatile fuel
// are the /datum/gas/methane and /datum/gas/volatile_fuel subtypes declared below.
// (Reagent ids are REAGENT_ID_* in code/defines/library/_reagents.dm, never GAS_*.)
#define GAS_PHORON GAS_PLASMA
#define GAS_CH4 "methane"
#define GAS_VOLATILE_FUEL "volatile_fuel"

/// Numeric Rust gas ID (GAS_ID_*) for a gas given as a GAS_ID_* number, a /datum/gas
/// path, its path text or its short id ("o2"). Gas binds take only numbers.
#define GAS_IDX(gas) (isnum(gas) ? (gas) : GLOB.gas_idx_by_key[gas])

// Layout of read_gas_mixtures() results (Rust read_mixtures): per mixture,
// GAS_READ_HEADER header floats then GAS_ID_COUNT mole counts. Offsets are
// 1-based within one record; a record starts at (index - 1) * GAS_READ_STRIDE.
#define GAS_READ_STRIDE (GAS_READ_HEADER + GAS_ID_COUNT)
#define GAS_READ_PRESSURE 1
#define GAS_READ_TEMPERATURE 2
#define GAS_READ_VOLUME 3
#define GAS_READ_TOTAL_MOLES 4
#define GAS_READ_HEAT_CAPACITY 5
/// Offset of a gas's moles (GAS_ID_* number) within a record.
#define GAS_READ_MOLES(gas_id) (GAS_READ_HEADER + (gas_id) + 1)

// Layout of read_gas_levels() results: per mixture, GAS_LEVELS_HEADER floats (generated from Rust) then the moles of each gas asked for.
#define GAS_LEVEL_PRESSURE 1
#define GAS_LEVEL_TEMPERATURE 2
#define GAS_LEVEL_MOLES 3
/// Offset of the n-th requested gas (1-based, in the order asked) within a row.
#define GAS_LEVEL_GAS(n) (GAS_LEVELS_HEADER + (n))
/// The `field` (GAS_LEVEL_*) of mixture `i` (1-based) in `rows`, a read_gas_levels() result whose rows are `stride` floats each.
#define GAS_LEVELS_AT(rows, i, stride, field) ((rows)[((i) - 1) * (stride) + (field)])

// The state of an air alarm thermostat (code/game/machinery/air_alarm.dm): what it is doing to the room's air.
#define GAS_HEATER_IDLE 0
#define GAS_HEATER_COOLING 1
#define GAS_HEATER_HEATING 2
