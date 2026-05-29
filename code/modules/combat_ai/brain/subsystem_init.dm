// Minimal init subsystem for the combat AI framework.
// Only purpose: build the faction registry once before any mob's brain looks
// up its faction data.

SUBSYSTEM_DEF(dq_combat_ai)
	name = "DQ Combat AI"
	flags = SS_NO_FIRE        // init only, no recurring fire

/datum/controller/subsystem/dq_combat_ai/Initialize()
	dq_build_faction_registry()
	return SS_INIT_SUCCESS
