#define UPGRADE_KILL_TIMER	100

///Process_Grab()
///Called by client/Move()
///Checks to see if you are grabbing or being grabbed by anything and if moving will affect your grab.
/client/proc/Process_Grab()
	//if we are being grabbed
	if(isliving(mob))
		var/mob/living/L = mob
		if(!L.canmove && LAZYLEN(L?.grabbed_by_list()))
			L.resist() //shortcut for resisting grabs

		//if we are grabbing someone
		for(var/obj/item/grab/G in list(L.get_equipped_item(SLOT_ID_HAND_L), L.get_equipped_item(SLOT_ID_HAND_R)))
			G.reset_kill_state() //no wandering across the station/asteroid while choking someone

/obj/item/grab
	name = "grab"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "reinforce"
	item_flags = DROPDEL | NOSTRIP
	var/atom/movable/screen/grab/hud = null
	var/state = GRAB_PASSIVE

	var/allow_upgrade = 1
	/// Blocks grab upgrades until UPGRADE_COOLDOWN after the last grab action.
	COOLDOWN_DECLARE(upgrade_cooldown)
	/// Blocks special grab moves until 2 seconds after the last grab action.
	COOLDOWN_DECLARE(action_cooldown)
	var/last_hit_zone = 0
	var/force_down //determines if the affecting mob will be pinned to the ground
	var/dancing //determines if assailant and affecting keep looking at each other. Basically a wrestling position

	abstract = 1
	item_state = "nothing"
	w_class = ITEMSIZE_HUGE

/// The mob a grab is made on (its constructor param, dropped once linked).
/obj/item/grab/var/tmp/mob/victim_at_make

/// The grab link broke: the victim's shift and layer go back.
/mob/living/proc/grab_released(obj/item/grab/G)
	animate(src, pixel_x = initial(pixel_x), pixel_y = initial(pixel_y), 4, 1, LINEAR_EASING)
	reset_plane_and_layer()

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The grab links its holder to the victim, or is spent.
/obj/item/grab/proc/grab_made(mob/living/victim)
	var/mob/living/carbon/human/assailant = loc

	if(!istype(assailant) || !istype(victim) || victim.anchored || !assailant.Adjacent(victim))
		spent(src)
		return

	// The grab link (LK_GRABBING / LK_GRABBED_BY) is the sole store of the victim; its effects are the reveal messages, the dancing check and stopping
	// any pull on the victim.
	if(!link_make(src, LK_GRABBING, victim))
		spent(src)
		return
	victim.reveal(span_warning("You are revealed as [assailant] grabs you."))
	assailant.reveal(span_warning("You reveal yourself as you grab [victim]."))
	// If the assailant is also currently grabbed by their new victim, both
	// grabs enter "dancing" (facing each other, e.g. a wrestling clinch).
	for(var/obj/item/grab/G in assailant.grabbed_by_list())
		if(G.grab_assailant() == victim && G.grab_target() == assailant)
			G.dancing = TRUE
			G.adjust_position()
			dancing = TRUE
	if(assailant.pulling_target() == victim)
		assailant.stop_pulling()

	hud.icon_state = "reinforce"
	icon_state = "grabbed"
	hud.name = "reinforce grab"
	rel_set(hud, nameof(hud.master_ref), src)

	adjust_position()

//Used by throw code to hand over the mob, instead of throwing the grab. The grab is then deleted by the throw code.
/obj/item/grab/proc/throw_held()
	var/mob/living/affecting = src?.grab_target()
	if(affecting)
		if(affecting?.buckled_to())
			return null
		if(state >= GRAB_AGGRESSIVE)
			animate(affecting, pixel_x = initial(affecting.pixel_x), pixel_y = initial(affecting.pixel_y), 4, 1)
			return affecting

	return null

//This makes sure that the grab screen object is displayed in the correct hand.
/obj/item/grab/proc/synch() //why is this needed?
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	if(QDELETED(src))
		return
	var/mob/living/affecting = src?.grab_target()
	if(affecting)
		if(assailant.get_equipped_item(SLOT_ID_HAND_R) == src)
			hud.screen_loc = ui_rhand
		else
			hud.screen_loc = ui_lhand

