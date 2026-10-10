#define DEFAULT_SEED PLANT_GLOWSHROOM
#define VINE_GROWTH_STAGES 5

/proc/spacevine_infestation(potency_min=70, potency_max=100, maturation_min=5, maturation_max=15)
	after(null, 0, GLOBAL_PROC_REF(spacevine_infestation_start), with = list(potency_min, potency_max, maturation_min, maturation_max)) //to stop the secrets panel hanging (the global owner: a round event)

/obj/effect/dead_plant
	anchored = TRUE
	opacity = 0
	density = FALSE
	color = DEAD_PLANT_COLOUR

CAPABILITIES(/obj/effect/dead_plant)
	op("clear_dead_plant", hand(), label("Interaction clear dead plant"), then(PROC_REF(interaction_clear_dead_plant)))
	op("clear_dead_plant_item", item(/obj/item), label("Interaction clear dead plant item"), then(PROC_REF(interaction_clear_dead_plant_item)))

/// Old attack_hand: a touch clears the dead plant away.
/obj/effect/dead_plant/proc/interaction_clear_dead_plant(datum/act/op/A)
	var/mob/user = A.actor
	consume(src, user)
	return TRUE

/// Old attackby: any item clears it and lets the neighbouring vines regrow (the item's normal handling still follows).
/obj/effect/dead_plant/proc/interaction_clear_dead_plant_item(datum/act/op/A)
	var/mob/user = A.actor
	for(var/obj/effect/plant/neighbor in range(1, src))
		neighbor.update_neighbors()
	consume(src, user)
	return OP_PASS

/// Growing (plant_step every() on `growing`) while in REGISTRY_GROWING_PLANTS: add_plant() / remove_plant().
REGISTRY_MEMBERSHIP(/obj/effect/plant, REGISTRY_GROWING_PLANTS)

/obj/effect/plant
	name = "plant"
	anchored = TRUE
	can_buckle = TRUE
	opacity = 0
	density = FALSE
	icon = 'icons/obj/hydroponics_growing.dmi'
	icon_state = "bush4-1"
	pass_flags = PASSTABLE
	mouse_opacity = 2

	var/health = 10
	var/max_health = 100
	var/growth_threshold = 0
	var/growth_type = 0
	var/max_growth = 0
	var/list/neighbors
	var/tmp/obj/effect/plant/parent
	var/tmp/datum/seed/seed_static
	var/sampled = 0
	var/floor = 0
	/// How far a wall plant sits into its wall, rolled once so a redraw keeps it.
	var/wall_shift = 12
	var/spread_chance = 40
	var/spread_distance = 3
	var/evolve_chance = 2
	EXPIRY_DECLARE(mature_time) //minimum maturation time
	COOLDOWN_DECLARE(neighbor_refresh_cooldown)
	var/obj/machinery/portable_atmospherics/hydroponics/soil/invisible/plant
	/// Is it in the growing registry? The growth every() below runs while it is.
	var/growing = FALSE

TRACKED(/obj/effect/plant, growing)

CAPABILITIES(/obj/effect/plant)
	every(7.5 SECONDS, then(PROC_REF(plant_step)), when = nameof(growing))
	owns_one(nameof(seed_static), on_destroy = ON_DESTROY_PRIVATE_COPY)
	owns_one(nameof(plant), /obj/machinery/portable_atmospherics/hydroponics/soil/invisible)
	op("hit_plant", item(/obj/item), then(PROC_REF(interaction_hit_plant)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("touch_plant", hand(), then(PROC_REF(interaction_touch_plant)))
	rolls(nameof(wall_shift), range_of(12, 14))
	param(nameof(seed_at_make), pos = 1)
	param(nameof(parent), pos = 2)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(plant_blast_die_off))))

// neighbouring plants resume spreading.
/obj/effect/plant/on_destroy(force)
	if(seed() && seed().get_trait(TRAIT_SPREAD)==2)
		unsense_proximity(callback = TYPE_PROC_REF(/atom, HasProximity), center = get_turf(src))
	SSplants.remove_plant(src)
	for(var/obj/effect/plant/neighbor in range(1,src))
		SSplants.add_plant(neighbor)
	..()

