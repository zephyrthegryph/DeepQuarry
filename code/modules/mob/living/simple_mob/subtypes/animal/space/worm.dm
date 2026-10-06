/mob/living/simple_mob/animal/space/space_worm
	name = "space worm segment"
	desc = "A part of a space worm."
	icon = 'icons/mob/worm.dmi'
	icon_state = "spaceworm"
	icon_living = "spaceworm"
	icon_dead = "spacewormdead"

	tt_desc = "U Tyranochaetus imperator"

	anchored = TRUE	// Theoretically, you shouldn't be able to move this without moving the head.

	endurance = 200
	movement_cooldown = -1

	faction = FACTION_WORM

	status_flags = 0
	universal_speak = 0
	universal_understand = 1
	animate_movement = SYNC_STEPS

	response_help  = "touches"
	response_disarm = "flails at"
	response_harm   = "punches the"

	harm_intent_damage = 2

	attacktext = list("slammed")

	organ_names = /datum/decl/mob_organ_names

	mob_class = MOB_CLASS_ABERRATION	// It's a monster.

	meat_amount = 10
	meat_type = /obj/item/reagent_containers/food/snacks/meat/worm

	var/mob/living/simple_mob/animal/space/space_worm/previous //next/previous segments, correspondingly
	var/mob/living/simple_mob/animal/space/space_worm/next     //head is the nextest segment

	var/severed = FALSE	// Is this a severed segment?

	var/severed_head_type = /mob/living/simple_mob/animal/space/space_worm/head/severed	// What type of head do we spawn when detaching?
	var/segment_type = /mob/living/simple_mob/animal/space/space_worm	// What type of segment do our heads make?

	var/stomachProcessProbability = 50
	var/digestionProbability = 20
	var/flatPlasmaValue = 5 //flat Phoron amount given for non-items

	var/atom/currentlyEating // Worm's current Maw target.

	var/z_transitioning = FALSE	// Are we currently moving between Z-levels, or doing something that might mean we can't rely on distance checking for segments?
	var/sever_chunks = FALSE	// Do we fall apart when dying?

	COOLDOWN_DECLARE(maw_cooldown_until)	// Ends maw_cooldown after the maw opens; also the auto-stop time while open.
	var/maw_cooldown = 30 SECONDS
	var/open_maw = FALSE	// Are we trying to eat things?

	can_be_drop_prey = FALSE

/mob/living/simple_mob/animal/space/space_worm/head
	name = "space worm"
	icon_state = "spacewormhead"
	icon_living = "spacewormhead"

	anchored = FALSE	// You can pull the head to pull the body.

	endurance = 300

	// dq_get_hovering(src) type-default moved to GLOB.dq_hovering_by_type

	melee_damage_lower = 10
	melee_damage_upper = 25
	attack_injury_kind = INJURY_CUT
	attack_armor_pen = 30
	attacktext = list("bitten", "gored", "gouged", "chomped", "slammed")

	animate_movement = SLIDE_STEPS

	var/segment_count = 6

/mob/living/simple_mob/animal/space/space_worm/head/severed
	segment_count = 0
	severed = TRUE

/mob/living/simple_mob/animal/space/space_worm/head/short
	segment_count = 3

/mob/living/simple_mob/animal/space/space_worm/head/long
	segment_count = 10

/mob/living/simple_mob/animal/space/space_worm/head/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/space/space_worm/head/life_special(datum/seq_frame/life/F)
	..()
	src.update_body_faction()