/obj/item/grab/periodic_step()
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	if(QDELETED(src)) // GC is trying to delete us, we'll kill our processing so we can cleanly GC
		return PROCESS_KILL

	confirm()
	var/mob/living/affecting = src?.grab_target()
	if(!assailant)
		ended_with(src) // Same here, except we're trying to delete ourselves.
		return PROCESS_KILL

	if(assailant.client)
		assailant.client.screen -= hud
		assailant.client.screen += hud

	if(state <= GRAB_AGGRESSIVE)
		allow_upgrade = 1
		//disallow upgrading if we're grabbing more than one person
		if((assailant.get_equipped_item(SLOT_ID_HAND_L) && assailant.get_equipped_item(SLOT_ID_HAND_L) != src && istype(assailant.get_equipped_item(SLOT_ID_HAND_L), /obj/item/grab)))
			var/obj/item/grab/G = assailant.get_equipped_item(SLOT_ID_HAND_L)
			if(G?.grab_target() != affecting)
				allow_upgrade = 0
		if((assailant.get_equipped_item(SLOT_ID_HAND_R) && assailant.get_equipped_item(SLOT_ID_HAND_R) != src && istype(assailant.get_equipped_item(SLOT_ID_HAND_R), /obj/item/grab)))
			var/obj/item/grab/G = assailant.get_equipped_item(SLOT_ID_HAND_R)
			if(G?.grab_target() != affecting)
				allow_upgrade = 0

		//disallow upgrading past aggressive if we're being grabbed aggressively
		for(var/obj/item/grab/G in affecting?.grabbed_by_list())
			if(G == src) continue
			if(G.state >= GRAB_AGGRESSIVE)
				allow_upgrade = 0

		if(allow_upgrade)
			if(state < GRAB_AGGRESSIVE)
				hud.icon_state = "reinforce"
			else
				hud.icon_state = "reinforce1"
		else
			hud.icon_state = "!reinforce"

	if(state >= GRAB_AGGRESSIVE)
		affecting.drop_l_hand()
		affecting.drop_r_hand()

		if(iscarbon(affecting))
			handle_eye_mouth_covering(affecting, assailant, assailant.zone_sel.selecting)

		if(force_down)
			if(affecting.loc != assailant.loc || size_difference(affecting, assailant) > 0)
				force_down = 0
			else
				affecting.status_at_least(STAT_WEAKENED, 2)

	if(state >= GRAB_NECK)
		affecting.status_at_least(STAT_STUNNED, 3)
		if(isliving(affecting))
			var/mob/living/L = affecting
			// A chokehold squeezes the airway for as long as it's held.
			L.body?.add_restriction(src, BF_AIRWAY, (state >= GRAB_KILL ? 0 : 0.3), 3 SECONDS)

	if(state >= GRAB_KILL)
		//affecting.apply_effect(STUTTER, 5) //would do this, but affecting isn't declared as mob/living for some stupid reason.
		affecting.status_at_least(STAT_STUTTERING, 5) //It will hamper your voice, being choked and all.
		affecting.status_at_least(STAT_WEAKENED, 5)	//Should keep you down unless you get help.
		affecting.losebreath = max(affecting.losebreath + 2, 3)

	adjust_position()

/obj/item/grab/proc/handle_eye_mouth_covering(mob/living/carbon/target, mob/user, target_zone)
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	var/mob/living/affecting = src?.grab_target()
	var/announce = (target_zone != last_hit_zone) //only display messages when switching between different target zones
	last_hit_zone = target_zone

	switch(target_zone)
		if(O_MOUTH)
			if(announce)
				act_message(user, target, others = span_warning("%U% covers %T%'s mouth!"))
			if(target.status_units(STAT_MUTED) < 3)
				target.status_set(STAT_MUTED, 3)
		if(O_EYES)
			if(announce)
				act_message(assailant, affecting, others = span_warning("%U% covers %T%'s eyes!"))
			if(affecting.status_units(STAT_BLINDED) < 3)
				affecting.status_at_least(STAT_BLINDED, 3)
		if(BP_HEAD)
			if(force_down)
				if(!user.combat_mode) // the holder's posture while the grab ticks (state)
					if(announce)
						act_message(assailant, target, others = span_warning("%U% sits on %T%'s face!"))


