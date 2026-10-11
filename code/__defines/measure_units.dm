// ---- Unit literals: a value followed by its PROP_UNIT_* ----
// They expand to value and unit arguments, so a bare number in a comparison is a
// constructor/boot validation error: every compared value states its unit.
#define KELVIN(v) v, PROP_UNIT_KELVIN
#define JOULES(v) v, PROP_UNIT_JOULES
#define PASCALS(v) v, PROP_UNIT_PASCALS
#define MOL(v) v, PROP_UNIT_MOLES
#define WATTS(v) v, PROP_UNIT_WATTS
#define J_PER_K(v) v, PROP_UNIT_HEAT_CAPACITY
#define KG(v) v, PROP_UNIT_KILOGRAMS
#define CUBIC_M(v) v, PROP_UNIT_CUBIC_METRES
#define SIZE_CLASS(v) v, PROP_UNIT_SIZE_CLASS
#define RATIO(v) v, PROP_UNIT_RATIO

