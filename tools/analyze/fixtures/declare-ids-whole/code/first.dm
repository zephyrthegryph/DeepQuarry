#if 0
STAT(/datum/x, alpha, SUM)
STAT(/datum/x, zeta, SUM, units = "kPa")
CAPABILITY_DEF(z, CAP_A, key = n, stacks = TRUE, value = list(1,2), prefix = "p")
CAPABILITY_TYPE(a, CAP_B, /datum/capability/a, x, bad())
SOURCE_DEF(zeta)
STAGE_DEF(build, late)
STATE_GRAPH(GRAPH_Z)
#endif
