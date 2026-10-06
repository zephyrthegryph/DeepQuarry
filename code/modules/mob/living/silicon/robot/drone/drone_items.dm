//TODO: Matter decompiler.
/obj/item/matter_decompiler

	name = "matter decompiler"
	desc = "Eating trash, bits of glass, or other debris will replenish your stores."
	icon = 'icons/obj/device.dmi'
	icon_state = "decompiler"

	//Metal, glass, wood, plastic.
	var/datum/matter_synth/metal/metal = null
	var/datum/matter_synth/glass/glass = null
	var/datum/matter_synth/wood/wood = null
	var/datum/matter_synth/plastic/plastic = null

/obj/item/matter_decompiler/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	return NONE

/obj/item/matter_decompiler/proc/decompile_drone_interrupted(datum/task/timed/matter_decompiler_decompile_drone/task)
	var/mob/living/silicon/robot/D = task.actor
	to_chat(D, span_danger("You need to remain still while decompiling such a large object."))

/datum/task/timed/matter_decompiler_decompile_drone
	duration = 5 SECONDS
	complete_proc = /obj/item/matter_decompiler/proc/decompile_drone_done
	cancel_proc = /obj/item/matter_decompiler/proc/decompile_drone_interrupted
	var/mob/M

/obj/item/matter_decompiler/proc/decompile_drone_done(datum/task/timed/matter_decompiler_decompile_drone/task)
	var/mob/living/silicon/robot/D = task.actor
	var/mob/M = task.M
	to_chat(D, span_danger("You carefully and thoroughly decompile [M], storing as much of its resources as you can within yourself."))
	spent(M)
	new/obj/effect/decal/cleanable/blood/oil(get_turf(src))

	if(metal)
		metal.add_charge(15000)
	if(glass)
		glass.add_charge(15000)
	if(wood)
		wood.add_charge(2000)
	if(plastic)
		plastic.add_charge(1000)

/obj/item/matter_decompiler/afterattack(atom/target as mob|obj|turf|area, mob/living/user as mob|obj, proximity, params)

	if(!proximity) return //Not adjacent.

	//We only want to deal with using this on turfs. Specific items aren't important.
	var/turf/T = get_turf(target)
	if(!istype(T))
		return

	//Used to give the right message.
	var/grabbed_something = 0

	for(var/mob/M in turf_contents_of_type(T, /mob))
		if(has_trait(M, TRAIT_AMBIENT_PEST_MOB))
			src.loc.visible_message(span_danger("[src.loc] sucks [M] into its decompiler. There's a horrible crunching noise."),span_danger("It's a bit of a struggle, but you manage to suck [M] into your decompiler. It makes a series of visceral crunching noises."))
			new/obj/effect/decal/cleanable/blood/splatter(get_turf(src))
			consumed(M, src)
			if(wood)
				wood.add_charge(2000)
			if(plastic)
				plastic.add_charge(2000)
			return

		else if(istype(M,/mob/living/silicon/robot/drone) && !M.client)

			var/mob/living/silicon/robot/D = src.loc

			if(!istype(D))
				return

			to_chat(D, span_danger("You begin decompiling [M]."))

			task_start(/datum/task/timed/matter_decompiler_decompile_drone, D, src, receiver = src, M = M)
			return
		else
			continue

	for(var/obj/W in turf_contents_of_type(T, /obj))
		//Different classes of items give different commodities.
		if(istype(W,/obj/item/trash/cigbutt))
			if(plastic)
				plastic.add_charge(500)
		else if(istype(W,/obj/effect/spider/spiderling))
			if(wood)
				wood.add_charge(2000)
			if(plastic)
				plastic.add_charge(2000)
		else if(istype(W,/obj/item/light))
			var/obj/item/light/L = W
			if(L.status >= 2) //In before someone changes the inexplicably local defines. ~ Z
				if(metal)
					metal.add_charge(250)
				if(glass)
					glass.add_charge(250)
			else
				continue
		else if(istype(W,/obj/effect/decal/remains/robot))
			if(metal)
				metal.add_charge(2000)
			if(plastic)
				plastic.add_charge(2000)
			if(glass)
				glass.add_charge(1000)
		else if(istype(W,/obj/item/trash))
			if(metal)
				metal.add_charge(1000)
			if(plastic)
				plastic.add_charge(3000)
		else if(istype(W,/obj/effect/decal/cleanable/blood/gibs/robot))
			if(metal)
				metal.add_charge(2000)
			if(glass)
				glass.add_charge(2000)
		else if(istype(W,/obj/item/ammo_casing))
			if(metal)
				metal.add_charge(1000)
		else if(istype(W,/obj/item/material/shard/shrapnel))
			if(metal)
				metal.add_charge(1000)
		else if(istype(W,/obj/item/material/shard))
			if(glass)
				glass.add_charge(1000)
		else if(istype(W,/obj/item/reagent_containers/food/snacks/grown))
			if(wood)
				wood.add_charge(4000)
		else if(istype(W,/obj/item/pipe))
			pass() // This allows drones and engiborgs to clear pipe assemblies from floors.
		else
			continue

		consumed(W, src)
		grabbed_something = 1

	if(grabbed_something)
		to_chat(user, span_notice("You deploy your decompiler and clear out the contents of \the [T]."))
	else
		to_chat(user, span_danger("Nothing on \the [T] is useful to you."))
	return

// The synths are the robot module's (the owned "synths" list).