DECLARE_APPEARANCE_PROC(/mob/living/simple_mob/animal/space/space_worm/head, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/simple_mob/animal/space/space_worm/head/appearance_overlays()
	. = list()
	. += ..()
	if(!open_maw && !stat)
		icon_state = "[icon_living][previous ? 1 : 0]_hunt"
	else
		icon_state = "[icon_living][previous ? 1 : 0]"

	if(previous)
		set_dir(get_dir(previous,src))

	if(stat)
		icon_state = "[icon_state]_dead"

/mob/living/simple_mob/animal/space/space_worm/head/Initialize(mapload)
	. = ..()

	var/mob/living/simple_mob/animal/space/space_worm/current = src

	if(segment_count && !severed)
		for(var/i = 1 to segment_count)
			var/mob/living/simple_mob/animal/space/space_worm/newSegment = new segment_type(loc)
			current.Attach(newSegment)
			current = newSegment
			current.faction = faction

/mob/living/simple_mob/animal/space/space_worm/head/verb/toggle_devour()
	set name = "Toggle Feeding"
	set desc = "Extends your teeth for 30 seconds so that you can chew through mobs and structures alike."
	set category = VERB_CAT_ABILITIES_WORM

	if(!COOLDOWN_FINISHED(src, maw_cooldown_until))
		if(open_maw)
			to_chat(src, span_notice("You retract your teeth."))
			maw_cooldown_until -= maw_cooldown / 2	// Recovers half cooldown if you end it early manually.
		else
			to_chat(src, span_notice("You are too tired to do this.."))
		set_maw(FALSE)
	else
		set_maw(!open_maw)

/mob/living/simple_mob/animal/space/space_worm/proc/set_maw(state = FALSE)
	open_maw = state
	if(open_maw)
		COOLDOWN_START(src, maw_cooldown_until, maw_cooldown)
		movement_cooldown = initial(movement_cooldown) + 1.5
	else
		movement_cooldown = initial(movement_cooldown)
	update_icon()

/mob/living/simple_mob/animal/space/space_worm/on_death(gibbed)
	..()

	DumpStomach()

	if(previous)
		previous.death()

/mob/living/simple_mob/animal/space/space_worm/life_special_due()
	return TRUE

/mob/living/simple_mob/animal/space/space_worm/life_special(datum/seq_frame/life/F)
	..()

	if(COOLDOWN_FINISHED(src, maw_cooldown_until))	// Auto-stop eating.
		if(src.open_maw)
			to_chat(src, span_notice("Your jaws cannot remain open.."))
			src.set_maw(FALSE)

	if(src.next && !(src.next in view(src,1)) && !src.z_transitioning)
		src.Detach(1)

	if(src.stat == DEAD && src.sever_chunks) // Dead chunks fall off and die immediately if we sever_chunks
		if(src.previous)
			src.previous.Detach(1)
		if(src.next)
			src.Detach(1)

	if(prob(src.stomachProcessProbability))
		src.ProcessStomach()

	src.update_icon()

	return

/mob/living/simple_mob/animal/space/space_worm/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /mob/living/simple_mob/animal/space/space_worm/head))
		var/mob/living/simple_mob/animal/space/space_worm/head/H = mover
		if(H.previous == src)
			return FALSE

	if(istype(mover, /mob/living/simple_mob/animal/space/space_worm))	// Worms don't run over worms. That's weird. And also really annoying.
		return TRUE
	else if(src.stat == DEAD && !istype(mover, /obj/item/projectile))	// Projectiles need to do their normal checks.
		return TRUE
	return ..()

// a destroyed chunk empties its stomach and kills the back half.
/mob/living/simple_mob/animal/space/space_worm/on_destroy(force) // If a chunk is destroyed, kill the back half.
	DumpStomach()
	if(previous)
		previous.Detach(1)
	..()

/mob/living/simple_mob/animal/space/space_worm/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	if(previous)
		if(previous.z != z)
			previous.z_transitioning = TRUE
		else
			previous.z_transitioning = FALSE
		previous.forceMove(old_loc)	// None of this 'ripped in half by an airlock' business.
	update_icon()

/mob/living/simple_mob/animal/space/space_worm/head/Bump(atom/obstacle)
	if(open_maw && !stat && obstacle != previous)
		after(src, 0.1 SECONDS, PROC_REF(bump_eat), with = list(obstacle)) // a tick later, after the bump settles
	else
		rel_clear(src, nameof(currentlyEating))
		. = ..(obstacle)

DECLARE_APPEARANCE_PROC(/mob/living/simple_mob/animal/space/space_worm, TYPE_PROC_REF(/atom, appearance_overlays), list())
/mob/living/simple_mob/animal/space/space_worm/appearance_overlays()
	. = list()
	if(previous) //midsection
		icon_state = "spaceworm[get_dir(src,previous) | get_dir(src,next)]"
		if(stat)
			icon_state = "[icon_state]_dead"

	else //tail
		icon_state = "spacewormtail"
		if(stat)
			icon_state = "[icon_state]_dead"
		set_dir(get_dir(src,next))

	if(next)
		color = next.color

	return .