/obj/effect/plant/single
	spread_chance = 0

/// The seed a vine grows from (its constructor param), or null for the default seed.
/obj/effect/plant/var/datum/seed/seed_at_make

// ALLOW(init/INSTANCE_STATE): a vine takes its seed's traits, growth and spread
/obj/effect/plant/Initialize(mapload)
	. = ..()
	if(isopenturf(loc))
		return INITIALIZE_HINT_QDEL

	if(!parent)
		rel_set(src, nameof(parent), src)

	if(!SSplants)
		to_chat(world, span_danger("Plant controller does not exist and [src] requires it. Aborting."))
		return INITIALIZE_HINT_QDEL

	var/datum/seed/newseed = seed_at_make
	if(!istype(newseed))
		newseed = SSplants.seeds[DEFAULT_SEED]
	proto_set(src, nameof(seed_static), seed_shareable(newseed)) // vines share their seed
	if(!seed())
		return INITIALIZE_HINT_QDEL

	name = seed().display_name
	max_health = round(seed().get_trait(TRAIT_ENDURANCE)/2)
	if(seed().get_trait(TRAIT_SPREAD)==2)
		sense_proximity(callback = TYPE_PROC_REF(/atom,HasProximity)) // Grabby
		set_max_growth(VINE_GROWTH_STAGES)
		set_growth_threshold(max_health/VINE_GROWTH_STAGES)
		icon = 'icons/obj/hydroponics_vines.dmi'
		set_growth_type(2) // Vines by default.
		if(seed().get_trait(TRAIT_CARNIVOROUS) >= 2)
			set_growth_type(1) // WOOOORMS.
		else if(!(seed().seed_noun in list("seeds","pits")))
			if(seed().seed_noun in list("nodes", "cuttings"))
				set_growth_type(3) // Biomass
			else
				set_growth_type(4) // Mold
	else
		set_max_growth(seed().growth_stages)
		set_growth_threshold(max_health/seed().growth_stages)

	if(max_growth > 2 && prob(50))
		set_max_growth(max_growth - 1) //Ensure some variation in final sprite, makes the carpet of crap look less wonky.

	EXPIRY_SET(src, mature_time, seed().get_trait(TRAIT_MATURATION) + 15, CLOCK_WORLD) //prevent vines from maturing until at least a few seconds after they've been created.
	spread_chance = seed().get_trait(TRAIT_POTENCY)
	spread_distance = ((growth_type>0) ? round(spread_chance*0.6) : round(spread_chance*0.3))

// Plants will sometimes be spawned in the turf adjacent to the one they need to end up in, for the sake of correct dir/etc being set.
/obj/effect/plant/proc/finish_spreading()
	set_dir(calc_dir())
	SSplants.add_plant(src)
	//Some plants eat through plating.
	if(islist(seed().chems) && !isnull(seed().chems[REAGENT_ID_PACID]))
		var/turf/T = get_turf(src)
		T.ex_act(prob(80) ? 3 : 2)

TRACKED(/obj/effect/plant, health)
TRACKED(/obj/effect/plant, growth_threshold)
TRACKED(/obj/effect/plant, growth_type)
TRACKED(/obj/effect/plant, max_growth)
TRACKED(/obj/effect/plant, floor)
TRACKED(/obj/effect/plant, wall_shift)

/// The most stages the plant reaches: its own, held back at the fringe of its spread.
/obj/effect/plant/proc/plant_growth_cap()
	var/growth_cap = max_growth
	if(spread_distance > 5)
		var/at_fringe = get_dist(src, parent())
		if(at_fringe >= (spread_distance-3))
			growth_cap--
		if(at_fringe >= (spread_distance-2))
			growth_cap--
	return max(1, growth_cap)