CAPABILITIES(/obj/item/grab)
	op("tighten", in_hand(), label("Tighten grip"), then(PROC_REF(interaction_tighten)))
	// The hands-on inspection of a grabbed limb (mob_grab_specials.dm): each step starts the next, an interrupted one goes on to the next as well.
	op("inspect_organ", ai(), begins(PROC_REF(inspect_organ_text)), wait(1 SECOND), on_interrupt(PROC_REF(inspect_organ_grab_failed)), then(PROC_REF(inspect_organ_grab_done)))
	op("inspect_bones", ai(), wait(2 SECONDS), on_interrupt(PROC_REF(inspect_bones_failed)), then(PROC_REF(inspect_bones_done)))
	op("inspect_skin", ai(), wait(1 SECOND), on_interrupt(PROC_REF(inspect_skin_failed)), then(PROC_REF(inspect_skin_done)))
	// Forcing the grabbed one to the ground (mob_grab_specials.dm): two seconds, the victim staying where they were.
	op("pin_down", ai(), takes("victim", "from"), wait(2 SECONDS), then(PROC_REF(pin_down_grab_done)))
	op("inspect_internal", ai(), wait(5 SECONDS), on_interrupt(PROC_REF(inspect_internal_failed)), then(PROC_REF(inspect_internal_done)))
	op("pin_down", ai(), wait(2 SECONDS), then(PROC_REF(pin_down_grab_done)))
	owns_one(nameof(hud), starts = /atom/movable/screen/grab)
	param(nameof(victim_at_make), pos = 1, apply = PROC_REF(grab_made), keep = FALSE)

/// Old attack_self: upgrade the grab.
/obj/item/grab/proc/interaction_tighten(datum/act/op/A)
	s_click(hud)
	return TRUE

//Updating pixelshift, position and direction
//Gets called on process, when the grab gets upgraded or the assailant moves
/obj/item/grab/proc/adjust_position()
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	var/mob/living/affecting = src?.grab_target()
	if(!affecting)
		spent(src)
		return
	if(affecting?.buckled_to())
		animate(affecting, pixel_x = initial(affecting.pixel_x), pixel_y = initial(affecting.pixel_y), 4, 1, LINEAR_EASING)
		return
	if(affecting.lying && state != GRAB_KILL)
		animate(affecting, pixel_x = initial(affecting.pixel_x), pixel_y = initial(affecting.pixel_y), 5, 1, LINEAR_EASING)
		if(force_down)
			affecting.set_dir(SOUTH) //face up
		return
	var/shift = 0
	var/adir = get_dir(assailant, affecting)
	affecting.layer = MOB_LAYER
	switch(state)
		if(GRAB_PASSIVE)
			shift = 8
			if(dancing) //look at partner
				shift = 10
				assailant.set_dir(get_dir(assailant, affecting))
		if(GRAB_AGGRESSIVE)
			shift = 12
		if(GRAB_NECK, GRAB_UPGRADING)
			shift = -10
			adir = assailant.dir
			affecting.set_dir(assailant.dir)
			affecting.forceMove(assailant.loc)
		if(GRAB_KILL)
			shift = 0
			adir = 1
			affecting.set_dir(SOUTH) //face up
			affecting.forceMove(assailant.loc)

	switch(adir)
		if(NORTH)
			animate(affecting, pixel_x = initial(affecting.pixel_x), pixel_y =-shift, 5, 1, LINEAR_EASING)
			affecting.layer = BELOW_MOB_LAYER
		if(SOUTH)
			animate(affecting, pixel_x = initial(affecting.pixel_x), pixel_y = shift, 5, 1, LINEAR_EASING)
		if(WEST)
			animate(affecting, pixel_x = shift, pixel_y = initial(affecting.pixel_y), 5, 1, LINEAR_EASING)
		if(EAST)
			animate(affecting, pixel_x =-shift, pixel_y = initial(affecting.pixel_y), 5, 1, LINEAR_EASING)

