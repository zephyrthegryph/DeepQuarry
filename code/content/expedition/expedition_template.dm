// Blank vacuum volume a fresh expedition station is built inside. Keeping the
// template as space prevents unused map bounds from appearing as an asteroid
// around the generated hull.
/datum/map_template/expedition_site
	name = "Expedition Site"
	mappath = "maps/expedition/expedition_blank.dmm"


// A real, pre-piped thermoelectric engine bay (TEG + circulators + burn chamber
// + phoron/nitrogen canisters) reused from the Southern Cross engine submaps.
// Stamped onto a site for the "commission the engine" objective: the crew must
// fuel the burn chamber, start the loop, and bring the generator online.
/datum/map_template/expedition_engine
	name = "Derelict Engine Bay"
	mappath = "maps/submaps/engine_submaps/southern_cross/engine_sme.dmm"
	annihilate = TRUE
