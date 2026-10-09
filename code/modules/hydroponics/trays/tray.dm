#define AGE_MOD_MAX 10 // Define for age_mod sanity check as a define to allow for easy tweaking.

/obj/machinery/portable_atmospherics/hydroponics
	name = "hydroponics tray"
	desc = "A tray usually full of fluid for growing plants."
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "hydrotray3"
	density = TRUE
	anchored = TRUE
	unacidable = TRUE
	flags = OPENCONTAINER
	volume = 100

	var/mechanical = 1         // Set to 0 to stop it from drawing the alert lights.
	var/base_name = "tray"

	// Plant maintenance vars.
	var/waterlevel = 100       // Water (max 100)
	var/nutrilevel = 10        // Nutrient (max 10)
	var/pestlevel = 0          // Pests (max 10)
	var/weedlevel = 0          // Weeds (max 10)

	// Tray state vars.
	var/dead = 0               // Is it dead?
	var/harvest = 0            // Is it ready to harvest?
	var/age = 0                // Current plant age
	var/sampled = 0            // Have we taken a sample?

	// Harvest/mutation mods.
	var/yield_mod = 0          // Modifier to yield
	var/mutation_mod = 0       // Modifier to mutation chance
	var/toxins = 0             // Toxicity in the tray?
	var/mutation_level = 0     // When it hits 100, the plant mutates.
	var/tray_light = 1         // Supplied lighting.
	var/age_mod = 0            // Variable for chems which speed up plant growth. On average, every 3 age mod reduces growing time by 2.5 minutes.

	// Mechanical concerns.
	var/health = 0             // Plant health.
	var/lastproduce = 0        // Last time tray was harvested
	EXPIRY_DECLARE(lastcycle) // Cycle timing/tracking var.
	var/cycledelay = 150       // Delay per cycle.
	var/closed_system          // If set, the tray will attempt to take atmos from a pipe.
	var/force_update           // Set this to bypass the cycle time check.
	var/obj/temp_chem_holder   // Something to hold reagents during process_reagents()
	var/labelled

	// Seed details/line data.
	var/datum/seed/seed = null // The currently planted seed

	var/image/ov_lowhealth
	var/image/ov_lowwater
	var/image/ov_lownutri
	var/image/ov_harvest
	var/image/ov_frozen
	var/image/ov_alert3

	// Reagent information for process(), consider moving this to a controller along
	// with cycle information under 'mechanical concerns' at some point.
	var/static/list/toxic_reagents = list(
		REAGENT_ID_ANTITOXIN =     -2,
		REAGENT_ID_TOXIN =           2,
		REAGENT_ID_FLUORINE =        2.5,
		REAGENT_ID_CHLORINE =        1.5,
		REAGENT_ID_SACID =           1.5,
		REAGENT_ID_PACID =           3,
		REAGENT_ID_PLANTBGONE =      3,
		REAGENT_ID_CRYOXADONE =     -3,
		REAGENT_ID_RADIUM =          2
		)
	var/static/list/nutrient_reagents = list(
		REAGENT_ID_MILK =            0.1,
		REAGENT_ID_BEER =            0.25,
		REAGENT_ID_PHOSPHORUS =      0.1,
		REAGENT_ID_SUGAR =           0.1,
		REAGENT_ID_SODAWATER =       0.1,
		REAGENT_ID_AMMONIA =         1,
		REAGENT_ID_DIETHYLAMINE =    2,
		REAGENT_ID_NUTRIMENT =       1,
		REAGENT_ID_ADMINORDRAZINE =  1,
		REAGENT_ID_EZNUTRIENT =      1,
		REAGENT_ID_ROBUSTHARVEST =   1,
		REAGENT_ID_LEFT4ZED =        1
		)
	var/static/list/weedkiller_reagents = list(
		REAGENT_ID_FLUORINE =       -4,
		REAGENT_ID_CHLORINE =       -3,
		REAGENT_ID_PHOSPHORUS =     -2,
		REAGENT_ID_SUGAR =           2,
		REAGENT_ID_SACID =          -2,
		REAGENT_ID_PACID =          -4,
		REAGENT_ID_PLANTBGONE =     -8,
		REAGENT_ID_ADMINORDRAZINE = -5
		)
	var/static/list/pestkiller_reagents = list(
		REAGENT_ID_SUGAR =           2,
		REAGENT_ID_DIETHYLAMINE =   -2,
		REAGENT_ID_ADMINORDRAZINE = -5
		)
	var/static/list/water_reagents = list(
		REAGENT_ID_ADMINORDRAZINE =  1,
		REAGENT_ID_MILK =            0.9,
		REAGENT_ID_BEER =            0.7,
		REAGENT_ID_FLUORINE =       -0.5,
		REAGENT_ID_CHLORINE =       -0.5,
		REAGENT_ID_PHOSPHORUS =     -0.5,
		REAGENT_ID_WATER =           1,
		REAGENT_ID_SODAWATER =       1,
		)

	// Beneficial reagents also have values for modifying health, yield_mod and mut_mod (in that order).
	var/static/list/beneficial_reagents = list(
		REAGENT_ID_BEER =           list( -0.05, 0,   0  ),
		REAGENT_ID_FLUORINE =       list( -2,    0,   0  ),
		REAGENT_ID_CHLORINE =       list( -1,    0,   0  ),
		REAGENT_ID_PHOSPHORUS =     list( -0.75, 0,   0  ),
		REAGENT_ID_SODAWATER =      list(  0.1,  0,   0  ),
		REAGENT_ID_SACID =          list( -1,    0,   0  ),
		REAGENT_ID_PACID =          list( -2,    0,   0  ),
		REAGENT_ID_PLANTBGONE =     list( -2,    0,   0.2),
		REAGENT_ID_CRYOXADONE =     list(  3,    0,   0  ),
		REAGENT_ID_AMMONIA =        list(  0.5,  0,   0  ),
		REAGENT_ID_DIETHYLAMINE =   list(  1,    0,   0  ),
		REAGENT_ID_NUTRIMENT =      list(  0.5,  0.1, 0  ),
		REAGENT_ID_RADIUM =         list( -1.5,  0,   0.2),
		REAGENT_ID_ADMINORDRAZINE = list(  1,    1,   1  ),
		REAGENT_ID_ROBUSTHARVEST =  list(  0,    0.2, 0  ),
		REAGENT_ID_LEFT4ZED =       list(  0,    0,   0.2)
		)

	// Mutagen list specifies minimum value for the mutation to take place, rather
	// than a bound as the lists above specify.
	var/static/list/mutagenic_reagents = list(
		REAGENT_ID_RADIUM =  8,
		REAGENT_ID_MUTAGEN = 15
		)

	var/static/list/age_reagents = list(
	REAGENT_ID_PITCHERNECTAR =  1
	)