/// Bump()'s deferred half: starts eating what the maw ran into.
/mob/living/simple_mob/animal/space/space_worm/proc/bump_eat(atom/obstacle)
	if(currentlyEating != obstacle)
		rel_set(src, nameof(currentlyEating), obstacle)
	ai_busy_begin()
	AttemptToEat(obstacle)

/// Starts eating `target`; eat_finished() reports the outcome.
/mob/living/simple_mob/animal/space/space_worm/proc/AttemptToEat(atom/target)
	if(istype(target,/turf/simulated/wall))
		var/turf/simulated/wall/W = target
		// 10 seconds for an R-wall, 5 seconds for a normal one.
		task_timed(src, W.reinf_material ? 10 SECONDS : 5 SECONDS, target = target, receiver = src, on_done = PROC_REF(eat_wall_done), done_args = list(W), on_fail = PROC_REF(eat_finished), fail_args = list(FALSE))
		return
	if(istype(target,/atom/movable))
		if(istype(target,/mob))
			eat_movable(target)
		else // 5 ticks to eat stuff like tables.
			task_timed(src, 5, target = target, receiver = src, on_done = PROC_REF(eat_movable), done_args = list(target), on_fail = PROC_REF(eat_finished), fail_args = list(FALSE))
		return
	eat_finished(FALSE)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_finished(success)
	if(success)
		rel_clear(src, nameof(currentlyEating))
	ai_busy_end()

/mob/living/simple_mob/animal/space/space_worm/proc/eat_wall_done(turf/simulated/wall/W)
	W.dismantle_wall()
	eat_finished(TRUE)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_movable(atom/movable/objectOrMob)
	if(istype(objectOrMob, /obj/machinery/door))	// Doors and airlocks take time based on their durability and our damageo.
		var/obj/machinery/door/D = objectOrMob
		eat_door_hit(D, 1, max(2, round(D.max_integrity / (2 * melee_damage_upper))))
		return
	if(istype(objectOrMob, /obj/effect/energy_field))
		var/obj/effect/energy_field/EF = objectOrMob
		if(EF.opacity)
			EF.visible_message(span_danger("Something begins forcing itself through \the [EF]!"))
		else
			EF.visible_message(span_danger("\The [src] begins forcing itself through \the [EF]!"))
		// No eating shields.
		task_timed(src, EF.get_strength() * 5, target = EF, receiver = src, on_done = PROC_REF(eat_field_done), done_args = list(EF), on_fail = PROC_REF(eat_field_failed), fail_args = list(EF))
		return
	eat_consume(objectOrMob)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_door_hit(obj/machinery/door/D, hit, total_hits)
	task_start(/datum/task/timed/worm_batter_door, src, D, hits_left = total_hits - hit + 1)

/// Battering a door (the target) a hit every half second until it breaks or the hits run out,
/// then swallowing it.
/datum/task/timed/worm_batter_door
	steps = list(/mob/living/simple_mob/animal/space/space_worm/proc/eat_door_struck = 5)
	cancel_proc = /mob/living/simple_mob/animal/space/space_worm/proc/eat_task_failed
	var/hits_left = 1

/mob/living/simple_mob/animal/space/space_worm/proc/eat_task_failed(datum/task/timed/task)
	eat_finished(FALSE)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_door_struck(datum/task/timed/worm_batter_door/task)
	var/obj/machinery/door/D = task.target
	D.visible_message(span_danger("Something crashes against \the [D]!"))
	D.take_damage(2 * melee_damage_upper, BRUTE, MELEE)
	if(QDELETED(D))
		return STEP_FAIL("gone")
	if(!D.operable())
		D.open(TRUE)
		eat_consume(D)
		return STEP_DONE
	if(--task.hits_left > 0)
		return STEP_REPEAT(5)
	eat_consume(D)
	return STEP_DONE

