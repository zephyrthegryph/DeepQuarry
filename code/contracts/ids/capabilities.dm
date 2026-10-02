// Capability ids (doc/rewrite/final_api.html, section 11). CAPABILITY_DEF / CAPABILITY_TYPE declare a capability and E1's
// generator emits CAP_X; until then these are the hand-assigned ids of the capabilities the contracts and the E0 fixtures
// name. master's legacy CAP_* names (CAP_COVER_OPEN, CAP_LOCK, ...) are bit names of the old cap_data words and are
// unrelated: no id here reuses one.

#define CAP_COVER 1
#define CAP_POWERED 2
#define CAP_CONSTRUCTION 3
#define CAP_DEPLOYMENT 4
#define CAP_PHASE_SHIFT 5
#define CAP_PHASED 6
#define CAP_MIRROR_PLATING 7
/// The test-only capabilities of code/tests/engine/ (declared and compiled under UNIT_TESTS only).
#define CAP_E0_DOOR 100
#define CAP_E0_MIRROR 101
#define CAP_E0_LIBRARY 102
#define CAP_E0_HOPPER 103
#define CAP_E0_CABINET 104
#define CAP_E0_PUMP 105
#define CAP_E0_LAMP 106
