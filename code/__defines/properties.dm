// Property registry (doc/rewrite/rules.md §1). Code: code/datums/properties/.

// Property kinds.
#define PROP_KIND_MEASURE 1
#define PROP_KIND_TAG 2

// Aggregators: how several values of one property combine into one. The
// values shared with the body factor rules (BF_RULE_* in body_factors.dm) are
// the same numbers on purpose, and dq_property_aggregators checks it:
// PRODUCT = BF_RULE_MULT, SUM = BF_RULE_ADD, MAX = BF_RULE_MAX,
// MIN = BF_RULE_MIN, OR = BF_RULE_FLAGS.
#define PROP_AGG_NONE 0
#define PROP_AGG_PRODUCT 1
#define PROP_AGG_SUM 2
#define PROP_AGG_MAX 3
#define PROP_AGG_MIN 4
#define PROP_AGG_OR 5

// Provider sources. TYPE, MATERIAL and DOMAIN are base providers: exactly one
// answers for a given type. COMPONENT and EQUIPMENT are contributors: they fold
// into the base value through the property's aggregator.
#define PROP_SOURCE_TYPE "type"
#define PROP_SOURCE_MATERIAL "material"
#define PROP_SOURCE_DOMAIN "domain"
#define PROP_SOURCE_COMPONENT "component"
#define PROP_SOURCE_EQUIPMENT "equipment"

// SI units. The first six mirror the newtypes in verdigris/core/src/units.rs
// (Kelvin, Joules, Pascals, Moles, Watts, HeatCapacity) and use their symbols.
#define PROP_UNIT_KELVIN "K"
#define PROP_UNIT_JOULES "J"
#define PROP_UNIT_PASCALS "Pa"
#define PROP_UNIT_MOLES "mol"
#define PROP_UNIT_WATTS "W"
#define PROP_UNIT_HEAT_CAPACITY "J/K"
// Not yet on the Rust side.
#define PROP_UNIT_KILOGRAMS "kg"
#define PROP_UNIT_CUBIC_METRES "m3"
/// Dimensionless ordinal: ITEMSIZE_* classes.
#define PROP_UNIT_SIZE_CLASS "size"
/// Dimensionless ratio or count.
#define PROP_UNIT_RATIO "1"

// Property ids.
#define PROP_SIZE_CLASS "size_class"
#define PROP_MASS "mass"
#define PROP_MELTING_POINT "melting_point"
#define PROP_IGNITION_POINT "ignition_point"
#define PROP_MAX_HEAT_PROTECTION "max_heat_protection"
#define PROP_HEAT_CAPACITY "heat_capacity"
#define PROP_TEMPERATURE "temperature"
#define PROP_INTEGRITY_RATIO "integrity_ratio"
#define PROP_INTEGRITY_FAILURE "integrity_failure"
// Tag ids.
#define TAG_SHARP "sharp"
#define TAG_FLAMMABLE "flammable"
#define TAG_CONDUCTIVE "conductive"
#define TAG_PAPERWORK "paperwork"

/// Mass of one unit of an item's `matter` list. Matter amounts are treated as
/// grams of that material (a sheet is SHEET_MATERIAL_AMOUNT = 2000, so 2 kg).
#define MATTER_UNIT_KG 0.001

/// Bits per tag word. BYOND bit operations are exact to 24 bits.
#define PROP_TAG_WORD_BITS 24

/// Value of property `id` for an instance: base provider, saved state, then contributors.
#define PROPERTY(thing, id) dq_property(thing, id)
/// Whether an instance has tag `tag`.
#define HAS_TAG(thing, tag) dq_has_tag(thing, tag)