/// The plant: its stage of growth, flush against the wall it grows from when it is not on the floor, tinted and lit by its seed.
/obj/effect/plant/draw(datum/look/look)
	..()
	var/growth_cap = plant_growth_cap()
	var/growth = growth_threshold ? min(growth_cap, round(health/growth_threshold)) : growth_cap
	if(growth_type > 0)
		switch(growth_type)
			if(1)
				look.state("worms")
			if(2)
				look.state("vines-[growth]")
			if(3)
				look.state("mass-[growth]")
			if(4)
				look.state("mold-[growth]")
	else
		look.state("[seed().get_trait(TRAIT_PLANT_ICON)]-[growth]")

	look.effect(PROC_REF(plant_settle), growth > 2 && growth == growth_cap)

	if(growth_type == 0 && !floor)
		var/matrix/M = matrix()
		// should make the plant flush against the wall it's meant to be growing from.
		M.Translate(0, -wall_shift)
		switch(dir)
			if(WEST)
				M.Turn(90)
			if(NORTH)
				M.Turn(180)
			if(EAST)
				M.Turn(270)
		look.set_transform(M)
	var/icon_colour = seed().get_trait(TRAIT_PLANT_COLOUR)
	if(icon_colour)
		look.set_color(icon_colour)
	// Apply colour and light from seed datum.
	if(seed().get_trait(TRAIT_BIOLUM))
		var/clr
		if(seed().get_trait(TRAIT_BIOLUM_COLOUR))
			clr = seed().get_trait(TRAIT_BIOLUM_COLOUR)
		// Tons of super bright super long range lights everywhere is annoying and laggy, so let's limit it a bit.
		var/blight = 1+round(seed().get_trait(TRAIT_POTENCY)/20)
		if(blight >= 5)
			blight = 5
		look.light(blight, 0.5, clr)
	else
		look.light_off()

/// A fully grown plant stands tall (and, of woody seeds, blocks the way); a younger one lies flat and open.
/obj/effect/plant/proc/plant_settle(full_grown)
	if(full_grown)
		plane = ABOVE_PLANE
		set_opacity(1)
		if(!isnull(seed().chems[REAGENT_ID_WOODPULP]))
			set_density(TRUE)
	else
		reset_plane_and_layer()
		set_density(FALSE)

/obj/effect/plant/proc/calc_dir()
	var/turf/T = get_turf(src)
	if(!istype(T)) return

	var/direction = 16

	for(var/wallDir in GLOB.cardinal)
		var/turf/newTurf = get_step(T,wallDir)
		if(newTurf.density)
			direction |= wallDir

	for(var/obj/effect/plant/shroom in turf_contents_of_type(T, /obj/effect/plant))
		if(shroom == src)
			continue
		if(shroom.floor) //special
			direction &= ~16
		else
			direction &= ~shroom.dir

	var/list/dirList = list()

	for(var/i=1,i<=16,i <<= 1)
		if(direction & i)
			dirList += i

	if(dirList.len)
		var/newDir = pick(dirList)
		if(newDir == 16)
			set_floor(1)
			newDir = 1
		return newDir

	set_floor(1)
	return 1

