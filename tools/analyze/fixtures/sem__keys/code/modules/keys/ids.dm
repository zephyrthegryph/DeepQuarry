// Declarations the key resolver indexes (stat, source, stage, capability, op).
SOURCE_DEF(status)
SOURCE_DEF(ai_control)
SOURCE_DEF(status)
STAT(/atom, density, TOP)
STAT(/obj/machinery, operable, ALL)
STAGE_DEF(door, frame)
STAGE_DEF(door, wired)
#define STAT_CLOCK_RATE 11

CAPABILITY_DEF(cover, CAP_COVER, key = name, open = FALSE,
	op("open", needs(PROC_REF(can_open))),
	op("close"))
cap_keys(CAP_COVER, OPEN = MSG(cover/closed), REMOVED = MSG(cover/removed))

CAPABILITY_DEF(cover, CAP_COVER_AGAIN)

CAPABILITY_DEF(construction, CAP_CONSTRUCTION,
	op("build"),
	op("undo"))
