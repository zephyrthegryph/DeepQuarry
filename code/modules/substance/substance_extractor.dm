// The substance extractor (design doc §6 — complementary sources).
//
// Reframes the other science disciplines as substance SOURCES without touching
// their mechanics: feed it a xenobiology slime extract and it renders a bio
// substance (high-affinity — the binders and aimers); feed it a bred xenobotany
// product and it renders a botany substance in quantity (high-purity — the clean
// bulk stabilisers). Field finds (xenoarch) are powerful but volatile and impure;
// a powerful, stable, clean product naturally wants all three sources, which is
// what makes serious combinations a cross-discipline effort.

/obj/machinery/substance_extractor
	name = "substance extractor"
	desc = "Renders cultivated, bred, and excavated matter down into refined substance. Slime extracts yield high-affinity bio substance; bred produce yields clean bulk substance; a harvested xenoarchaeology artifact essence yields a field substance keyed to its anomalous effect."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "mixer0"
	density = TRUE
	anchored = TRUE
	use_power = USE_POWER_IDLE
	idle_power_usage = 20
	active_power_usage = 150

/obj/machinery/substance_extractor/attackby(obj/item/I, mob/user)
	if(stat & (BROKEN|NOPOWER))
		return ..()
	if(istype(I, /obj/item/slime_extract))
		extract_to(user, I, "bio", rand(1, 2))
		return
	if(istype(I, /obj/item/reagent_containers/food/snacks/grown))
		extract_to(user, I, "botany", rand(2, 3))
		return
	if(istype(I, /obj/item/anobattery))
		extract_artifact(user, I)
		return
	return ..()

// Render a harvested xenoarchaeology artifact essence (an anomaly battery) into a
// field substance whose effect family is derived from the captured anomaly effect.
/obj/machinery/substance_extractor/proc/extract_artifact(mob/user, obj/item/anobattery/battery)
	var/datum/artifact_effect/AE = battery.battery_effect
	if(!AE)
		to_chat(user, span_warning("\The [battery] holds no harvested anomaly to render."))
		return
	var/fam = substance_family_from_artifact_effect(AE.effect_type)
	var/datum/substance/S = new()
	S.family = fam
	S.trigger = substance_family_default_trigger(fam)
	// Field-source tendencies: potent and volatile, variable purity (per design §6).
	S.energy = rand(55, 95)
	S.volatility = rand(45, 90)
	S.affinity = rand(20, 60)
	S.purity = rand(25, 70)
	S.resonance = rand(0, SUBSTANCE_RES_MAX - 1)
	S.name = "artifact substance"
	var/famname = substance_family_name(fam)
	qdel(battery)
	substance_spawn_stack(get_turf(src), S, rand(3, 5))
	qdel(S)
	use_power(active_power_usage)
	to_chat(user, span_notice("\The [src] renders the harvested anomaly into a stack of [famname] alloy."))

// Map a xenoarchaeology anomaly effect (EFFECT_*) to a substance effect family.
/proc/substance_family_from_artifact_effect(effect_type)
	switch(effect_type)
		if(EFFECT_ELECTIC_FIELD, EFFECT_EMP, EFFECT_CELL)
			return SUBFAM_DISCHARGE
		if(EFFECT_TEMPERATURE)
			return SUBFAM_THERMAL
		if(EFFECT_GRAVIATIONAL_WAVES, EFFECT_POLTERGEIST, EFFECT_ANIMATE)
			return SUBFAM_FORCE
		if(EFFECT_FORCEFIELD)
			return SUBFAM_FIELD
		if(EFFECT_GAIA, EFFECT_RESURRECT, EFFECT_VAMPIRE, EFFECT_HEALTH)
			return SUBFAM_SPORE
		if(EFFECT_RADIATE)
			return SUBFAM_RADIANT
		if(EFFECT_TELEPORT)
			return SUBFAM_VOID
		if(EFFECT_GAS)
			return SUBFAM_CORROSIVE
	return rand(1, SUBFAM_COUNT)

// Consume the feedstock and dispense a category-appropriate substance material stack.
/obj/machinery/substance_extractor/proc/extract_to(mob/user, obj/item/feed, category, qty)
	var/list/ids = substance_archetype_ids_by_category(category)
	if(!length(ids))
		return
	var/datum/substance/S = substance_from_archetype(pick(ids), qty)
	if(!S)
		return
	var/feedname = "[feed]"
	var/famname = substance_family_name(S.family)
	qdel(feed)
	substance_spawn_stack(get_turf(src), S, qty + 2)
	qdel(S) // spawn_stack took a clone
	use_power(active_power_usage)
	to_chat(user, span_notice("\The [src] renders [feedname] into a stack of [famname] alloy."))