/// Old attackby: a scalpel takes a sample, anything else hacks at the plant. The item's normal handling still follows.
/obj/effect/plant/proc/interaction_hit_plant(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	user.setClickCooldown(user.get_attack_speed(held))
	SSplants.add_plant(src)

	if(istype(held, /obj/item/surgical/scalpel))
		take_plant_sample(user)
	else if(held.force)
		set_health(health - held.force)
	return OP_PASS

/// Old attack_hand: pull free whoever the plant has entangled.
/obj/effect/plant/proc/interaction_touch_plant(datum/act/op/A)
	var/mob/user = A.actor
	manual_unbuckle(user)
	return TRUE

/obj/effect/plant/proc/take_plant_sample(mob/user)
	if(sampled)
		to_chat(user, span_warning("\The [src] has already been sampled recently."))
		return FALSE
	if(!is_mature())
		to_chat(user, span_warning("\The [src] is not mature enough to yield a sample yet."))
		return FALSE
	if(!seed())
		to_chat(user, span_warning("There is nothing to take a sample from."))
		return FALSE
	if(prob(70))
		sampled = TRUE
	seed().harvest(user, 0, TRUE)
	set_health(health - rand(3, 5) * 5)
	sampled = TRUE
	check_health()
	return TRUE

/// Wirecutters take a sample of the plant.
/obj/effect/plant/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	user.setClickCooldown(user.get_attack_speed(A.held))
	SSplants.add_plant(src)
	take_plant_sample(user)
	return OP_OK

//handles being overrun by vines - note that attacker_parent may be null in some cases
/obj/effect/plant/proc/vine_overrun(datum/seed/attacker_seed, obj/effect/plant/attacker_parent)
	var/aggression = 0
	aggression += (attacker_seed.get_trait(TRAIT_CARNIVOROUS) - seed().get_trait(TRAIT_CARNIVOROUS))
	aggression += (attacker_seed.get_trait(TRAIT_SPREAD) - seed().get_trait(TRAIT_SPREAD))

	var/resiliance
	if(is_mature())
		resiliance = 0
		switch(seed().get_trait(TRAIT_ENDURANCE))
			if(30 to 70)
				resiliance = 1
			if(70 to 95)
				resiliance = 2
			if(95 to INFINITY)
				resiliance = 3
	else
		resiliance = -2
		if(seed().get_trait(TRAIT_ENDURANCE) >= 50)
			resiliance = -1
	aggression -= resiliance

	if(aggression > 0)
		set_health(health - aggression*5)
		check_health()


/// A blast kills the plant by its own severity odds (instead of the blast packet).
/obj/effect/plant/proc/plant_blast_die_off(datum/act/hit/explosion/A)
	var/datum/damage_packet/packet = A.packet
	switch(packet.severity)
		if(1.0)
			die_off()
		if(2.0)
			if (prob(50))
				die_off()
		if(3.0)
			if (prob(5))
				die_off()
	return OP_OK

/obj/effect/plant/proc/check_health()
	if(health <= 0)
		die_off()

/obj/effect/plant/proc/is_mature()
	return (health >= (max_health/3) && ELAPSED_SINCE(src, mature_time, CLOCK_WORLD) > 0)

#undef DEFAULT_SEED
#undef VINE_GROWTH_STAGES

/proc/spacevine_infestation_start(potency_min, potency_max, maturation_min, maturation_max)
	var/list/turf/simulated/floor/turfs = list() // list of all the empty floor turfs in the hallway areas // start: keeping old method over upstream's landmark method
	for(var/areapath in typesof(/area/hallway))
		var/area/A = locate(areapath)
		for(var/turf/simulated/floor/F in contents_of(A))
			if(!F.check_density())
				turfs += F

	if(turfs.len) //Pick a turf to spawn at if we can
		var/turf/simulated/floor/T = pick(turfs) // end
		var/datum/seed/seed = SSplants.create_random_seed(1)
		seed.set_trait(TRAIT_SPREAD,2)             // So it will function properly as vines.
		seed.set_trait(TRAIT_POTENCY,rand(potency_min, potency_max)) // 70-100 potency will help guarantee a wide spread and powerful effects.
		seed.set_trait(TRAIT_MATURATION,rand(maturation_min, maturation_max))
		seed.display_name = "strange plants" //more thematic for the vine infestation event

		//make vine zero start off fully matured
		var/obj/effect/plant/vine = new(T,seed)
		vine.set_health(vine.max_health)
		vine.mature_time = 0
		vine.plant_step(null)

		message_admins(span_notice("Event: Spacevines spawned at [T.loc] ([T.x],[T.y],[T.z])"))
		return
	message_admins(span_notice("Event: Spacevines failed to find a viable turf."))


/// the parent this refers to (a relation view: null once it is deleted).
/obj/effect/plant/proc/parent() as /obj/effect/plant
	return parent

/// The seed (PROTO): a registered line, or this holder's own private copy.
/obj/effect/plant/proc/seed() as /datum/seed
	return seed_static