/obj/item/grab/proc/s_click(atom/movable/screen/S)
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	if(QDELETED(src))
		return
	var/mob/living/affecting = src?.grab_target()
	if(!affecting)
		return
	if(state == GRAB_UPGRADING)
		return
	if(!COOLDOWN_FINISHED(src, upgrade_cooldown))
		return
	if(!assailant.canmove || assailant.lying)
		spent(src)
		return

	note_action()

	if(state < GRAB_AGGRESSIVE)
		if(!allow_upgrade)
			return
		if(!affecting.lying || size_difference(affecting, assailant) > 0)
			act_message(assailant, affecting, others = span_warning("%U% has grabbed %T% aggressively (now hands)!"))
		else
			act_message(assailant, affecting, others = span_warning("%U% pins %T% down to the ground (now hands)!"))
			apply_pinning(affecting, assailant)

		state = GRAB_AGGRESSIVE
		icon_state = "grabbed1"
		hud.icon_state = "reinforce1"
		add_attack_logs(assailant, affecting, "Aggressively grabbed", FALSE) // Not important enough to notify admins, but still helpful.
	else if(state < GRAB_NECK)
		if(isslime(affecting))
			to_chat(assailant, span_notice("You squeeze [affecting], but nothing interesting happens."))
			return

		act_message(assailant, affecting, others = span_warning("%U% has reinforced %THEIR% grip on %T% (now neck)!"))
		state = GRAB_NECK
		icon_state = "grabbed+1"
		assailant.set_dir(get_dir(assailant, affecting))
		add_attack_logs(assailant,affecting,"Neck grabbed")
		hud.icon_state = "kill"
		hud.name = "kill"
		affecting.status_at_least(STAT_STUNNED, 10) //10 ticks of ensured grab
	else if(state < GRAB_UPGRADING)
		act_message(assailant, affecting, others = span_danger("%U% starts to tighten %THEIR% grip on %T%'s neck!"))
		hud.icon_state = "kill1"

		state = GRAB_KILL
		act_message(assailant, affecting, others = span_danger("%U% has tightened %THEIR% grip on %T%'s neck!"))
		add_attack_logs(assailant,affecting,"Strangled")
		affecting.setClickCooldown(10)
		affecting.AdjustLosebreath(1)
		affecting.set_dir(WEST)
	adjust_position()

//This is used to make sure the victim hasn't managed to yackety sax away before using the grab.
/obj/item/grab/proc/confirm()
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	var/mob/living/affecting = src?.grab_target()
	if(!assailant || !affecting)
		spent(src)
		return 0

	if(affecting)
		if(!isturf(assailant.loc) || ( !isturf(affecting.loc) || assailant.loc != affecting.loc && get_dist(assailant, affecting) > 1) )
			spent(src)
			return 0

	return 1

