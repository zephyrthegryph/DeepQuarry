/* Simple object type, calls a proc when "stepped" on by something */

/obj/effect/step_trigger
	var/affect_ghosts = 0
	var/stopper = 1 // stops throwers
	invisibility = INVISIBILITY_BADMIN // nope cant see this shit
	plane = ABOVE_PLANE
	anchored = TRUE
	icon = 'icons/mob/screen1.dmi'
	icon_state = "centermarker"

/obj/effect/step_trigger/proc/Trigger(atom/movable/A)
	return 0

/obj/effect/step_trigger/Crossed(atom/movable/H as mob|obj)
	if((istype(H, /mob/observer) && !affect_ghosts) || (!istype(H, /mob/observer) && H.is_incorporeal() && !affect_ghosts))
		return // Fixing some step trigger stuff to coincide with incorporeal check changes
	..()
	if(!H)
		return
	Trigger(H)

/* Tosses things in a certain direction */

/obj/effect/step_trigger/thrower
	var/direction = SOUTH // the direction of throw
	var/tiles = 3	// if 0: forever until atom hits a stopper
	var/immobilize = 1 // if nonzero: prevents mobs from moving while they're being flung
	var/speed = 1	// delay of movement
	var/facedir = 0 // if 1: atom faces the direction of movement
	var/nostop = 0 // if 1: will only be stopped by teleporters
	var/list/affecting = list() // ALLOW(instance_list): d: live thrower state (generic name, too many ambiguous call sites)

/obj/effect/step_trigger/thrower/Trigger(atom/A)
	if(!A || !istype(A, /atom/movable))
		return
	var/atom/movable/AM = A
	for(var/obj/effect/step_trigger/thrower/T in orange(2, src))
		if(AM in T.affecting)
			return

	if(ismob(AM))
		var/mob/M = AM
		if(immobilize)
			M.canmove = 0

	rel_add(src, nameof(affecting), AM)
	throw_next(AM, 0)

/// Moves AM one tile every `speed` until it runs out of tiles or hits a stopper.
/obj/effect/step_trigger/thrower/proc/throw_next(atom/movable/AM, curtiles)
	if(QDELETED(AM) || (tiles && curtiles >= tiles) || AM.z != src.z)
		throw_end(AM)
		return
	after(src, speed, PROC_REF(throw_step), with = list(AM, curtiles + 1))

/obj/effect/step_trigger/thrower/proc/throw_step(atom/movable/AM, curtiles)
	if(QDELETED(AM))
		throw_end(AM)
		return
	var/stopthrow = 0
	// Calculate if we should stop the process
	if(!nostop)
		for(var/obj/effect/step_trigger/T in get_step(AM, direction))
			if(T.stopper && T != src)
				stopthrow = 1
	else
		for(var/obj/effect/step_trigger/teleporter/T in get_step(AM, direction))
			if(T.stopper)
				stopthrow = 1

	var/predir = AM.dir
	step(AM, direction)
	if(!facedir)
		AM.set_dir(predir)
	if(stopthrow)
		throw_end(AM)
		return
	throw_next(AM, curtiles)

/obj/effect/step_trigger/thrower/proc/throw_end(atom/movable/AM)
	rel_remove(src, nameof(affecting), AM)

	if(ismob(AM))
		var/mob/M = AM
		if(immobilize)
			M.canmove = 1

/* Stops things thrown by a thrower, doesn't do anything */

/obj/effect/step_trigger/stopper

/* Instant teleporter */

/obj/effect/step_trigger/teleporter
	var/teleport_x = 0	// teleportation coordinates (if one is null, then no teleport!)
	var/teleport_y = 0
	var/teleport_z = 0

/obj/effect/step_trigger/teleporter/Trigger(atom/movable/AM)
	if(teleport_x && teleport_y && teleport_z)
		var/turf/T = locate(teleport_x, teleport_y, teleport_z)
		move_object(AM, T)

