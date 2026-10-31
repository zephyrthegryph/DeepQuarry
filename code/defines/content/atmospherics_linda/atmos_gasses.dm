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

// CHOMP code uses GAS_PHORON / GAS_CH4 / GAS_VOLATILE_FUEL by string ID.
// LINDA uses different names (plasma vs phoron). The CHOMP _reagents.dm defines
// load BEFORE this file, so our redefs win and CHOMP code resolves to LINDA gas
// IDs. /datum/gas/methane and /datum/gas/volatile_fuel are also added below as
// CHOMP-flavor gas subtypes so all the string IDs map to a real /datum/gas type.
#undef GAS_PHORON
#define GAS_PHORON GAS_PLASMA
#undef GAS_CH4
#define GAS_CH4 "methane"
#undef GAS_VOLATILE_FUEL
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

// The fields of a dirty-gas observation record (verdigris/ffi/src/gas/mix.rs drain_observations()), counted from the index a gas watch callback
// is handed (the record's mixture id): read them with GAS_OBSERVED(observation, index, GAS_OBS_PRESSURE), never with a bare offset.
#define GAS_OBS_MIXTURE 0
#define GAS_OBS_MASK 1
#define GAS_OBS_REVISION 2
#define GAS_OBS_PRESSURE 3
#define GAS_OBS_TEMPERATURE 4
#define GAS_OBS_VOLUME 5
#define GAS_OBS_OXYGEN 6
#define GAS_OBS_CARBON_DIOXIDE 7
#define GAS_OBS_PLASMA 8
#define GAS_OBS_METHANE 9
#define GAS_OBS_NITROUS_OXIDE 10
#define GAS_OBS_VOLATILE_FUEL 11
#define GAS_OBS_MIASMA 12
#define GAS_OBS_ZAUKER 13
#define GAS_OBS_TOTAL_MOLES 14
/// The named field `field` (GAS_OBS_*) of the observation record at `index` of `observation`.
#define GAS_OBSERVED(observation, index, field) ((observation)[(index) + (field)])

// The state of an air alarm thermostat (code/game/machinery/air_alarm.dm): what it is doing to the room's air.
#define GAS_HEATER_IDLE 0
#define GAS_HEATER_COOLING 1
#define GAS_HEATER_HEATING 2
