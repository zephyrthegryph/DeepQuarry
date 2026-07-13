// Source-substance archetypes.
//
// An archetype fixes a source's VISIBLE surface behavior (family + trigger) and
// the TENDENCY ranges its hidden profile is rolled from — but the exact profile
// rerolls every round (substance_round.dm). Phase 1 uses xenoarchaeology finds as
// the only source, so these read the field-material way: high energy, often high
// volatility, exotic resonance, variable purity. Bio/botany sources (the clean,
// high-affinity and high-purity ends) arrive in a later phase.

/datum/substance_archetype
	/// Registry key + default substance name.
	var/id = "archetype"
	var/name = "exotic sample"
	/// Source category — "field" (xenoarch), "bio" (cultivated), "botany" (bred).
	/// Complementary by design: field = powerful but volatile/impure; bio = high
	/// affinity (binders/aimers); botany = high purity in bulk (clean stabilisers).
	var/category = "field"
	/// Visible surface behavior.
	var/family = SUBFAM_DISCHARGE
	var/trigger = SUB_TRIG_IMPACT
	/// Per-axis roll ranges (the hidden profile is drawn from these each round).
	var/energy_lo = 40
	var/energy_hi = 90
	var/volatility_lo = 40
	var/volatility_hi = 90
	var/affinity_lo = 20
	var/affinity_hi = 70
	var/purity_lo = 20
	var/purity_hi = 80

// Registry: id -> /datum/substance_archetype. Built once, lazily.
/proc/substance_archetype(id)
	var/list/registry = substance_archetype_registry()
	return registry[id]

/proc/substance_archetype_registry()
	var/static/list/registry
	if(registry)
		return registry
	registry = list()
	for(var/atype in subtypesof(/datum/substance_archetype))
		var/datum/substance_archetype/A = new atype()
		if(A.id)
			registry[A.id] = A
	return registry

// All archetype ids, for tooling/debug.
/proc/substance_archetype_ids()
	return substance_archetype_registry().Copy()

// Archetype ids in a given source category ("field" / "bio" / "botany").
/proc/substance_archetype_ids_by_category(cat)
	var/list/out = list()
	var/list/reg = substance_archetype_registry()
	for(var/id in reg)
		var/datum/substance_archetype/A = reg[id]
		if(A.category == cat)
			out += id
	return out

// ---- The Phase 1 source roster (xenoarchaeology finds) ---------------------
// Each fixes a family + a thematically-fitting trigger. The wide, overlapping
// roll ranges are what make profiles partly-predictable but never solved.

/datum/substance_archetype/voltaic_shard
	id = "voltaic_shard"
	name = "voltaic shard"
	family = SUBFAM_DISCHARGE
	trigger = SUB_TRIG_IMPACT
	energy_lo = 55; energy_hi = 95
	volatility_lo = 45; volatility_hi = 85

/datum/substance_archetype/thermic_resin
	id = "thermic_resin"
	name = "thermic resin"
	family = SUBFAM_THERMAL
	trigger = SUB_TRIG_HEAT
	energy_lo = 40; energy_hi = 80
	volatility_lo = 35; volatility_hi = 75
	affinity_lo = 30; affinity_hi = 75

/datum/substance_archetype/kinetic_ore
	id = "kinetic_ore"
	name = "kinetic ore"
	family = SUBFAM_FORCE
	trigger = SUB_TRIG_IMPACT
	energy_lo = 50; energy_hi = 90
	volatility_lo = 30; volatility_hi = 70

/datum/substance_archetype/ward_crystal
	id = "ward_crystal"
	name = "ward crystal"
	family = SUBFAM_FIELD
	trigger = SUB_TRIG_PRESSURE
	energy_lo = 30; energy_hi = 70
	volatility_lo = 20; volatility_hi = 55
	affinity_lo = 45; affinity_hi = 90 // fields bond well — natural stabilizers