/obj/item/grab/attack(mob/living/M, mob/living/user, target_zone, attack_modifier, stance = I_HURT)
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	if(QDELETED(src))
		return ITEM_INTERACT_FAILURE
	var/mob/living/affecting = src?.grab_target()
	if(!affecting)
		return ITEM_INTERACT_FAILURE
	if(!COOLDOWN_FINISHED(src, action_cooldown))
		return ITEM_INTERACT_FAILURE

	note_action()
	reset_kill_state() //using special grab moves will interrupt choking them

	//clicking on the victim while grabbing them
	if(M == affecting)
		if(ishuman(affecting))
			var/mob/living/carbon/human/H = affecting
			var/hit_zone = assailant.zone_sel.selecting
			flick(hud.icon_state, hud)
			switch(stance) // the victim's per-stance item interaction (Use on / Shove with / Hold with / Hit)
				if(I_HELP)
					if(force_down)
						to_chat(assailant, span_warning("You are no longer pinning [affecting] to the ground."))
						force_down = 0
					if(state >= GRAB_AGGRESSIVE)
						H.apply_pressure(assailant, hit_zone)
					else
						inspect_organ(affecting, assailant, hit_zone)

				if(I_GRAB)
					jointlock(affecting, assailant, hit_zone)

				if(I_HURT)
					if(hit_zone == O_EYES)
						attack_eye(affecting, assailant)
					else if(hit_zone == BP_HEAD)
						headbutt(affecting, assailant)
					else
						dislocate(affecting, assailant, hit_zone)

				if(I_DISARM)
					pin_down(affecting, assailant)
			return ITEM_INTERACT_SUCCESS
	return ITEM_INTERACT_FAILURE

/obj/item/grab/proc/reset_kill_state()
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	var/mob/living/affecting = src?.grab_target()
	if(state == GRAB_KILL)
		act_message(assailant, affecting, others = span_warning("%U% lost %THEIR% tight grip on %T%'s neck!"))
		hud.icon_state = "kill"
		state = GRAB_NECK

/obj/item/grab/proc/handle_resist()
	var/mob/living/carbon/human/assailant = src?.grab_assailant()
	var/mob/living/affecting = src?.grab_target()
	var/grab_name
	var/break_strength = 1
	var/list/break_chance_table = list(100)
	switch(state)

		if(GRAB_AGGRESSIVE)
			grab_name = "grip"
			//Being knocked down makes it harder to break a grab, so it is easier to cuff someone who is down without forcing them into unconsciousness.
			if(!affecting.incapacitated(INCAPACITATION_KNOCKDOWN))
				break_strength++
			break_chance_table = list(15, 60, 100)

		if(GRAB_NECK)
			grab_name = "headlock"
			//If the you move when grabbing someone then it's easier for them to break free. Same if the affected mob is immune to stun.
			if(ELAPSED_SINCE(src, assailant.l_move_time, CLOCK_WORLD) < 30 || !affecting.has_status(STAT_STUNNED))
				break_strength++
			break_chance_table = list(3, 18, 45, 100)

		if(GRAB_KILL)
			grab_name = "stranglehold"
			break_chance_table = list(5, 20, 40, 80, 100)

	//It's easier to break out of a grab by a smaller mob
	break_strength += max(size_difference(affecting, assailant), 0)
	var/prob_mult = 1
	var/mob/living/carbon/human/grabbee = affecting
	var/mob/living/carbon/human/grabber = assailant
	if(istype(grabbee))
		prob_mult /= grabbee.species.grab_resist_divisor_self
		break_strength += grabbee.species.grab_power_self
	if(istype(grabber))
		prob_mult /= grabber.species.grab_resist_divisor_victims
		break_strength += grabber.species.grab_power_victims

	var/break_chance = CLAMP(prob_mult*break_chance_table[CLAMP(break_strength, 1, break_chance_table.len)],0,100)
	if(prob(break_chance))
		if(state == GRAB_KILL)
			reset_kill_state()
			return
		else if(grab_name)
			act_message(affecting, assailant, others = span_warning("%U% has broken free of %T%'s [grab_name]!"))
		spent(src)

//returns the number of size categories between affecting and assailant, rounded. Positive means A is larger than B
/obj/item/grab/proc/size_difference(mob/A, mob/B)
	return mob_size_difference(A.mob_size, B.mob_size)

#undef UPGRADE_KILL_TIMER

/// Starts both grab action cooldowns (upgrade and special-move) together.
/obj/item/grab/proc/note_action()
	COOLDOWN_START(src, upgrade_cooldown, UPGRADE_COOLDOWN)
	COOLDOWN_START(src, action_cooldown, 2 SECONDS)