/obj/effect/step_trigger/teleporter/proc/move_object(atom/movable/AM, turf/T)
	if(!T)
		return
	if(AM.anchored && !istype(AM, /obj/mecha))
		return

	if(isliving(AM))
		var/mob/living/L = AM
		if(L?.pulling_target())
			var/atom/movable/P = L?.pulling_target()
			L.stop_pulling()
			P.forceMove(T)
			L.forceMove(T)
			L.continue_pulling(P)
		else
			L.forceMove(T)
	else
		AM.forceMove(T)

/* Moves things by an offset, useful for 'Bridges'. Uses dir and a distance var to work with maploader direction changes. */
/obj/effect/step_trigger/teleporter/offset
	icon = 'icons/effects/effects.dmi'
	icon_state = "arrow"
	var/distance = 3

/obj/effect/step_trigger/teleporter/offset/north
	dir = NORTH

/obj/effect/step_trigger/teleporter/offset/south
	dir = SOUTH

/obj/effect/step_trigger/teleporter/offset/east
	dir = EAST

/obj/effect/step_trigger/teleporter/offset/west
	dir = WEST

/obj/effect/step_trigger/teleporter/offset/Trigger(atom/movable/AM)
	var/turf/T = get_turf(src)
	for(var/i = 1 to distance)
		T = get_step(T, dir)
		if(!istype(T))
			return
	move_object(AM, T)

/* Random teleporter, teleports atoms to locations ranging from teleport_x - teleport_x_offset, etc */

/obj/effect/step_trigger/teleporter/random
	var/teleport_x_offset = 0
	var/teleport_y_offset = 0
	var/teleport_z_offset = 0

/obj/effect/step_trigger/teleporter/random/Trigger(atom/movable/A)
	if(teleport_x && teleport_y && teleport_z)
		if(teleport_x_offset && teleport_y_offset && teleport_z_offset)
			var/turf/T = locate(rand(teleport_x, teleport_x_offset), rand(teleport_y, teleport_y_offset), rand(teleport_z, teleport_z_offset))
			if(T)
				A.forceMove(T)

/* Teleporter that sends objects stepping on it to a specific landmark. */

/obj/effect/step_trigger/teleporter/landmark
	var/obj/effect/landmark/the_landmark
	var/landmark_id = null

/obj/effect/step_trigger/teleporter/landmark/Initialize(mapload)
	. = ..()
	for(var/obj/effect/landmark/teleport_mark/mark in REGISTRY_MEMBERS(REGISTRY_TELE_LANDMARKS))
		if(mark.landmark_id == landmark_id)
			rel_set(src, nameof(the_landmark), mark)
			return

/obj/effect/step_trigger/teleporter/landmark/Trigger(atom/movable/A)
	if(the_landmark())
		A.forceMove(get_turf(the_landmark()))

/obj/effect/landmark/teleport_mark
	var/landmark_id = null

REGISTRY_MEMBERSHIP(/obj/effect/landmark/teleport_mark, REGISTRY_TELE_LANDMARKS)

/* Teleporter which simulates falling out of the sky. */

/obj/effect/step_trigger/teleporter/planetary_fall
	var/datum/planet/planet_static

// First time setup, which planet are we aiming for?
/obj/effect/step_trigger/teleporter/planetary_fall/proc/find_planet()
	return

/obj/effect/step_trigger/teleporter/planetary_fall/Trigger(atom/movable/A)
	var/turf/T = get_turf(A)
	if(!T)
		return
	T.trigger_fall(A, planet())

//Death

/obj/effect/step_trigger/death
	var/deathmessage = "You die a horrible, brutal and very sudden death."
	var/deathalert = "has stepped on a death trigger."

/obj/effect/step_trigger/death/Trigger(atom/movable/A)
	if(isliving(A))
		to_chat(A, span_danger("[deathmessage]"))
		log_and_message_admins("[deathalert]", A)
		spent(A)

