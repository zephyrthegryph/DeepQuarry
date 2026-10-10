/obj/item/ghost_catcher
	name = "proton rifle"
	desc = "A two handed device, used for 'catching ghosts'. Weakens the entity initially grabbed."
	icon = 'icons/obj/guns/ghost_beam.dmi'
	icon_state = "ghost_beam"
	w_class = ITEMSIZE_NORMAL
	force = 0
	slot_flags = SLOT_BELT
	var/grab_range = 5 // How many tiles away it can grab. Changing this also changes the box size.
	/// Stops multiple grabbs if set to TRUE
	/// The entity we are currently grabbing.
	/// Relation view: the entity held in the beam.
	var/atom/movable/grabbed_entity
	/// How far we can move an entity in one go!
	var/max_move_distance = 1
	/// If we're held in two hands or not...Used until we get two handed component.
	var/wielded = FALSE

	COOLDOWN_DECLARE(ghost_cooldown)
	COOLDOWN_DECLARE(click_cooldown)

	//TODO:
	// Make ghosts/phased entities slow when grabbed
	// Make it so it searches in an AOE and grabs thing.

/obj/item/ghost_catcher/proc/appearance_busy()
	return op_claimed(src) ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/ghost_catcher/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_busy() ? "_active" : ""]")

/obj/item/ghost_catcher/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && M.can_wield_item(src) && is_held_twohanded(M))
		wielded = TRUE
	else
		wielded = FALSE
	..()

/obj/item/ghost_catcher/afterattack(atom/target, mob/user, proximity_flag)
	update_held_icon()
	if(!wielded)
		to_chat(user, span_warning("You need to hold \the [src] in two hands to use it!"))
		return

	if(!COOLDOWN_FINISHED(src, ghost_cooldown))
		to_chat(user, span_warning("The [src] is recharging!"))
		return
	if(!COOLDOWN_FINISHED(src, click_cooldown))
		to_chat(user, span_warning("The [src] needs time between movements!"))
		return

	if(isturf(target) && (!target.incorporeal_grab()))
		var/turf/T = target
		if(!op_claimed(src))
			for(var/mob/entity in range(1, T)) //We'll let you grab things ON the tile or AROUND the tile you click on.
				if(entity.incorporeal_grab())
					target = entity
					break
			if(!ismob(target))
				to_chat(user, span_warning("No valid target in range! Beginning cooldown."))
				COOLDOWN_START(src, ghost_cooldown, 3 SECONDS) //Prevent from spamclicking to find ghosts.
				return
		else
			if(grabbed_entity)
				var/atom/movable/entity = grabbed_entity
				if(get_dist(T, entity) > max_move_distance)
					to_chat(user, span_warning("\The [src] is unable to pull the entity that far!"))
					return
				entity.forceMove(T)
				COOLDOWN_START(src, click_cooldown, 1 SECOND)
				return

	if(istype(target, /obj/item/ghost_trap)) //Special handling for traps, since traps are full sized objects and not turf.
		var/obj/item/ghost_trap/trap = target
		var/atom/movable/entity = grabbed_entity
		if(!trap.deployed)
			to_chat(user, span_warning("The trap isn't deployed!"))
			return
		if(!entity)
			to_chat(user, span_warning("No valid target!"))
			return
		if(get_dist(trap, entity) > max_move_distance)
			to_chat(user, span_warning("\The [src] is unable to pull the entity that far!"))
			return
		entity.forceMove(get_turf(trap))
		COOLDOWN_START(src, click_cooldown, 1 SECOND)
		return

	// Things that invalidate the scan immediately.
	if(op_claimed(src))
		to_chat(user, span_warning("\The [src] is already grabbing an entity!"))
		return

	if(!target.incorporeal_grab(user)) // This will tell the user what is wrong.
		return

	if(get_dist(target, user) > grab_range)
		to_chat(user, span_warning("You are too far away from \the [target] to catalogue it. Get closer."))
		return

	// Start the special effects.
	var/datum/beam/scan_beam = user.Beam(target, icon_state = "curse1", time = 60 SECONDS)
	var/filter = filter(type = "outline", size = 1, color = "#330099")
	target.filters += filter
	var/list/box_segments = list()
	if(user.client)
		box_segments = draw_box(target, grab_range, user.client)
		color_box(box_segments, "#330099", 60 SECONDS)

	play_sfx(src, SFX_MACHINES_BEEP)

	rel_set(src, nameof(grabbed_entity), target)
	if(isliving(target))
		var/mob/living/target_mob = target
		target_mob.status_at_least(STAT_WEAKENED, 3)
		target_mob.status_at_least(STAT_STUNNED, 3)
		to_chat(target, span_danger("You feel yourself weakened from the [src]'s beam!"))

	// The delay, and test for if the scan succeeds or not. The grab claims the catcher
	// (op_claimed()) until it ends; the effects travel in a list (the beam ends itself).
	var/list/effects = list(scan_beam, filter, box_segments)
	var/datum/op_result/started = perform_op(user, src, "grab", src, ORIGIN_AI, AUTH_AI | AUTH_PHYSICAL, with = list("subject" = target, "effects" = effects))
	if(!started || started.outcome == ACT_REFUSED)
		grab_ended(target, user, effects)
		return

