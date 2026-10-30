#if 0
#define SRC_ALPHA 800
# define STAT_ALPHA 99
#define CAP_A 301
#define STAGE_BUILD_EARLY 40
STAT(/datum/x, alpha, ANY)
STAT(/datum/x, alpha, SUM, units = "Pa")
SOURCE_DEF(alpha)
SOURCE_DEF(ßeta)
STAGE_DEF(build, early)
STATE_GRAPH(GRAPH_A)
CAPABILITY_TYPE(other, CAP_B, /datum/capability/other)
CAPABILITY_DEF(short)
cap_keys(CAP_B, ON = 1, OFF = 0)
cap_keys(CAP_UNKNOWN, SOME = 3)
cap_keys(CAP_B, K0 = 0, K1 = 0, K2 = 0, K3 = 0, K4 = 0, K5 = 0, K6 = 0, K7 = 0, K8 = 0, K9 = 0, K10 = 0, K11 = 0, K12 = 0, K13 = 0, K14 = 0, K15 = 0, K16 = 0, K17 = 0, K18 = 0, K19 = 0, K20 = 0, K21 = 0, K22 = 0, K23 = 0, K24 = 0)
#endif