/obj/effect/step_trigger/death/train_lost
	deathmessage = "You fly down the tunnel of the train at high speed for a few moments before impact kills you with sheer concussive force."
	deathalert = "fell off the side of the train and died horribly."

/obj/effect/step_trigger/death/train_crush
	deathmessage = "You get horribly crushed by the train, there's pretty much nothing left of you."
	deathalert = "fell under the train and was crushed horribly."

/obj/effect/step_trigger/death/fly_off
	deathmessage = "You get caught up in the slipstream of the train and quickly dragged down into the tracks. Your body is brutally smashed into the electrified rails and then sucked right under a carriage. No one is finding that mess, thankfully."
	deathalert = "tried to fly away from the train but was died horribly in the process."

//warning

/obj/effect/step_trigger/warning
	var/warningmessage = "Warning!"
	icon_state = "warnmarker"

/obj/effect/step_trigger/warning/Trigger(atom/movable/A)
	if(isliving(A))
		to_chat(A, span_warning("[warningmessage]"))

/obj/effect/step_trigger/warning/train_edge
	warningmessage = "The wind billowing alongside the train is extremely strong here! Any movement could easily pull you down beneath the carriages, return to the train immediately!"

/*
This should actually be refactored if it ever needs to be used again into just being
an event controller with more graceful solutions.
Creating lockers was not graceful, in practice, and creates clutter, for example.
Repurpose this idea into a self contained machine in the future that stores and auto-equips someones gear.

But for now, for what it's been used for, it works.

*/

//Admin tool to automatically strip a human victim of all their equipment and genetics powers, and store them in a closet.
//Equips Vox/Zaddat survival gear, and a few basic pieces of clothing
/obj/effect/step_trigger/autostrip
	name = "Autostrip trigger. Set the targetid to match the effect/autostriptarget"
	var/targetid = "Default"
	/// Keyed relation view: the autostriptarget with our targetid (linked when either materializes).
	var/obj/effect/autostriptarget/target
	/// Keyed relation view: the mob autostriptarget with our targetid.
	var/obj/effect/autostriptarget/mob/Mtarget
	var/remove_implants = 0	//Havn't bothered to implement this yet
	var/remove_mutations = 0

CAPABILITIES(/obj/effect/step_trigger/autostrip)
	ref_one(nameof(target), /obj/effect/autostriptarget, by = nameof(targetid))
	ref_one(nameof(Mtarget), /obj/effect/autostriptarget/mob, by = nameof(targetid))

/obj/effect/step_trigger/autostrip/Trigger(mob/living/carbon/human/H as mob)
	if(!istype(H))
		return
	if(!target_ref())
		return
	if(Mtarget())
		H.forceMove(Mtarget().loc)
	var/obj/locker = new /obj/structure/closet/secure_closet/mind(target_ref().loc, H.mind)
	for(var/obj/item/W in contents_of(H))
		if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
			continue
		if(H.drop_from_inventory(W))
			W.forceMove(locker)

	// Traitgenes new remove genes code, didn't want to solve per-trait unique mutation shenanigans... So we just strip your entire genome. This is an admin anti-powergaming tool anyway.
	if(remove_mutations)
		for(var/datum/gene/gene in GLOB.dna_genes)
			if(gene.name in H.active_genes)
				// Setup injector
				var/obj/item/dnainjector/D = new /obj/item/dnainjector(locker)
				D.name = initial(D.name) + " - RESTORE: [gene.name]" //lazy, but we may as well support base genes... even if unused...
				D.block = gene.block
				D.buf.types = DNA2_BUF_SE
				D.SetValue( H.dna.GetSEValue(gene.block) ) // Get original block's value for the injector
				D.has_radiation = FALSE // safe to use these!
				// Turn off gene
				H.dna.SetSEState(gene.block,0)
			domutcheck(H,null,MUTCHK_FORCED)
			H.UpdateAppearance()
			H.update_mutations()
	if(H.species.name == SPECIES_VOX || H.species.name == SPECIES_ZADDAT)	//Species that 'actually' require survival gear to live. The rest don't.
		H.species.equip_survival_gear(H)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/chameleon(H), SLOT_ID_UNIFORM)
	H.equip_to_slot_or_del(new /obj/item/clothing/shoes/sandal(H),SLOT_ID_SHOES)
	H.equip_to_slot_or_del(new /obj/item/radio/headset(H),SLOT_ID_EAR_L)
	H.equip_to_slot_or_del(new /obj/item/clothing/under/permit(H), SLOT_ID_HAND_L)