/mob/living/simple_mob/animal/space/space_worm/proc/eat_field_done(obj/effect/energy_field/EF)
	EF.adjust_strength(rand(-8, -10))
	EF.visible_message(span_danger("\The [src] crashes through \the [EF]!"))
	eat_finished(FALSE)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_field_failed(obj/effect/energy_field/EF)
	EF.visible_message(span_danger("\The [EF] reverberates as it returns to normal."))
	eat_finished(FALSE)

/mob/living/simple_mob/animal/space/space_worm/proc/eat_consume(atom/movable/objectOrMob)
	objectOrMob.update_nearby_tiles(need_rebuild=1)
	objectOrMob.forceMove(src)
	eat_finished(TRUE)

/mob/living/simple_mob/animal/space/space_worm/proc/Attach(mob/living/simple_mob/animal/space/space_worm/attachement)
	if(!attachement)
		return

	rel_set(src, nameof(previous), attachement)
	rel_set(attachement, nameof(attachement.next), src)

	return

/mob/living/simple_mob/animal/space/space_worm/proc/Detach(die = 0)
	if(loc?.release_refusal(src))
		return
	var/mob/living/simple_mob/animal/space/space_worm/head/newHead = new severed_head_type(loc,0)
	var/mob/living/simple_mob/animal/space/space_worm/newHeadPrevious = previous

	rel_clear(src, nameof(previous)) //so that no extra heads are spawned

	newHead.Attach(newHeadPrevious)

	if(die)
		newHead.death()

	consume(src)

/mob/living/simple_mob/animal/space/space_worm/proc/ProcessStomach()
	for(var/atom/movable/stomachContent in contents)
		if(stomach_special(stomachContent))
			continue
		if(prob(digestionProbability))
			if(stomach_special_digest(stomachContent))
				continue
			if(istype(stomachContent,/obj/item/stack)) //converts to plasma, keeping the stack value
				if(!istype(stomachContent,/obj/item/stack/material/phoron))
					var/obj/item/stack/oldStack = stomachContent
					new /obj/item/stack/material/phoron(src, oldStack.get_amount())
					dissolved(oldStack, src)
					continue
			else if(istype(stomachContent,/obj/item)) //converts to plasma, keeping the w_class
				var/obj/item/oldItem = stomachContent
				new /obj/item/stack/material/phoron(src, oldItem.w_class)
				dissolved(oldItem, src)
				continue
			else
				new /obj/item/stack/material/phoron(src, flatPlasmaValue) //just flat amount
				if(!isliving(stomachContent))
					dissolved(stomachContent, src)
				else
					var/mob/living/L = stomachContent
					if(iscarbon(L))
						var/mob/living/carbon/C = L
						var/damage_cycles = rand(3, 5)
						for(var/I = 0, I < damage_cycles, I++)
							C.injure(INJURY_CORROSIVE, rand(10,20), pick(BP_ALL), src)
					else
						L.injure(INJURY_CORROSIVE, rand(10,60), source = src)
				continue

	DumpStomach()

	return

/mob/living/simple_mob/animal/space/space_worm/proc/DumpStomach()
	if(previous && previous.stat != DEAD)
		for(var/atom/movable/stomachContent in contents) //transfer it along the digestive tract
			stomachContent.forceMove(previous)
	else
		for(var/atom/movable/stomachContent in contents) // Or dump it out.
			stomachContent.forceMove(get_turf(src))
	return

/mob/living/simple_mob/animal/space/space_worm/proc/stomach_special(atom/A)	// Futureproof. Anything that interacts with contents without relying on digestion probability. Return TRUE if it should skip digest.
	return FALSE

/mob/living/simple_mob/animal/space/space_worm/proc/stomach_special_digest(atom/A)	// Futureproof. Any special checks that interact with digested atoms. I.E., ore processing. Return TRUE if it should skip future digest checks.
	return FALSE

/mob/living/simple_mob/animal/space/space_worm/proc/update_body_faction()
	if(next)	// Keep us on the same page, here.
		faction = next.faction
	if(previous)
		previous.update_body_faction()
		return 1
	return 0

// Neighbouring segments: Destroy() severs the back half and unlinks the front.

/// Immune to incapacitation by nature (stun, weakness, paralysis).
CAPABILITIES(/mob/living/simple_mob/animal/space/space_worm)
	immune_to_incapacitation()