/// The grab was cut short (the catcher put down, the user down): the effects end.
/obj/item/ghost_catcher/proc/grab_broken(datum/act/op/A)
	grab_ended(A.arg("subject"), A.actor, A.arg("effects"))

/// The grab is over (broken or done): clean up the effects and start the cooldown.
/obj/item/ghost_catcher/proc/grab_ended(atom/target, mob/user, list/effects)
	var/datum/beam/scan_beam = effects[1]
	if(!QDELETED(scan_beam))
		scan_beam.End()
	if(target)
		target.filters -= effects[2]
	if(user?.client) // If for some reason they logged out mid-scan the box will be gone anyways.
		delete_box(effects[3], user.client)
	rel_clear(src, nameof(grabbed_entity))
	COOLDOWN_START(src, ghost_cooldown, 10 SECONDS) // Arbitrary cooldown to prevent spam. Adjust as needed.

/obj/item/ghost_catcher/proc/grab_timed_out(datum/act/op/A)
	var/atom/target = A.arg("subject")
	var/mob/user = A.actor
	var/list/effects = A.arg("effects")
	to_chat(user, span_warning("With a buzz, \the [src] flashes red, the beam on \the [target] has broken!"))
	play_sfx(src, SFX_MACHINES_BUZZ_TWO)
	color_box(effects[3], "#330099", 3)
	grab_ended(target, user, effects)
	return OP_OK

CAPABILITIES(/obj/item/ghost_catcher)
	// Holding a ghost in the beam, up to a minute; the catcher is claimed (busy) until it ends. The user may walk about while it lasts.
	op("grab", ai(), takes("subject", "effects"), claims(CLAIM_TARGET), wait(60 SECONDS, keeps = HELD | TARGET_PRESENT | ALIVE), on_interrupt(PROC_REF(grab_broken)), then(PROC_REF(grab_timed_out)))

/atom/proc/incorporeal_grab(mob/user)
	if(is_incorporeal())
		return TRUE
	return FALSE

/mob/observer/dead/incorporeal_grab(mob/user) // Dead mobs can't be scanned.
	if(admin_ghosted || !interact_with_world)
		to_chat(user, span_notice("No entity detected!")) //The goggles ARE listed as unreliable. You could just be seeing static.
		return FALSE
	return ..()

//The backpack the gun is (typically) attached to!
/obj/item/proton_pack
	name = "proton pack"
	desc = "A complex backpack that houses a miniature antimatter reactor to power a spectral capture device."
	icon = 'icons/obj/technomancer.dmi'
	default_worn_icon = 'icons/inventory/back/mob.dmi'
	icon_state = "technomancer_core"
	item_state = "proton_pack"
	slot_flags = SLOT_BACK
	preserve_item = 1
	w_class = ITEMSIZE_LARGE
	unacidable = TRUE
	var/who_ya_gunna_call = /obj/item/ghost_catcher

/obj/item/proton_pack/Initialize(mapload)
	make_tethered(who_ya_gunna_call)
	. = ..()

CAPABILITIES(/obj/item/proton_pack)
	op("interaction_hand", hand(), then(PROC_REF(interaction_hand)))
	drag_onto(PROC_REF(drop_input))

/// Old attack_hand.
/obj/item/proton_pack/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	// See important note in code/datums/behaviours/tethered_item.dm
	if(tether_swap(user))
		return TRUE
	return OP_DECLINE

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). The worn pack is dragged into its wearer's hands.
/obj/item/proton_pack/proc/drop_input(datum/act/input/A)
	drag_backpack_with_actor(A.actor)
	return TRUE

/obj/item/proton_pack/proc/drag_backpack_with_actor(mob/user)
	if(ismob(src.loc))
		if(!CanMouseDrop(src, user))
			return
		var/mob/M = src.loc
		if(!M.unEquip(src))
			return
		src.add_fingerprint(user)
		M.put_in_any_hand_if_possible(src)