/obj/effect/autostriptarget
	name = "Autostrip target. Link me via targetid to an autostrip trigger."
	icon = 'icons/mob/screen1.dmi'
	icon_state = "no_item1"
	var/targetid = "Default"
	unacidable = 1
	layer = 99
	anchored = 1
	invisibility = INVISIBILITY_BADMIN

/obj/effect/autostriptarget/mob
	name = "Autostrip target to send mobs to."

/obj/effect/step_trigger/teleporter/deathfall/Initialize(mapload)
	. = ..()
	teleport_z = src.z //This is for use in gateways, so mappers can hard map the X and Y without worrying about going to brazil

/obj/effect/step_trigger/teleporter/deathfall/Trigger(atom/movable/A)
	var/turf/simulated/T = locate(teleport_x, teleport_y, teleport_z)
	if(!istype(T))
		log_mapping("[src] failed to find destination turf.")
		return
	if(dq_get_hovering(A))//Flying people dont fall
		return
	if(isobserver(A))
		A.forceMove(T) // Harmlessly move ghosts.
		return
	if(A.throwing) //jumpboots
		return
	if(!(A.can_fall())) //test
		return // Phased shifted kin should not fall

	var/mob/living/L
	if(isliving(A))
		L = A
		if(L.is_floating)
			return //Flyers/nograv can ignore it

	A.forceMove(T)
	// Living things should probably be logged when they fall...
	if(isliving(A))
		message_admins("\The [A] fell out of the sky.")
	// ... because they're probably going to die from it.
		A.fall_impact(T, 42, 90, FALSE, TRUE)	//Medical gameplay generator
	else
		message_admins("ERROR: planetary_fall step trigger lacks a planet to fall onto.")
		return

/obj/effect/step_trigger/teleporter/poi/Initialize(mapload) //This is for placing teleporters in gateways/POIS, where Z levels can be different and I cant be assed to make fake teleporter stairs
	. = ..()
	teleport_z = src.z

/obj/effect/step_trigger/teleporter/randomspawn //teleporter/random was taken. This version only teleports when stepped on *sometimes*, and you can give it a chance not to spawn
	var/destroyprob = 99
	var/teleprob = 1

/obj/effect/step_trigger/teleporter/randomspawn/Initialize(mapload)
	. = ..()
	if(destroyprob && prob(destroyprob))
		return INITIALIZE_HINT_QDEL

/obj/effect/step_trigger/teleporter/randomspawn/Trigger()
	if(teleprob && !prob(teleprob))
		return FALSE
	return ..()

/// Relation view: the landmark (reads null once it is gone).
/obj/effect/step_trigger/teleporter/landmark/proc/the_landmark() as /obj/effect/landmark
	return the_landmark

/// The planet (a registered singleton: shared, never cleared).
/obj/effect/step_trigger/teleporter/planetary_fall/proc/planet() as /datum/planet
	return planet_static

/// The keyed relation view `target` (null once it is gone).
/obj/effect/step_trigger/autostrip/proc/target_ref() as /obj/effect/autostriptarget
	return target

/// The keyed relation view `Mtarget` (null once it is gone).
/obj/effect/step_trigger/autostrip/proc/Mtarget() as /obj/effect/autostriptarget/mob
	return Mtarget