/datum/substance_archetype/spore_clod
	id = "spore_clod"
	name = "spore clod"
	family = SUBFAM_SPORE
	trigger = SUB_TRIG_CONTACT
	energy_lo = 25; energy_hi = 65
	volatility_lo = 30; volatility_hi = 70
	affinity_lo = 40; affinity_hi = 85
	purity_lo = 30; purity_hi = 75

/datum/substance_archetype/etching_acid
	id = "etching_acid"
	name = "etching salt"
	family = SUBFAM_CORROSIVE
	trigger = SUB_TRIG_CONTACT
	energy_lo = 35; energy_hi = 75
	volatility_lo = 50; volatility_hi = 90
	purity_lo = 25; purity_hi = 70

/datum/substance_archetype/lumen_dust
	id = "lumen_dust"
	name = "lumen dust"
	family = SUBFAM_RADIANT
	trigger = SUB_TRIG_ENERGY
	energy_lo = 45; energy_hi = 90
	volatility_lo = 40; volatility_hi = 80

/datum/substance_archetype/rift_glass
	id = "rift_glass"
	name = "rift glass"
	family = SUBFAM_VOID
	trigger = SUB_TRIG_PRESSURE
	energy_lo = 55; energy_hi = 100
	volatility_lo = 55; volatility_hi = 95
	affinity_lo = 15; affinity_hi = 55 // void barely bonds — fragile, low yield
	purity_lo = 15; purity_hi = 60

// ---- Bio sources (xenobiology — cultivated; high AFFINITY: binders/aimers) ----

/datum/substance_archetype/vital_culture
	id = "vital_culture"
	name = "vital culture"
	category = "bio"
	family = SUBFAM_SPORE
	trigger = SUB_TRIG_CONTACT
	energy_lo = 25; energy_hi = 60
	volatility_lo = 25; volatility_hi = 55
	affinity_lo = 60; affinity_hi = 95
	purity_lo = 35; purity_hi = 70

/datum/substance_archetype/binding_plasm
	id = "binding_plasm"
	name = "binding plasm"
	category = "bio"
	family = SUBFAM_FIELD
	trigger = SUB_TRIG_CONTACT
	energy_lo = 20; energy_hi = 55
	volatility_lo = 20; volatility_hi = 50
	affinity_lo = 65; affinity_hi = 95

/datum/substance_archetype/neural_jelly
	id = "neural_jelly"
	name = "neural jelly"
	category = "bio"
	family = SUBFAM_DISCHARGE
	trigger = SUB_TRIG_ENERGY
	energy_lo = 30; energy_hi = 65
	volatility_lo = 30; volatility_hi = 60
	affinity_lo = 55; affinity_hi = 85

// ---- Botany sources (xenobotany — bred; high PURITY in bulk: clean stabilisers) ----

/datum/substance_archetype/pure_pollen
	id = "pure_pollen"
	name = "pure pollen"
	category = "botany"
	family = SUBFAM_RADIANT
	trigger = SUB_TRIG_ENERGY
	energy_lo = 25; energy_hi = 60
	volatility_lo = 20; volatility_hi = 50
	purity_lo = 65; purity_hi = 95

/datum/substance_archetype/solvent_sap
	id = "solvent_sap"
	name = "solvent sap"
	category = "botany"
	family = SUBFAM_CORROSIVE
	trigger = SUB_TRIG_CONTACT
	energy_lo = 30; energy_hi = 65
	volatility_lo = 30; volatility_hi = 60
	purity_lo = 60; purity_hi = 90

/datum/substance_archetype/ballast_fiber
	id = "ballast_fiber"
	name = "ballast fiber"
	category = "botany"
	family = SUBFAM_FIELD
	trigger = SUB_TRIG_PRESSURE
	energy_lo = 20; energy_hi = 50
	volatility_lo = 15; volatility_hi = 45
	affinity_lo = 50; affinity_hi = 80
	purity_lo = 65; purity_hi = 95