MSG_DEF_SELF(hydroponics/anchor_first, "Anchor it first!")
MSG_DEF_SELF(hydroponics/no_freezer, "You see no way to use that on it.")
MSG_DEF_SELF(hydroponics/not_by_this, "You can't do that.")

// A tray grows while it is not cryogenically frozen: started work whose step runs each machine interval while there is something to grow or
// soak in, and parks on its growth timer between cycles (schedule_growth_wake()); planting, reagents and the freezer start it again.
CAPABILITIES(/obj/machinery/portable_atmospherics/hydroponics)
	reagents(200)
	owns_one(nameof(seed), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_one(nameof(temp_chem_holder), /obj)
	started_work(step = PROC_REF(work_step), starts = PROC_REF(has_seed), gate = PROC_REF(not_frozen), wakes_on = list(nameof(frozen)))
	op("use_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_attackby)))
	op("tend", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))
	op("tk_harvest", tk(), label("Harvest"), then(PROC_REF(hydroponics_tk_harvest)))
	// a ghost may become the living plant product of a ripe tray (the old attack_ghost: never fell through to the default)
	op("ghost_harvest", observer(), label("Harvest"), needs(req_bool(PROC_REF(can_ghost_harvest), because = PROC_REF(ghost_harvest_refusal))),
		asks(/datum/prompt/yes_no, fields = list("title" = "Living plant request", "question" = computed(PROC_REF(ghost_harvest_question)), "timeout" = 0), keeps = TARGET_PRESENT),
		then(PROC_REF(ghost_harvested)))
	op("close_lid", hand(), gesture(GESTURE_ALT), label("Toggle lid"), wait(0), when(req_bool(PROC_REF(can_toggle_lid))), then(PROC_REF(interaction_close_lid)))
	op("remove_label", menu(), label("Remove Label"), when(req_actor_kind(list(/mob/living/carbon/human, /mob/living/silicon/robot))), needs(req_bool(PROC_REF(actor_can_act), because = MSG(hydroponics/not_by_this))), then(PROC_REF(interaction_remove_label)))
	op("set_light", menu(), label("Set Light"), when(req_actor_kind(list(/mob/living/carbon/human, /mob/living/silicon/robot))), needs(req_bool(PROC_REF(actor_can_act), because = MSG(hydroponics/not_by_this))),
		asks(/datum/prompt/choice, fields = list("question" = "Specify a light level.", "title" = "Light Level", "choices" = list(0,1,2,3,4,5,6,7,8,9,10), "buttons" = FALSE, "timeout" = 0), step = "light"),
		then(PROC_REF(interaction_set_light)))
	op("toggle_lid", menu(), label("Toggle Tray Lid"), when(req_actor_kind(list(/mob/living/carbon/human, /mob/living/silicon/robot))), needs(req_bool(PROC_REF(actor_can_act), because = MSG(hydroponics/not_by_this))), then(PROC_REF(interaction_toggle_lid_verb)))
	op("sample", tool(TOOL_WIRECUTTER), label("Take a sample"), wait(0), then(PROC_REF(sample_cut)))
	op("bolt", tool(TOOL_WRENCH), label("Anchor"), wait(0), priority(OP_PRIORITY_PART + 1), when(req_bool(PROC_REF(boltable))), then(PROC_REF(bolted)))
	op("freezer", tool(TOOL_MULTITOOL), label("Toggle cryogenic freezing"), wait(0),
		needs(req_bool(PROC_REF(is_anchored), because = MSG(hydroponics/anchor_first)), req_bool(PROC_REF(can_freeze), because = MSG(hydroponics/no_freezer))),
		then(PROC_REF(freezer_toggled)))

/// Only a mechanical tray has a lid (the hand binding brings the reach and the actor's state).
/obj/machinery/portable_atmospherics/hydroponics/proc/can_toggle_lid(datum/act/op/A)
	return mechanical

/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_close_lid(datum/act/op/A)
	close_lid(A.actor)

/// The old verbs' check: alive, conscious and free.
/obj/machinery/portable_atmospherics/hydroponics/proc/actor_can_act(datum/act/op/A)
	return dq_actor_can_act(A.actor, src, A.held)

/// A ghost may become the living plant product of a ripe tray (the old attack_ghost). Silent unless the ghost itself may not.
/obj/machinery/portable_atmospherics/hydroponics/proc/can_ghost_harvest(datum/act/op/A)
	return isnull(ghost_harvest_refusal(A))

/// Why a ghost may not harvest this tray, or null: nothing living to harvest (silent) or the ghost trap's own candidate checks.
/obj/machinery/portable_atmospherics/hydroponics/proc/ghost_harvest_refusal(datum/act/op/A)
	READS_FROM() // the ripeness and the candidate's bans are read when the ghost clicks, never cached
	if(!(harvest && seed && seed.has_mob_product)) // ALLOW(reads): ripeness and the plant's kind are read when the ghost clicks, never cached
		return /datum/msg/req_silent
	var/datum/ghosttrap/plant/G = get_ghost_trap("living plant")
	return G?.candidate_refusal(A.actor)

/// The question the ghost is asked, naming the planted line.
/obj/machinery/portable_atmospherics/hydroponics/proc/ghost_harvest_question(datum/act/A)
	return "Are you sure you want to harvest this [seed?.display_name]?"

/// The yes: the tray is harvested and the ghost goes into the plant (the ghost trap's candidate checks are asked again with the answer).
/obj/machinery/portable_atmospherics/hydroponics/proc/ghost_harvested(datum/act/op/A)
	var/datum/prompt/answer = A.answer
	if(answer?.value)
		harvest()
		SStgui.update_uis(src)
	return OP_OK

/obj/machinery/portable_atmospherics/hydroponics/attack_generic(mob/user)

	// Why did I ever think this was a good idea. TODO: move this onto the nymph mob.
	if(istype(user,/mob/living/carbon/alien/diona))
		var/mob/living/carbon/alien/diona/nymph = user

		if(nymph.stat == DEAD || nymph.has_status(STAT_PARALYZED) || nymph.has_status(STAT_WEAKENED) || nymph.has_status(STAT_STUNNED) || nymph.restrained())
			return

		if(weedlevel > 0)
			nymph.reagents.add_reagent(REAGENT_ID_GLUCOSE, weedlevel)
			weedlevel = 0
			act_message(nymph, src, MSG_SELF(span_notice("You begin rooting through %T%, ripping out weeds and eating them noisily.")), \
				MSG_OTHERS(span_notice(span_bold("%U%") + " begins rooting through %T%, ripping out weeds and eating them noisily.")))
		else if(nymph.nutrition > 100 && nutrilevel < 10)
			nymph.adjust_nutrition(-(((10-nutrilevel)*5)))
			nutrilevel = 10
			act_message(nymph, src, MSG_SELF(span_notice("You secrete a trickle of green liquid, refilling %T%.")), \
				MSG_OTHERS(span_notice(span_bold("%U%") + " secretes a trickle of green liquid, refilling %T%.")))
		else
			act_message(nymph, src, MSG_SELF(span_notice("You roll around in %T% for a bit.")), \
				MSG_OTHERS(span_notice(span_bold("%U%") + " rolls around in %T% for a bit.")))
		return


/// Is the plant frozen? -1 is used to define trays that can't be frozen. 0 is unfrozen and 1 is frozen.
/obj/machinery/portable_atmospherics/hydroponics/var/frozen = 0
TRACKED(/obj/machinery/portable_atmospherics/hydroponics, frozen)

/// Everything but cryogenically frozen (frozen == 1) grows.
/obj/machinery/portable_atmospherics/hydroponics/proc/not_frozen()
	return frozen != 1

/// A tray with something planted starts its work when it is placed.
/obj/machinery/portable_atmospherics/hydroponics/proc/has_seed(datum/act/A)
	return !!seed

/obj/machinery/portable_atmospherics/hydroponics/Initialize(mapload)
	. = ..()
	if(!ov_lowhealth)
		setup_overlays()
	rel_set(src, nameof(temp_chem_holder), new /obj())
	temp_chem_holder.create_reagents(10) // ALLOW(decl): holder on a bare scratch /obj child, not on src
	if(mechanical)
		connect()
	update_icon()


/obj/machinery/portable_atmospherics/hydroponics/on_reagent_change()
	work_start(src)

/obj/machinery/portable_atmospherics/hydroponics/proc/schedule_growth_wake()
	if(after_pending(src, "growth_timer") || frozen == 1)
		return
	after(src, max(0.1 SECONDS, lastcycle + cycledelay - world.time), PROC_REF(wake_for_growth), key = "growth_timer")

/obj/machinery/portable_atmospherics/hydroponics/proc/wake_for_growth()
	work_start(src)

// Give the seeds time to initialize itself
/// Plants the seeds lying on its turf.
/obj/machinery/portable_atmospherics/hydroponics/port_after_init(datum/act/timer/A)
	..()
	var/obj/item/seeds/S = locate_within(loc, /obj/item/seeds)
	if(S)
		plant_seeds(S)

/obj/machinery/portable_atmospherics/hydroponics/proc/plant_seeds(obj/item/seeds/S)
	lastproduce = 0
	seed_hand_over(S, "seed_static", src, "seed") //Grab the seed datum (a packet's private copy moves over).
	dead = 0
	age = 1
	//Snowflakey, maybe move this to the seed datum
	health = (istype(S, /obj/item/seeds/cutting) ? round(seed.get_trait(TRAIT_ENDURANCE)/rand(2,5)) : seed.get_trait(TRAIT_ENDURANCE))
	EXPIRY_STAMP(src, lastcycle, CLOCK_WORLD)
	work_start(src)

	consumed(S, src)

	GLOB.seed_planted_shift_roundstat++

	check_health()
	update_icon()

/obj/machinery/portable_atmospherics/hydroponics/bullet_act(obj/item/projectile/Proj)

	//Don't act on seeds like dionaea that shouldn't change.
	if(seed && seed.get_trait(TRAIT_IMMUTABLE) > 0)
		return

	// Override for somatoray projectiles.
	// Change the mutchance var to buff or nerf somatorays, it will be multiplied by the tier of the laser.
	var/mutchance = 15
	if(istype(Proj ,/obj/item/projectile/energy/floramut))
		var/obj/item/projectile/energy/floramut/GM = Proj
		mutchance *= GM.lasermod
		if(prob(mutchance))
			if(istype(Proj, /obj/item/projectile/energy/floramut/gene))
				var/obj/item/projectile/energy/floramut/gene/G = Proj
				if(seed)
					var/datum/seed/mutated = seed.diverge_mutate_gene(G.gene(), get_turf(loc))	//get_turf just in case it's not in a turf.
					if(mutated && mutated != seed)
						proto_set(src, nameof(seed), mutated)
			else
				mutate(1)
				return
	else if(istype(Proj ,/obj/item/projectile/energy/florayield))
		var/obj/item/projectile/energy/floramut/GY = Proj
		mutchance *= GY.lasermod
		if(prob(mutchance))
			yield_mod = min(10,yield_mod+rand(1,2))
			return
	else if(istype(Proj, /obj/item/projectile/energy/floraprune))
		var/obj/item/projectile/energy/floraprune/GP = Proj
		mutchance *= GP.lasermod
		if(prob(mutchance) && seed)
			var/c = safepick(seed.chems)
			if(length(seed.chems) > 1 && c)
				var/turf/T = get_turf(loc)
				var/datum/seed/pruned = seed.diverge()
				if(!pruned)
					return
				proto_set(src, nameof(seed), pruned)
				T.visible_message(span_infoplain(span_bold("\The [seed.display_name]") + " quivers!"))
				seed.chems -= c
			return

	..()

/obj/machinery/portable_atmospherics/hydroponics/CanPass(atom/movable/mover, turf/target)
	if(istype(mover) && mover.checkpass(PASSTABLE))
		return TRUE
	return FALSE

/obj/machinery/portable_atmospherics/hydroponics/proc/check_health()
	if(seed && !dead && health <= 0)
		die()
	check_level_sanity()
	update_icon()

/obj/machinery/portable_atmospherics/hydroponics/proc/die()
	dead = 1
	mutation_level = 0
	harvest = 0
	weedlevel += 1 * HYDRO_SPEED_MULTIPLIER
	pestlevel = 0

//Process reagents being input into the tray.
/obj/machinery/portable_atmospherics/hydroponics/proc/process_reagents()

	if(!reagents) return

	if(reagents.total_volume <= 0)
		return

	reagents.trans_to_obj(temp_chem_holder, min(reagents.total_volume,rand(1,3)))

	for(var/datum/reagent/R in temp_chem_holder.reagents.reagent_list)

		var/reagent_total = temp_chem_holder.reagents.get_reagent_amount(R.id)

		if(seed && !dead)
			// Beneficial reagents have a few impacts along with health buffs.
			if(seed.beneficial_reagents && seed.beneficial_reagents[R.id])
				health += seed.beneficial_reagents[R.id][1]       * reagent_total
				yield_mod += seed.beneficial_reagents[R.id][2]    * reagent_total
				mutation_mod += seed.beneficial_reagents[R.id][3] * reagent_total

			else if(beneficial_reagents[R.id])
				health += beneficial_reagents[R.id][1]       * reagent_total
				yield_mod += beneficial_reagents[R.id][2]    * reagent_total
				mutation_mod += beneficial_reagents[R.id][3] * reagent_total

			// Mutagen is distinct from the previous types and mostly has a chance of proccing a mutation.
			if(seed.mutagenic_reagents && seed.mutagenic_reagents[R.id])
				mutation_level += reagent_total*seed.mutagenic_reagents[R.id]+mutation_mod

			else if(mutagenic_reagents[R.id])
				mutation_level += reagent_total*mutagenic_reagents[R.id]+mutation_mod

			// Toxic reagents can possibly differ between plants.
			if(seed.toxic_reagents && seed.toxic_reagents[R.id])
				toxins += seed.toxic_reagents[R.id] * reagent_total

			else if(toxic_reagents[R.id])
				toxins += toxic_reagents[R.id] * reagent_total

			if(age_reagents[R.id])
				age_mod += age_reagents[R.id]  * reagent_total

		//Handle some general level adjustments. These values are independent of plants existing.
		if(weedkiller_reagents[R.id])
			weedlevel -= weedkiller_reagents[R.id] * reagent_total
		if(pestkiller_reagents[R.id])
			pestlevel += pestkiller_reagents[R.id] * reagent_total

		// Handle nutrient refilling.
		if(nutrient_reagents[R.id])
			nutrilevel += nutrient_reagents[R.id]  * reagent_total

		// Handle water and water refilling.
		var/water_added = 0
		if(water_reagents[R.id])
			var/water_input = water_reagents[R.id] * reagent_total
			water_added += water_input
			waterlevel += water_input

		// Water dilutes toxin level.
		if(water_added > 0)
			toxins -= round(water_added/4)

	temp_chem_holder.reagents.clear_reagents()
	check_health()

//Harvests the product of a plant.
/obj/machinery/portable_atmospherics/hydroponics/proc/harvest(mob/user)

	//Harvest the product of the plant,
	if(!seed || !harvest)
		return

	if(closed_system)
		if(user)
			to_chat(user, span_filter_notice("You can't harvest from the plant while the lid is shut."))
		return

	if(user)
		seed.harvest(user,yield_mod)
	else
		seed.harvest(get_turf(src),yield_mod)
	// Reset values.
	harvest = 0
	lastproduce = age

	if(!seed.get_trait(TRAIT_HARVEST_REPEAT))
		yield_mod = 0
		proto_set(src, nameof(seed), null)
		dead = 0
		age = 0
		sampled = 0
		mutation_mod = 0
		age_mod = 0

	check_health()
	return

//Clears out a dead plant.
/obj/machinery/portable_atmospherics/hydroponics/proc/remove_dead(mob/user)
	if(!user || !dead) return

	if(closed_system)
		to_chat(user, span_filter_notice("You can't remove the dead plant while the lid is shut."))
		return

	proto_set(src, nameof(seed), null)
	dead = 0
	sampled = 0
	age = 0
	yield_mod = 0
	mutation_mod = 0
	age_mod = 0

	to_chat(user, span_filter_notice("You remove the dead plant."))
	lastproduce = 0
	check_health()
	return

// If a weed growth is sufficient, this proc is called.
/obj/machinery/portable_atmospherics/hydroponics/proc/weed_invasion()
	var/previous_plant

	//Remove the seed if something is already planted.
	if(seed)
		previous_plant = seed.display_name
		proto_set(src, nameof(seed), null)
	proto_set(src, nameof(seed), SSplants.seeds[pick(list(PLANT_REISHI,PLANT_NETTLE,PLANT_AMANITA,PLANT_MUSHROOMS,PLANT_PLUMPHELMET,PLANT_TOWERCAP,PLANT_HAREBELLS,PLANT_WEEDS))])
	if(!seed) return //Weed does not exist, someone fucked up.

	dead = 0
	age = 0
	age_mod = 0
	health = seed.get_trait(TRAIT_ENDURANCE)
	EXPIRY_STAMP(src, lastcycle, CLOCK_WORLD)
	harvest = 0
	weedlevel = 0
	pestlevel = 0
	sampled = 0
	update_icon()
	visible_message(span_notice("\The [previous_plant ? previous_plant : initial(name)] has been overtaken by [seed.display_name]."))

	return

/obj/machinery/portable_atmospherics/hydroponics/proc/mutate(severity)

	// No seed, no mutations.
	if(!seed)
		return

	// Check if we should even bother working on the current seed datum.
	if(seed.mutants && seed.mutants.len && severity > 1)
		mutate_species()
		return

	// We need to make sure we're not modifying one of the global seed datums.
	// If it's not in the global list, then no products of the line have been
	// harvested yet and it's safe to assume it's restricted to this tray.
	if(!isnull(SSplants.seeds[seed.name]))
		var/datum/seed/mutant = seed.diverge()
		if(!mutant) // TRAIT_IMMUTABLE
			return
		proto_set(src, nameof(seed), mutant)
		seed.mutate(severity,get_turf(src))

	return

/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_remove_label(datum/act/op/A)
	var/mob/user = A.actor
	if(labelled)
		to_chat(user, span_filter_notice("You remove the label."))
		labelled = null
		update_icon()
	else
		to_chat(user, span_filter_notice("There is no label to remove."))

/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_set_light(datum/act/op/A)
	var/new_light = A.step_value("light")
	if(new_light)
		tray_light = new_light
		to_chat(A.actor, span_filter_notice("You set the tray to a light level of [tray_light] lumens."))

/obj/machinery/portable_atmospherics/hydroponics/proc/check_level_sanity()
	//Make sure various values are sane.
	if(seed)
		health =     max(0,min(seed.get_trait(TRAIT_ENDURANCE),health))
	else
		health = 0
		dead = 0

	mutation_level = max(0,min(mutation_level,100))
	nutrilevel =     max(0,min(nutrilevel,10))
	waterlevel =     max(0,min(waterlevel,100))
	pestlevel =      max(0,min(pestlevel,10))
	weedlevel =      max(0,min(weedlevel,10))
	toxins =         max(0,min(toxins,10))
	age_mod =        max(0,min(age_mod,AGE_MOD_MAX)) // age_mod sanity check

/obj/machinery/portable_atmospherics/hydroponics/proc/mutate_species()

	var/previous_plant = seed.display_name
	var/newseed = seed.get_mutant_variant()
	if(newseed in SSplants.seeds)
		proto_set(src, nameof(seed), SSplants.seeds[newseed])
	else
		return

	dead = 0
	mutate(1)
	age = 0
	health = seed.get_trait(TRAIT_ENDURANCE)
	EXPIRY_STAMP(src, lastcycle, CLOCK_WORLD)
	harvest = 0
	weedlevel = 0

	update_icon()
	visible_message(span_danger("The " + span_notice("[previous_plant]") + " has suddenly mutated into " + span_notice("[seed.display_name]") + "!"))

	return

/// An item used on the tray, the old attackby kept as one effect: its guards and branches all sit at the same level, and only the
/// "syringe, inject mode, seed present" case goes on to what else the click means (OP_DECLINE).
/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_attackby(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/O = A.held

	if(O.is_open_container())
		return OP_OK

	if(istype(O, /obj/item/surgical/scalpel))
		take_plant_sample(user)
		return OP_OK

	else if(istype(O, /obj/item/reagent_containers/syringe))

		var/obj/item/reagent_containers/syringe/S = O

		if (S.mode == 1)
			if(seed)
				return OP_DECLINE
			else
				to_chat(user, span_filter_notice("There's no plant to inject."))
				return OP_OK
		else
			if(seed)
				//Leaving this in in case we want to extract from plants later.
				to_chat(user, span_filter_notice("You can't get any extract out of this plant."))
			else
				to_chat(user, span_filter_notice("There's nothing to draw something from."))
			return OP_OK

	else if (istype(O, /obj/item/seeds))

		if(!seed)

			var/obj/item/seeds/S = O
			user.remove_from_mob(O)

			if(!S.seed())
				to_chat(user, span_filter_notice("The packet seems to be empty. You throw it away."))
				consume(O, user)
				return OP_OK

			to_chat(user, span_filter_notice("You plant the [S.seed().seed_name] [S.seed().seed_noun]."))
			plant_seeds(S)

		else
			to_chat(user, span_danger("\The [src] already has seeds in it!"))

	else if (istype(O, /obj/item/material/minihoe))  // The minihoe

		if(weedlevel > 0)
			act_message(user, src, MSG_SELF(span_danger("You remove the weeds from %T%.")), MSG_OTHERS(span_danger("%U% starts uprooting the weeds.")))
			weedlevel = 0
			update_icon()
		else
			to_chat(user, span_danger("This plot is completely devoid of weeds. It doesn't need uprooting."))

	else if (istype(O, /obj/item/storage/bag/plants))

		attack_hand(user)

		var/obj/item/storage/bag/plants/S = O
		for (var/obj/item/reagent_containers/food/snacks/grown/G in locate(user.x,user.y,user.z))
			var/refusal = S.insert_refusal(G, user)
			if(refusal)
				S.refuse_insert(G, user, refusal)
				return
			S.insert_item(G, user, TRUE)

	else if ( istype(O, /obj/item/plantspray) )

		var/obj/item/plantspray/spray = O
		user.remove_from_mob(O)
		toxins += spray.toxicity
		pestlevel -= spray.pest_kill_str
		weedlevel -= spray.weed_kill_str
		to_chat(user, span_filter_notice("You spray [src] with [O]."))
		play_sfx(src, SFX_EFFECTS_SPRAY3, extrarange = -6)
		consume(O, user)
		check_health()

	else if(O.force && seed)
		user.setClickCooldown(user.get_attack_speed(O))
		act_message(user, null, others = span_danger("\The [seed.display_name] has been attacked by %U% with %I%!"), item = O)
		if(!dead)
			health -= O.force
			check_health()

	return OP_OK

/obj/machinery/portable_atmospherics/hydroponics/proc/take_plant_sample(mob/user)
	if(!seed)
		to_chat(user, span_filter_notice("There is nothing to take a sample from in \the [src]."))
		return FALSE
	if(sampled)
		to_chat(user, span_filter_notice("You have already sampled from this plant."))
		return FALSE
	if(dead)
		to_chat(user, span_filter_notice("The plant is dead."))
		return FALSE
	seed.harvest(user, yield_mod, TRUE)
	health -= rand(3, 5) * 10
	if(prob(30))
		sampled = TRUE
	check_health()
	force_update = TRUE
	work_step(null)
	return TRUE

/obj/machinery/portable_atmospherics/hydroponics/proc/sample_cut(datum/act/op/A)
	take_plant_sample(A.actor)

/// A mechanical tray with no port under it is bolted down by its own wrench, not connected.
/obj/machinery/portable_atmospherics/hydroponics/port_wrench_offered(datum/act/op/A)
	return !mechanical || locate_within(loc, /obj/machinery/atmospherics/portables_connector)

/// A mechanical tray with no port under it is bolted down by its own wrench, not connected.
/obj/machinery/portable_atmospherics/hydroponics/proc/boltable(datum/act/op/A)
	return mechanical && !locate_within(loc, /obj/machinery/atmospherics/portables_connector) // ALLOW(reads): the port under the tray is looked for when the wrench is used

/obj/machinery/portable_atmospherics/hydroponics/proc/bolted(datum/act/op/A)
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 50, TRUE)
	set_anchored(!anchored)
	to_chat(A.actor, span_filter_notice("You [anchored ? "wrench" : "unwrench"] \the [src]."))

/obj/machinery/portable_atmospherics/hydroponics/proc/is_anchored(datum/act/op/A)
	return anchored

/obj/machinery/portable_atmospherics/hydroponics/proc/can_freeze(datum/act/op/A)
	return frozen != -1

/obj/machinery/portable_atmospherics/hydroponics/proc/freezer_toggled(datum/act/op/A)
	to_chat(A.actor, span_notice("You [frozen ? "disable" : "enable"] the cryogenic freezing."))
	set_frozen(!frozen)
	update_icon()

/// Old attack_tk: clear a dead plant or harvest a ripe one at range.
/obj/machinery/portable_atmospherics/hydroponics/proc/hydroponics_tk_harvest(datum/act/op/A)
	if(dead)
		remove_dead(A.actor)
	else if(harvest)
		harvest(A.actor)

/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(istype(user,/mob/living/silicon))
		return
	if(frozen == 1)
		to_chat(user, span_warning("Disable the cryogenic freezing first!"))
	if(harvest)
		harvest(user)
	else if(dead)
		remove_dead(user)

/obj/machinery/portable_atmospherics/hydroponics/examine(mob/user)
	. = ..()

	if(seed)
		. += span_notice("[seed.display_name] are growing here.")
	else
		. += "It is empty."

	if(!Adjacent(user))
		return .

	. += "Water: [round(waterlevel,0.1)]/100"
	. += "Nutrient: [round(nutrilevel,0.1)]/10"

	if(seed)
		if(weedlevel >= 5)
			. += "It is " + span_danger("infested with weeds") + "!"
		if(pestlevel >= 5)
			. += "It is " + span_danger("infested with tiny worms") + "!"
		if(dead)
			. += "It has " + span_danger("a dead plant") + "!"
		else if(health <= (seed.get_trait(TRAIT_ENDURANCE)/ 2))
			. += "It has " + span_danger("an unhealthy plant") + "!"
	if(frozen == 1)
		. += span_notice("It is cryogenically frozen.")
	if(mechanical)
		var/turf/T = loc
		var/datum/gas_mixture/environment

		var/environment_type
		if(closed_system && (connected_port() || holding) && air_contents)
			environment = air_contents
			environment_type = "connected"
		else
			if(istype(T))
				environment = T.return_air()
			if(!environment) //We're in a crate or nullspace, bail out.
				return
			environment_type = "surrounding"

		var/light_string
		if(closed_system && mechanical)
			light_string = "that the internal lights are set to [tray_light] lumens"
		else
			var/light_available = T.get_lumcount() * 5
			light_string = "a light level of [light_available] lumens"

		. += "The tray's sensor suite is reporting [light_string] and a temperature of [environment.return_temperature()]K at [environment.return_pressure()] kPa in the [environment_type] environment."

/obj/machinery/portable_atmospherics/hydroponics/proc/interaction_toggle_lid_verb(datum/act/op/A)
	close_lid(A.actor)

/obj/machinery/portable_atmospherics/hydroponics/proc/close_lid(mob/living/user)
	closed_system = !closed_system
	to_chat(user, span_filter_notice("You [closed_system ? "close" : "open"] the tray's lid."))
	update_icon()

#undef AGE_MOD_MAX

