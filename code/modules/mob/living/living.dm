/mob/living/proc/get_visible_name()
	// A hook on the mob may name it (shadekin phase hiding); nothing is allocated when nothing hooks it.
	var/datum/act/name_visible/shown = ACT_TRY(src, name_visible)
	if(!shown)
		return ACT_REPLY
	act_cancel(shown)

	if(real_name)
		return real_name
	else
		return name

// the base living mob: Life, body effects, soul links, nest, transformed holder and organs.
/mob/living/on_destroy(force)
	life_leave_z()
	clear_body_effects(TRUE)
	// The owned dna is deleted with the body (phase 4). The identity names it by
	// handle, which can't keep it alive: nulling `dna` here only let BYOND free it
	// without qdel(), so the identity's handle then reported a collected target.
	for(var/datum/soul_link/S as anything in owned_soul_links?.Copy())
		S.owner_died(FALSE)
		rel_remove(src, nameof(owned_soul_links), S) // The owner retires its soul link after the death callback.
	for(var/datum/soul_link/S as anything in shared_soul_links?.Copy())
		S.sharer_died(FALSE)
		S.remove_soul_sharer(src) // If a sharer is destroy()'d, they are simply removed.
	if(nest) //Ew.
		if(istype(nest, /obj/structure/prop/nest))
			var/obj/structure/prop/nest/N = nest
			N.remove_creature(src)
		// a blob spore leaves its factory's spores through the pair's teardown
		if(istype(nest, /obj/structure/mob_spawner))
			var/obj/structure/mob_spawner/S = nest
			S.get_death_report(src)
		nest = null
	// BUCKLED(src) is already null here: the buckled_to relation
	// (code/datums/om/library.dm) unlinked in the destroy transaction's phase
	// 5 teardown, before Destroy() ran, and its on_unlink() hook did the
	// unbuckling.
	if(tf_mob_holder && tf_mob_holder.loc == src)
		return_player_to_tf_holder("transformed form destroyed")
		if(isbelly(loc))
			tf_mob_holder.forceMove(loc)
		else
			var/turf/get_dat_turf = get_turf(src)
			tf_mob_holder.forceMove(get_dat_turf)
		// the holder's old bellies go (it owns them)
		own_clear(tf_mob_holder, nameof(tf_mob_holder.vore_organs), OWN_DELETE)
		tf_mob_holder.mob_belly_transfer(src)
	if(tf_mob_holder)
		set_tf_mob_holder(null)
	own_clear(src, nameof(hud_list), OWN_DELETE)
	// Deleting a part detaches it, and the detach hook empties these caches
	// (code/modules/body/parts/attach.dm). Copies: they shrink as we go.
	for(var/OR in organs?.Copy())
		if(isdatum(OR))
			ended_with(OR, src)
	for(var/OR in internal_organ_list())
		if(isdatum(OR))
			ended_with(OR, src)

	GLOB.cultnet.updateVisibility(src, 0)
	..()

//mob verbs are faster than object verbs. See mob/verb/examine.
/mob/living/verb/pulled(atom/movable/AM as mob|obj in oview(1))
	set name = "Pull"
	set category = VERB_CAT_OBJECT

	if(istype(AM) && AM.Adjacent(src))
		src.start_pulling(AM)

	return

//mob verbs are faster than object verbs. See above.
/mob/living/pointed(atom/A as mob|obj|turf in view(client.view, src))
	if(src.stat || src.restrained())
		return FALSE
	if(src.status_flags & FAKEDEATH)
		return FALSE
	return ..()

/mob/living/_pointed(atom/pointing_at)
	if(!..())
		return FALSE

	act_message(src, pointing_at, MSG_SELF(span_info("You point at %T%.")), MSG_OTHERS(span_info(span_bold("%U%") + " points at %T%.")))

/mob/living/verb/succumb()
	set name = "Succumb to death"
	set category = VERB_CAT_IC_GAME
	set desc = "Press this button if you are in crit and wish to die. Use this sparingly (ending a scene, no medical, etc.)"
	open_request(src, /datum/prompt/choice/succumb, PROC_REF(succumb_ask_again), answerer = src, choices = list("No", "Yes"), title = "Confirm wish to succumb", question = "Pressing this button will kill you instantenously! Are you sure you wish to proceed?")

/// One of the two succumb confirmations. A no or a cancel keeps the mob alive.
/datum/prompt/choice/succumb
	timeout = 0
	buttons = TRUE

/mob/living/proc/succumb_ask_again(datum/act/request/A)
	var/datum/prompt/choice/succumb/ask = A.request
	if(!A.answer || ask.value != "Yes")
		if(A.answer || (ask.outcome == REQ_CANCELLED && isnull(ask.value)))
			to_chat(src, span_blue("You chose to live another day."))
		return
	//Swapped answers to protect from accidental double clicks.
	open_request(src, /datum/prompt/choice/succumb, PROC_REF(succumb_answered), answerer = src, choices = list("Yes", "No"), title = "Are you sure?", question = "Pressing this buttom will really kill you, no going back")

/mob/living/proc/succumb_answered(datum/act/request/A)
	var/datum/prompt/choice/succumb/ask = A.request
	if(!A.answer || ask.value != "Yes")
		if(A.answer || (ask.outcome == REQ_CANCELLED && isnull(ask.value)))
			to_chat(src, span_blue("You chose to live another day."))
		return
	if (is_critical() && stat != DEAD)
		src.death()
		to_chat(src, span_blue("You have given up life and succumbed to death."))
	else
		if(stat == DEAD)
			to_chat(src, span_blue("As much as you'd like, you can't die when already dead"))
		else
			to_chat(src, span_blue("You are not injured enough to succumb to death!"))

/mob/living/verb/toggle_afk()
	set name = "Toggle AFK"
	set category = VERB_CAT_IC_GAME
	set desc = "Mark yourself as Away From Keyboard, or clear that status!"
	if(away_from_keyboard)
		remove_status_indicator("afk")
		to_chat(src, span_notice("You are no longer marked as AFK."))
		away_from_keyboard = FALSE
		manual_afk = FALSE
	else
		add_status_indicator("afk")
		to_chat(src, span_notice("You are now marked as AFK."))
		away_from_keyboard = TRUE
		manual_afk = TRUE

//This proc is used for mobs which are affected by pressure to calculate the amount of pressure that actually
//affects them once clothing is factored in. ~Errorage
/mob/living/proc/calculate_affecting_pressure(pressure)
	return

//sort of a legacy burn method for /electrocute, /shock, and the e_chair
/mob/living/proc/burn_skin(burn_amount)
	if(ishuman(src))
		if(src.has_mutation(mShock)) //shockproof
			return 0
		if (src.has_mutation(COLD_RESISTANCE)) //fireproof
			return 0
		// Electrical burns spread across the whole body.
		if(injure(INJURY_ELECTRIC, burn_amount))
			UpdateDamageIcon()
		return 1
	else if(isAI(src))
		return 0

/mob/living/proc/adjustBodyTemp(actual, desired, incrementboost)
	var/temperature = actual
	var/difference = abs(actual-desired)	//get difference
	var/increments = difference/10 //find how many increments apart they are
	var/change = increments*incrementboost	// Get the amount to change by (x per increment)

	// Too cold
	if(actual < desired)
		temperature += change
		if(actual > desired)
			temperature = desired
	// Too hot
	if(actual > desired)
		temperature -= change
		if(actual < desired)
			temperature = desired
	return temperature

// ++++ROCKDTBEN++++ MOB PROCS //END

/mob/proc/get_contents()

//Recursive function to find everything a mob is holding.
/mob/living/get_contents(obj/item/storage/Storage = null)
	var/list/L = list()

	if(Storage) //If it called itself
		L += Storage.return_inv()

		//Leave this commented out, it will cause storage items to exponentially add duplicate to the list
		//for(var/obj/item/storage/S in Storage.return_inv()) //Check for storage items
		//	L += get_contents(S)

		for(var/obj/item/gift/G in Storage.return_inv()) //Check for gift-wrapped items
			L += G.gift
			if(istype(G.gift, /obj/item/storage))
				L += get_contents(G.gift)

		for(var/obj/item/smallDelivery/D in Storage.return_inv()) //Check for package wrapped items
			L += D.wrapped
			if(istype(D.wrapped, /obj/item/storage)) //this should never happen
				L += get_contents(D.wrapped)
		return L

	else

		L += src.contents
		for(var/obj/item/storage/S in contents_of(src))	//Check for storage items
			L += get_contents(S)

		for(var/obj/item/gift/G in contents_of(src)) //Check for gift-wrapped items
			L += G.gift
			if(istype(G.gift, /obj/item/storage))
				L += get_contents(G.gift)

		for(var/obj/item/smallDelivery/D in contents_of(src)) //Check for package wrapped items
			L += D.wrapped
			if(istype(D.wrapped, /obj/item/storage)) //this should never happen
				L += get_contents(D.wrapped)

		for(var/obj/item/rig/R in contents_of(src))	//Check rigsuit storage for items
			if(R.rig_storage)
				L += get_contents(R.rig_storage)

		return L

/mob/living/proc/check_contents_for(A)
	var/list/L = src.get_contents()

	for(var/obj/B in L)
		if(B.type == A)
			return 1
	return 0

/// Revives a body using the client's preferences if human
/mob/living/proc/revive()
	revival_healing_action()

/// Performs the actual healing of Aheal, seperate from revive() because it does not use client prefs. Will not heal everything, and expects to be called through revive() or with a bodyrecord doing a respawn/revive.
/mob/living/proc/revival_healing_action()
	rejuvenate()
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		buckled.unbuckle_mob()
	if(iscarbon(src))
		var/mob/living/carbon/C = src

		C.drop_from_inventory(C.get_equipped_item(SLOT_ID_HANDCUFFED))
		C.drop_from_inventory(C.get_equipped_item(SLOT_ID_LEGCUFFED))
	flag_hud_update(HEALTH_HUD)
	flag_hud_update(STATUS_HUD)
	flag_hud_update(LIFE_HUD)
	if(ai_brain) // AI gets told to sleep when killed. Since they're not dead anymore, wake it up.
		ai_brain.go_wake()

	PUBLISH_LEGACY(src, /datum/notice/human_dna_finalized)
	PUBLISH_LEGACY(src, /datum/notice/living_aheal)

/mob/living/proc/rejuvenate()
	if(reagents)
		reagents.clear_reagents()

	// shut down various types of badness
	fully_heal()
	status_set(STAT_PARALYZED, 0)
	status_set(STAT_STUNNED, 0)
	status_set(STAT_WEAKENED, 0)

	// undo various death related conveniences
	sight = initial(sight)
	see_in_dark = initial(see_in_dark)
	see_invisible = initial(see_invisible)

	// shut down ongoing problems
	rejuvenate_physiology()
	set_sdisabilities(0)
	disabilities = 0
	set_resting(FALSE)

	for(var/datum/affliction/contagion/D as anything in get_contagions())
		D.cure(FALSE)

	// fix blindness and deafness
	set_blinded(0)
	status_set(STAT_BLINDED, 0)
	status_set(STAT_BLURRY, 0)
	status_set(STAT_DEAFENED, 0)
	set_ear_damage(0)

	// fix all of our organs
	restore_all_organs()

	// Everything is healed: a dead mob comes back through the one revive path; a living one wakes.
	if(stat == DEAD)
		return_from_death("rejuvenated", src, REVIVE_IGNORE_WINDOW)
	else
		set_stat(CONSCIOUS)

	// make the icons look correct
	regenerate_icons()

	flag_hud_update(HEALTH_HUD)
	flag_hud_update(STATUS_HUD)
	flag_hud_update(LIFE_HUD)

	failed_last_breath = 0 //So mobs that died of oxyloss don't revive and have perpetual out of breath.
	reload_fullscreen()

	return

/// Biological state a rejuvenate resets. Body plans without that biology (borgs) override it.
/mob/living/proc/rejuvenate_physiology()
	clear_radiation()
	set_nutrition(400)
	set_bodytemperature(T20C)

/mob/living/proc/UpdateDamageIcon()
	return

/mob/living/verb/Examine_OOC()
	set name = "Examine Meta-Info (OOC)"
	set category = VERB_CAT_OOC_GAME
	set src in view()
	do_examine_ooc(usr)

/mob/living/proc/do_examine_ooc(mob/user)
	//Makes it so SSD people have prefs with fallback to original style.
	if(CONFIG_GET(flag/allow_metadata))
		if(identity().ooc_notes)
			ooc_notes_window(user)
//			to_chat(user, span_filter_notice("[src]'s Metainfo:<br>[ooc_notes]"))
		else if(client)
			to_chat(user, span_filter_notice("[src]'s Metainfo:<br>[client.prefs.read_preference(/datum/preference/text/living/ooc_notes)]"))
		else
			to_chat(user, span_filter_notice("[src] does not have any stored infomation!"))
	else
		to_chat(user, span_filter_notice("OOC Metadata is not supported by this server!"))

	return

/mob/living/verb/resist()
	set name = "Resist"
	set category = VERB_CAT_IC_GAME

	if(!incapacitated(INCAPACITATION_KNOCKOUT) && !is_paralyzed() && (COOLDOWN_FINISHED(src, resist_cooldown)))
		COOLDOWN_START(src, resist_cooldown, RESIST_COOLDOWN)
		resist_grab()
		if(!has_status(STAT_WEAKENED))
			process_resist()
		else if(absorbed && isbelly(loc))			// Allow absorbed resistance
			var/obj/belly/B = loc
			B.relay_absorbed_resist(src)

/mob/living/proc/process_resist()

	if(istype(src.loc, /mob/living/silicon/robot/platform))
		var/mob/living/silicon/robot/platform/R = src.loc
		R.drop_stored_atom(src, src)
		return TRUE

	//unbuckling yourself
	if(src?.buckled_to())
		resist_buckle()
		return TRUE

	if(isobj(loc))
		var/obj/C = loc
		C.container_resist(src)
		return TRUE

	else if(canmove)
		if(on_fire)
			resist_fire() //stop, drop, and roll
		else
			resist_restraints()

/mob/living/proc/resist_buckle()
	var/obj/buckled = src?.buckled_to()
	if(buckled)
		if(istype(buckled, /obj/vehicle))
			var/obj/vehicle/vehicle = buckled
			vehicle.unload()
		else
			buckled.user_unbuckle_mob(src, src)

/mob/living/proc/resist_grab()
	var/resisting = 0
	for(var/obj/item/grab/G in src?.grabbed_by_list())
		resisting++
		G.handle_resist()
	if(resisting)
		act_message(src, null, others = span_danger("%U% resists!"))

/mob/living/proc/resist_fire()
	return

/mob/living/proc/resist_restraints()
	return

/mob/living/verb/lay_down()
	set name = "Rest"
	set category = VERB_CAT_IC_GAME

	set_resting(!resting)
	to_chat(src, span_notice("You are now [resting ? "resting" : "getting up"]."))
	update_canmove()

//called when the mob receives a bright flash
/mob/living/flash_eyes(intensity = FLASH_PROTECTION_MODERATE, override_blindness_check = FALSE, affect_silicon = FALSE, visual = FALSE, type = /atom/movable/screen/fullscreen/flash)
	if(override_blindness_check || !(disabilities & BLIND))
		overlay_fullscreen("flash", type)
		after(src, 2.5 SECONDS, TYPE_PROC_REF(/mob, clear_fullscreen), with = list("flash", 2.5 SECONDS))
		return 1

/mob/living/proc/cannot_use_vents()
	if(mob_size > MOB_SMALL)
		return "You can't fit into that vent."
	return null

/mob/living/proc/has_brain()
	return 1

/// Is this mob brain dead (needs a resleeve)? See /mob/living/carbon/human/is_brain_dead().
/mob/living/proc/is_brain_dead()
	return FALSE

/mob/living/proc/has_eyes()
	return 1

/mob/living/proc/has_lungs()
	return TRUE

/mob/living/proc/get_restraining_bolt()
	var/obj/item/implant/restrainingbolt/RB = locate_within(src, /obj/item/implant/restrainingbolt)
	if(RB)
		if(!RB.malfunction)
			return TRUE

	return FALSE

/mob/living/proc/slip(slipped_on,stun_duration=8)
	return 0

/mob/living/carbon/drop_from_inventory(obj/item/W, atom/target = null)
	return !has_internal_organ(W) && ..()

/mob/living/proc/drop_both_hands()
	if(get_equipped_item(SLOT_ID_HAND_L))
		unEquip(get_equipped_item(SLOT_ID_HAND_L))
	if(get_equipped_item(SLOT_ID_HAND_R))
		unEquip(get_equipped_item(SLOT_ID_HAND_R))
	return

/mob/living/touch_map_edge()

	//check for nuke disks
	if(client && stat != DEAD) //if they are clientless and dead don't bother, the parent will treat them as any other container
		if(SSticker && istype(SSticker.mode, /datum/game_mode/nuclear)) //only really care if the game mode is nuclear
			var/datum/game_mode/nuclear/G = SSticker.mode
			if(G.check_mob(src))
				if(x <= TRANSITIONEDGE)
					inertia_dir = 4
				else if(x >= world.maxx -TRANSITIONEDGE)
					inertia_dir = 8
				else if(y <= TRANSITIONEDGE)
					inertia_dir = 1
				else if(y >= world.maxy -TRANSITIONEDGE)
					inertia_dir = 2
				to_chat(src, span_warning("Something you are carrying is preventing you from leaving."))
				return

	..()

//damage/heal the mob ears and adjust the deaf amount
/mob/living/adjustEarDamage(damage, deaf)
	set_ear_damage(max(0, ear_damage + damage))
	if(deaf)
		status_adjust(STAT_DEAFENED, deaf)

//pass a negative argument to skip one of the variable
/mob/living/setEarDamage(damage, deaf)
	if(damage >= 0)
		set_ear_damage(damage)
	if(deaf >= 0)
		status_set(STAT_DEAFENED, deaf)

/mob/living/proc/vomit(lost_nutrition = 10, blood = FALSE, stun = 5, distance = 1, message = TRUE, toxic = VOMIT_TOXIC, purge = FALSE)
	if(!lastpuke)
		lastpuke = TRUE
		to_chat(src, span_warning("You feel nauseous..."))
		after(src, 15 SECONDS, TYPE_PROC_REF(/datum, om_chat), with = list(span_warning("You feel like you're about to throw up!")))
		after(src, 25 SECONDS, PROC_REF(do_vomit), with = list(lost_nutrition, blood, stun, distance, message, toxic, purge))

/// after() target: able to vomit again.
/mob/living/proc/puke_recovered()
	lastpuke = FALSE

/mob/living/proc/do_vomit(lost_nutrition = 10, blood = FALSE, stun = 5, distance = 1, message = TRUE, toxic = VOMIT_TOXIC, purge = FALSE)

	if(!check_has_mouth())
		return TRUE

	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		var/antiemetic = H.factor(BF_ANTIEMETIC)
		if(antiemetic)
			if(prob(min(90, antiemetic * 15)))
				after(src, rand(30 SECONDS, 2 MINUTES), PROC_REF(puke_recovered))
			return FALSE

	if(nutrition < 100 && !blood)
		if(message)
			act_message(src, null, MSG_SELF(span_userdanger("You try to throw up, but there's nothing in your stomach!")), \
				MSG_OTHERS(span_warning("%U% dry heaves!")))

		if(stun)
			status_at_least(STAT_STUNNED, stun)
		return TRUE

	var/obj/vomit_goal = get_active_hand()

	if(!istype(vomit_goal, /obj/item/reagent_containers/glass/bucket))
		vomit_goal = check_vomit_goal()

	if(iscarbon(src) && is_mouth_covered())
		if(message)
			act_message(src, null, MSG_SELF(span_userdanger("You throw up all over yourself!")), MSG_OTHERS(span_danger("%U% throws up all over themself!")))
		distance = 0
	else if(vomit_goal)
		if(message)
			act_message(src, vomit_goal, MSG_SELF(span_userdanger("You throw up into %T%!")), MSG_OTHERS(span_danger("%U% throws up into %T%!")))
		if(istype(vomit_goal, /obj/item/reagent_containers/glass/bucket))
			var/obj/item/organ/internal/stomach/S = LAZYACCESS(organs_by_name, O_STOMACH)
			var/obj/item/reagent_containers/glass/bucket/puke_bucket = vomit_goal
			if(S && S.acidtype)
				puke_bucket.reagents.add_reagent(S.acidtype, rand(3, 6))
			else if(blood)
				puke_bucket.reagents.add_reagent(REAGENT_BLOOD, rand(3, 6))
			else
				puke_bucket.reagents.add_reagent(REAGENT_ID_TOXIN, rand(3, 6))
		distance = 0
	else if(isbelly(loc))
		var/obj/belly/belly = loc
		if(message)
			to_chat(src, span_bolddanger("You throw up inside [belly.owner]'s [belly]!"))
		distance = 0
	else
		if(message)
			act_message(src, null, MSG_SELF(span_userdanger("You throw up!")), MSG_OTHERS(span_danger("%U% throws up!")))

	// Hurt liver means throwing up blood
	if(!blood && ishuman(src))
		var/mob/living/carbon/human/H = src
		if(!HAS_SYNTHETIC_BIOLOGY(H))
			var/obj/item/organ/internal/liver/L = H.organ_in(O_LIVER)
			if(!L || L.is_broken())
				blood = TRUE

	if(stun)
		status_at_least(STAT_STUNNED, stun)

	// Vomiting while unconscious: the patient aspirates it.
	if(ishuman(src) && stat != CONSCIOUS && !HAS_SYNTHETIC_BIOLOGY(src))
		body?.afflict(/datum/affliction/airway_obstruction)

	play_sfx(get_turf(src), SFX_EFFECTS_SPLAT)
	var/turf/T = get_turf(src)
	var/vomit_type = NONE
	var/mob/living/carbon/human/H = src

	if(HAS_SYNTHETIC_BIOLOGY(src))
		vomit_type = VOMIT_NANITE
	else if(ishuman(src) && H.ingested.has_reagent(REAGENT_ID_PHORON) && !HAS_SYNTHETIC_BIOLOGY(src))
		vomit_type = VOMIT_PURPLE
	else if(injury_load(INJURY_CATEGORY_TOXIC) && !HAS_SYNTHETIC_BIOLOGY(src))
		vomit_type = VOMIT_TOXIC

	if(!blood)
		adjust_nutrition(-lost_nutrition)
		mend(TREAT_ANTITOXIN, 3) // Purging the stomach clears some of the poison.

	if(distance)
		for(var/i=0 to distance)
			if(blood)
				if(T)
					blood_splatter(T, src, large = TRUE)
				if(stun)
					injure(INJURY_BLUNT, 2, BP_TORSO) // Retching blood tears at the gut.
			else if(T)
				T.add_vomit_floor(src, vomit_type, purge)
			T = get_step(T, dir)

	after(src, 10 SECONDS, PROC_REF(puke_recovered))

	return TRUE

/mob/living/proc/check_vomit_goal()
	PRIVATE_PROC(TRUE)
	var/obj_list = list(/obj/machinery/disposal,/obj/structure/toilet,/obj/structure/sink,/obj/structure/urinal)
	for(var/type in obj_list)
		// check standing on
		var/turf/T = get_turf(src)
		var/obj/O = locate_on(T, type)
		if(O)
			return O
		// check ahead of us
		T = get_turf(get_step(T,dir))
		O = locate_on(T, type)
		if(O && O.Adjacent(src))
			return O
	return null

/mob/living/update_canmove()
	if(!resting && cannot_stand() && can_stand_overridden())
		lying = FALSE
		canmove = TRUE
	else
		var/obj/buckled = src?.buckled_to()
		if(istype(buckled, /obj/vehicle))
			var/obj/vehicle/V = buckled
			if(is_physically_disabled())
				lying = FALSE
				canmove = TRUE
				if(!V.riding_datum) // If it has a riding datum, the datum handles moving the pixel_ vars.
					pixel_y = V.mob_offset_y - 5
			else
				if(buckled.buckle_lying != -1)
					lying = buckled.buckle_lying
				canmove = TRUE
				if(!V.riding_datum) // If it has a riding datum, the datum handles moving the pixel_ vars.
					pixel_y = V.mob_offset_y
		else if(buckled)
			set_anchored(TRUE)
			canmove = TRUE //The line above already makes the chair not swooce away if the sitter presses a button. No need to incapacitate them as a criminally large amount of mechanics read this var as a type of stun.
			if(istype(buckled))
				if(buckled.buckle_lying != -1)
					lying = buckled.buckle_lying
					canmove = buckled.buckle_movable
				if(buckled.buckle_movable)
					set_anchored(FALSE)
					canmove = TRUE
		else
			lying = incapacitated(INCAPACITATION_KNOCKDOWN)
			// Prone is not immobile. Voluntary rest and conscious knockdown use
			// movement_delay()'s crawl penalties; knockout, stun, paralysis, and
			// aggressive grabs are rejected below.
			canmove = TRUE

	if(incapacitated(INCAPACITATION_KNOCKOUT) || incapacitated(INCAPACITATION_STUNNED)) // Making sure we're in good condition to crawl
		canmove = FALSE

	if(is_paralyzed())
		lying = TRUE
		canmove = FALSE

	if(lying)
		set_density(FALSE)
		update_water() // Submerges the mob.
		stop_pulling()

		if(!passtable_crawl_checked)
			passtable_crawl_checked = TRUE
			if(pass_flags & PASSTABLE)
				passtable_reset = FALSE
			else
				passtable_reset = TRUE
				pass_flags |= PASSTABLE

	else
		set_density(initial(density))
		if(passtable_reset)
			passtable_reset = FALSE
			pass_flags &= ~PASSTABLE
		passtable_crawl_checked = FALSE

	for(var/obj/item/grab/G in src?.grabbed_by_list())
		if(G.state >= GRAB_AGGRESSIVE)
			canmove = 0
			break

	if(lying != lying_prev)
		lying_prev = lying
		update_transform()
		update_mob_action_buttons()
		if(lying && LAZYLEN(src?.buckled_mob_list()))
			for(var/mob/living/L as anything in src?.buckled_mob_list())
				if(src?.buckled_mob_list()[L] != "riding")
					continue // Only boot off riders
				if(riding_datum)
					riding_datum.force_dismount(L)
				else
					unbuckle_mob(L)
				L.status_at_least(STAT_STUNNED, 5)

	return canmove

// Mob holders in these slots will be spilled if the mob goes prone.
/mob/living/proc/get_mob_riding_slots()
	return list(get_equipped_item(SLOT_ID_BACK))

// Adds overlays for specific modifiers.
// You'll have to add your own implementation for non-humans currently, just override this proc.
/mob/living/proc/update_modifier_visuals()
	return

/mob/living/proc/update_water() // Involves overlays for humans.  Maybe we'll get submerged sprites for borgs in the future?
	return

/mob/living/proc/can_feel_pain(check_organ)
	if(HAS_SYNTHETIC_BIOLOGY(src))
		return FALSE
	return TRUE

// Called by job_controller.
/mob/living/proc/equip_post_job()
	return

// Used to check if something is capable of thought, in the traditional sense.
/mob/living/proc/is_sentient()
	return TRUE

/mob/living/get_icon_scale_x()
	return ..() * factor(BF_ICON_SCALE_X)

/mob/living/get_icon_scale_y()
	return ..() * factor(BF_ICON_SCALE_Y)

/mob/living/update_transform(instant = FALSE)
	// First, get the correct size.
	var/desired_scale_x = size_multiplier * icon_scale_x
	var/desired_scale_y = size_multiplier * icon_scale_y
	var/cent_offset = center_offset

	// Now for the regular stuff.
	if(fuzzy || offset_override || dir == EAST || dir == WEST)
		cent_offset = 0
	var/matrix/M = matrix()
	M.Scale(desired_scale_x, desired_scale_y)
	M.Translate(cent_offset * desired_scale_x, (vis_height/2)*(desired_scale_y-1))
	src.transform = M
	handle_status_indicators()

// This handles setting the client's color variable, which makes everything look a specific color.
// This proc is here so it can be called without needing to check if the client exists, or if the client relogs.
/mob/living/update_client_color()
	if(!client)
		return

	var/list/colors_to_blend = list()
	for(var/effect_color in body_effect_client_colors())
		if(islist(effect_color)) //It's a color matrix! Forget it. Just use that one.
			animate(client, color = effect_color, time = 10)
			return
		colors_to_blend += effect_color

	if(!colors_to_blend.len) // Modifiers take priority over passive area blending, to prevent changes on every area entered
		var/location_grade = get_location_color_tint() // Area or weather!
		if(location_grade)
			colors_to_blend += location_grade

	if(colors_to_blend.len)
		var/final_color
		if(colors_to_blend.len == 1) // If it's just one color we can skip all of this work.
			final_color = colors_to_blend[1]

		else // Otherwise we need to do some messy additive blending.
			var/R = 0
			var/G = 0
			var/B = 0

			for(var/C in colors_to_blend)
				var/RGB = hex2rgb(C)
				R = between(0, R + RGB[1], 255)
				G = between(0, G + RGB[2], 255)
				B = between(0, B + RGB[3], 255)
			final_color = rgb(R,G,B)

		if(final_color)
			var/old_color = client.color // Don't know if BYOND has an internal optimization to not care about animate() calls that effectively do nothing.
			if(final_color != old_color) // Gonna do a check just incase.
				animate(client, color = final_color, time = 10)

	else // No colors, so remove the client's color.
		animate(client, color = null, time = 10)

/mob/living/swap_hand()
	changed(src, CHANGE_MOB_HANDS)
	src.hand = !( src.hand )
	op_keep_poke(src, OP_KEEP_HAND)
	if(hud_used?.l_hand_hud_object && hud_used.r_hand_hud_object)
		if(hand)	//This being 1 means the left hand is in use
			hud_used.l_hand_hud_object.icon_state = "l_hand_active"
			hud_used.r_hand_hud_object.icon_state = "r_hand_inactive"
		else
			hud_used.l_hand_hud_object.icon_state = "l_hand_inactive"
			hud_used.r_hand_hud_object.icon_state = "r_hand_active"

	// We just swapped hands, so the thing in our inactive hand will notice it's not the focus
	var/obj/item/I = get_inactive_hand()
	if(I)
		I.in_inactive_hand(src)	//This'll do specific things, determined by the item
	return

/mob/living/proc/activate_hand(selhand) //0 or "r" or "right" for right hand; 1 or "l" or "left" for left hand.

	if(istext(selhand))
		selhand = lowertext(selhand)

		if(selhand == "right" || selhand == "r")
			selhand = 0
		if(selhand == "left" || selhand == "l")
			selhand = 1

	if(selhand != src.hand)
		swap_hand()

/mob/living/throw_item(atom/target, stance = I_HURT)
	if(incapacitated() || !target || istype(target, /atom/movable/screen) || is_incorporeal())
		return FALSE

	var/atom/movable/item = src.get_active_hand()

	if(!item || istype(item, /obj/item/tk_grab))
		return FALSE

	var/throw_range = item.throw_range
	if (istype(item, /obj/item/grab))
		var/obj/item/grab/G = item
		item = G.throw_held() //throw the person instead of the grab
		if(ismob(item))
			var/mob/M = item

			//limit throw range by relative mob size
			throw_range = round(M.throw_range * min(src.mob_size/M.mob_size, 1))

			var/turf/end_T = get_turf(target)
			if(end_T)
				add_attack_logs(src,M,"Thrown via grab to [end_T.x],[end_T.y],[end_T.z]")
			if(ishuman(M))
				var/mob/living/carbon/human/N = M
				if(N.is_critical() || N.stat == DEAD)
					N.injure(INJURY_BLUNT, rand(10,30), null, src)
			src.drop_from_inventory(G)

			act_message(src, item, others = span_warning("%U% has thrown %T%."))

			if((isspace(src.loc)) || (src.lastarea?.get_gravity() == 0))
				src.inertia_dir = get_dir(target, src)
				step(src, inertia_dir)
			item.throw_at(target, throw_range, item.throw_speed, src)
			return TRUE
		else
			return FALSE

	if(!item)
		return FALSE //Grab processing has a chance of returning null

	// Help stance + Adjacent = pass item to other (the catcher out of combat mode takes it)
	if(stance == I_HELP && Adjacent(target) && isitem(item) && ishuman(target) && target != src)
		var/obj/item/I = item
		var/mob/living/carbon/human/H = target
		if(H.in_throw_mode && !H.combat_mode && unEquip(I))
			H.put_in_hands(I) // If this fails it will just end up on the floor, but that's fitting for things like dionaea.
			visible_message(span_filter_notice(span_bold("[src]") + " hands \the [H] \a [I]."), span_notice("You give \the [target] \a [I]."))
		else
			to_chat(src, span_notice("You offer \the [I] to \the [target]."))
			do_give(H)
		return TRUE

	drop_from_inventory(item)

	if(!item || QDELETED(item))
		return TRUE //It may not have thrown, but it sure as hell left your hand successfully.

	//actually throw it!
	act_message(src, item, others = span_warning("%U% has thrown %T%."))

	if((isspace(src.loc)) || (src.lastarea?.get_gravity() == 0))
		src.inertia_dir = get_dir(target, src)
		step(src, inertia_dir)

	if(istype(item,/obj/item))
		var/obj/item/W = item
		W.randpixel_xy()

/*
	if(istype(src.loc, /turf/space) || (src.flags & NOGRAV)) //they're in space, move em one space in the opposite direction
		src.inertia_dir = get_dir(target, src)
		step(src, inertia_dir)
*/

	item.throw_at(target, throw_range, item.throw_speed, src)
	return TRUE

/mob/living/get_sound_env(spot, pressure_factor)
	if (has_status(STAT_HALLUCINATING))
		return SOUND_ENVIRONMENT_PSYCHOTIC
	else if (has_status(STAT_DRUGGED))
		return SOUND_ENVIRONMENT_DRUGGED
	else if (has_status(STAT_DROWSY))
		return SOUND_ENVIRONMENT_DIZZY
	else if (has_status(STAT_CONFUSED))
		return SOUND_ENVIRONMENT_DIZZY
	else if (has_status(STAT_SLEEPING))
		return SOUND_ENVIRONMENT_UNDERWATER
	else
		return ..()

//Add an entry to overlays, assuming it exists
/mob/living/proc/apply_hud(cache_index, image/I)
	if(I)
		rel_add(src, nameof(hud_list), I, cache_index) // the mob owns its HUD images; a replaced one is deleted
	if((. = hud_list[cache_index]))
		add_overlay(.)

//Remove an entry from overlays for editing; it stays owned in its slot until apply_hud() re-adds it
/mob/living/proc/grab_hud(cache_index)
	var/I = hud_list[cache_index]
	if(I)
		cut_overlay(I)
		return I

/mob/living/proc/make_hud_overlays()
	return

/mob/living/proc/has_vision()
	return !(has_status(STAT_BLINDED) || (disabilities & BLIND) || stat || blinded)

/mob/living/proc/dirties_floor()	// If we ever decide to add fancy conditionals for making dirty floors (floating, etc), here's the proc.
	return makes_dirt

/// Affected by airborne agents (smoke, choking): a breathing, non-synthetic body (P2-S7: breathes()).
/mob/living/proc/needs_to_breathe()
	return breathes() && !HAS_SYNTHETIC_BIOLOGY(src)

/// Shift nutrition by `amount`, clamped to [0, max_nutrition]. With
/// set_nutrition(), the ONLY writers of `nutrition` (P2-S11).
/mob/living/proc/adjust_nutrition(amount)
	if(!amount || !isnum(amount))
		return 0
	return set_nutrition(nutrition + amount)

/// Set nutrition to `value`, clamped to [0, max_nutrition]: nutrition's only writer (a tracked var the HUD reads).
/// Returns the change.
/mob/living/proc/set_nutrition(value)
	if(!isnum(value))
		return 0
	value = between(0, value, max_nutrition)
	var/old = nutrition
	if(old == value)
		return 0
	nutrition = value
	tracked_changed(src, nameof(nutrition))
	return value - old
SETTER(/mob/living, nutrition)

/// Marks the HUD-list entry `index` (ID_HUD, HEALTH_HUD, ...) stale: the HUD reaction redraws it (MOB_KEY_HUD_FLAGS).
/// The only producer of hud_updateflag bits (the HUD clears them as it draws).
/mob/living/proc/flag_hud_update(index)
	var/bit = 1 << index
	if(hud_updateflag & bit)
		return
	hud_updateflag |= bit
	PUBLISH_CHANGE(src, MOB_KEY_HUD_FLAGS)

/mob/living/proc/nutrition_percent()
	return 100 * nutrition / max_nutrition

/mob/living/vv_get_header()
	. = ..()
	var/refid = REF(src)
	. += {"
		<br>"} + span_small("[VV_HREF_TARGETREF(refid, VV_HK_GIVE_DIRECT_CONTROL, "[ckey || "no ckey"]")] / [VV_HREF_TARGETREF_1V(refid, VV_HK_BASIC_EDIT, "[real_name || "no real name"]", NAMEOF(src, real_name))]") + {"
		<br>"} + span_small("VITALITY: <span id='vitality'>[round(vitality() * 100)]%</span> 			AFFLICTIONS: <span id='afflictions'>[LAZYLEN(body?.afflictions)]</span> 			OXYGEN DEBT: <span id='oxygen_debt'>[round(oxygen_debt(), 0.1)]</span>") + {"
		<br>"} + span_small("<a href='byond://?_src_=vars;[HrefToken()];mobToDamage=[refid];adjustBody=injure'>Injure</a> 			<a href='byond://?_src_=vars;[HrefToken()];mobToDamage=[refid];adjustBody=mend'>Mend</a> 			<a href='byond://?_src_=vars;[HrefToken()];mobToDamage=[refid];adjustBody=afflict'>Add affliction</a> 			<a href='byond://?_src_=vars;[HrefToken()];mobToDamage=[refid];adjustBody=cure'>Remove affliction</a> 			<a href='byond://?_src_=vars;[HrefToken()];mobToDamage=[refid];adjustBody=oxygen'>Oxygen debt</a>")

/// The VV body editor: injure with a chosen kind, mend with a chosen tag, add
/// or remove an affliction, or set oxygen debt. Returns the log line (what was
/// done), or null when cancelled or still asking. Runs inside vv_topic()'s
/// prompt flow: each flow_ask() answer re-runs the topic, which re-locates this
/// mob, so every check below is made again before anything changes.
/mob/living/proc/vv_adjust_body(client/C, action)
	switch(action)
		if("injure")
			var/list/kinds = list()
			for(var/kind in 1 to INJURY_KIND_COUNT)
				kinds[injury_kind_name(kind)] = kind
			var/choice = flow_ask(C.mob, "body_injure_kind", /datum/om/prompt/choice, message = "Injury kind", title = "Injure [src]", choices = kinds)
			if(!choice || QDELETED(src))
				return null
			var/amount = flow_ask(C.mob, "body_injure_amount", /datum/om/prompt/number, message = "How much [choice]?", title = "Injure [src]", default = 10, min = 0, round_entry = FALSE)
			if(!amount || QDELETED(src))
				return null
			var/static/list/zones = list("whole body") + BP_ALL
			var/zone = flow_ask(C.mob, "body_injure_zone", /datum/om/prompt/choice, message = "Where? (systemic kinds ignore this)", title = "Injure [src]", choices = zones, default = "whole body")
			if(!zone || QDELETED(src))
				return null
			var/dealt = injure(kinds[choice], amount, zone == "whole body" ? null : zone, flags = INJURE_IGNORE_RESISTANCE)
			return "injured ([choice], [amount] requested, [round(dealt, 0.1)] dealt[zone == "whole body" ? "" : " at [zone]"])"
		if("mend")
			var/list/names = GLOB.dq_treatment_tag_names
			var/list/tags = list()
			for(var/tag in names)
				tags[names[tag]] = tag
			var/choice = flow_ask(C.mob, "body_mend_tag", /datum/om/prompt/choice, message = "Treatment tag", title = "Mend [src]", choices = tags)
			if(!choice || QDELETED(src))
				return null
			var/amount = flow_ask(C.mob, "body_mend_amount", /datum/om/prompt/number, message = "How much [choice]?", title = "Mend [src]", default = 10, min = 0, round_entry = FALSE)
			if(!amount || QDELETED(src))
				return null
			var/treated = mend(tags[choice], amount)
			return "mended ([choice], [amount] requested, [round(treated, 0.1)] treated)"
		if("afflict")
			var/list/affliction_types = list()
			for(var/path in subtypesof(/datum/affliction))
				affliction_types["[path]"] = path
			var/affliction_name = flow_ask(C.mob, "body_afflict_type", /datum/om/prompt/choice, message = "Affliction", title = "Afflict [src]", choices = affliction_types)
			var/affliction_type = affliction_types[affliction_name]
			if(!affliction_type || QDELETED(src) || !body)
				return null
			var/severity = flow_ask(C.mob, "body_afflict_severity", /datum/om/prompt/number, message = "Severity (0-[AFFLICTION_SEVERITY_TERMINAL])", title = "Afflict [src]", default = 30, max = AFFLICTION_SEVERITY_TERMINAL, min = 0, round_entry = FALSE)
			if(isnull(severity) || QDELETED(src) || !body)
				return null
			var/datum/affliction/A = body.afflict(affliction_type, null, severity)
			if(!A)
				to_chat(C, span_warning("[affliction_type] can't afflict [src] (wrong body plan or biology, or it needs a location)."), confidential = TRUE)
				return null
			return "added affliction [affliction_type] (severity [round(A.severity, 0.1)])"
		if("cure")
			var/list/choices = list()
			for(var/datum/affliction/A as anything in body.afflictions)
				choices["[A.name][A.location ? " ([A.location.name])" : ""] - severity [round(A.severity, 0.1)] [REF(A)]"] = A
			if(!length(choices))
				to_chat(C, span_notice("[src] has no afflictions."), confidential = TRUE)
				return null
			var/choice = flow_ask(C.mob, "body_cure", /datum/om/prompt/choice, message = "Remove which affliction?", title = "Cure [src]", choices = choices)
			var/datum/affliction/A = choices[choice]
			if(!A || QDELETED(src) || A.owner != src)
				return null
			var/removed = "[A.type]"
			A.cure()
			return "removed affliction [removed]"
		if("oxygen")
			var/amount = flow_ask(C.mob, "body_oxygen", /datum/om/prompt/number, message = "Oxygen debt to add (negative pays it down)", title = "Oxygen debt of [src]", default = 0, min = -INFINITY, round_entry = FALSE)
			if(!amount || QDELETED(src))
				return null
			if(amount > 0)
				add_oxygen_debt(amount, "admin [key_name(C)]")
			else
				mend(TREAT_OXYGENATION, -amount)
			return "changed oxygen debt by [amount]"
	return null

/mob/living/update_gravity(has_gravity)
	if(!SSticker)
		return
	if(has_gravity)
		clear_alert("weightless")
	else
		throw_alert("weightless", /atom/movable/screen/alert/weightless)

// Tries to turn off things that let you see through walls, like mesons.
// Each mob does vision a bit differently so this is just for inheritence and also so overrided procs can make the vision apply instantly if they call `..()`.
/mob/living/proc/disable_spoiler_vision()
	PUBLISH_CHANGE(src, MOB_KEY_VIEW) // the sight reaction re-reads it

/**
 * Small helper datum to manage the character setup HUD icon (was
 * /datum/component/character_setup). Owned by the mob's `character_setup_button` var.
 */
/datum/character_setup_button
	var/mob/living/owner
	var/atom/movable/screen/character_setup/screen_icon

/mob/living/var/datum/character_setup_button/character_setup_button

/datum/character_setup_button/New(mob/living/M)
	..()
	rel_set(src, nameof(owner), M)
	observe(owner, /datum/notice/mob_client_login, src, then(PROC_REF(on_client_login)))
	if(owner.client)
		create_mob_button(owner)

// owned state datum (was a component): its button leaves the owner's screen and HUD.
/datum/character_setup_button/on_destroy(force)
	if(screen_icon)
		owner?.client?.screen -= screen_icon
		var/datum/hud/button_hud = owner_of(screen_icon)
		if(istype(button_hud))
			own_remove(button_hud, nameof(button_hud.other_important), screen_icon)
	..()

/// Gives the mob its character setup HUD button if it has none.
/mob/living/proc/add_character_setup_button()
	if(!character_setup_button)
		rel_set(src, nameof(character_setup_button), new /datum/character_setup_button(src))
	return character_setup_button

/datum/character_setup_button/proc/on_client_login(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	create_mob_button(source)

/datum/character_setup_button/proc/create_mob_button(mob/user)
	var/datum/hud/HUD = user.hud_used
	// The hud owns the button (other_important); a new hud's button is made afresh
	// (the old hud deleted its own, which cleared this relation).
	if(!screen_icon)
		var/atom/movable/screen/character_setup/button = new
		rel_add(HUD, nameof(HUD.other_important), button)
		rel_set(src, nameof(screen_icon), button)
		observe(screen_icon, /datum/notice/click, src, then(PROC_REF(character_setup_click)))
	if(ispAI(user))
		screen_icon.icon = 'icons/mob/pai_hud.dmi'
		screen_icon.screen_loc = ui_acti
	else
		screen_icon.icon = HUD.ui_style
		screen_icon.color = HUD.ui_color
		screen_icon.alpha = HUD.ui_alpha
	if(isAI(user))
		screen_icon.screen_loc = ui_ai_pda_send
	user.client?.screen += screen_icon

/datum/character_setup_button/proc/character_setup_click(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/notice/click/event = A
	var/mob/clicker = event.user
	if(clicker?.client?.prefs)
		INVOKE_ASYNC(clicker.client.prefs, TYPE_PROC_REF(/datum/preferences, ShowChoices), clicker) // ALLOW(scheduler): ShowChoices opens tgui (asset/window setup)

/**
 * Screen object for vore panel
 */
/atom/movable/screen/character_setup
	name = "character setup"
	icon = 'icons/mob/screen/midnight.dmi'
	icon_state = "character"
	screen_loc = ui_smallquad

/mob/living/set_dir(new_dir)
	. = ..()
	if(size_multiplier != 1 || icon_scale_x != DEFAULT_ICON_SCALE_X && center_offset > 0)
		update_transform(TRUE)

/mob/living/proc/set_metainfo_favs(mob/user, reopen = TRUE)
	if(user != src)
		return
	ask_metainfo(src, "favs", reopen)

/mob/living/proc/set_metainfo_maybes(mob/user, reopen = TRUE)
	if(user != src)
		return
	ask_metainfo(src, "maybes", reopen)

/mob/living/proc/set_metainfo_ooc_style(mob/user, reopen = TRUE)
	if(user != src)
		return
	identity().ooc_notes_style = !identity().ooc_notes_style
	client.prefs.update_preference_by_type(/datum/preference/toggle/living/ooc_notes_style, identity().ooc_notes_style)
	if(reopen)
		ooc_notes_window(user)

/mob/living/Initialize(mapload)
	. = ..()
	life_update_relevance()
	// Brain creation is handled by the combat AI integration's
	// /mob/living/Initialize re-open (code/modules/combat_ai/integration/mob_living.dm),
	// which calls initialize_ai_brain() when the mob opts in via use_modern_ai.

	//Prime this list if we need it.
	if(has_huds)
		// Note, this should be refactored to drop priority overlays
		// ALLOW(decl): priority overlay from a global, gated on has_huds
		add_overlay(GLOB.backplane,TRUE) //Strap this on here, to block HUDs from appearing in rightclick menus: http://www.byond.com/forum/?post=2336679
		rel_clear(src, nameof(hud_list))
		hud_list = new /list(TOTAL_HUDS) // ALLOW(ownership): a fresh slot table (nulls only); its images are adopted through own_put()
		make_hud_overlays()

	//I'll just hang my coat up over here
	dsoverlay = image('icons/mob/darksight.dmi',GLOB.global_hud.darksight) //This is a secret overlay! Go look at the file, you'll see.
	var/mutable_appearance/dsma = new(dsoverlay) //Changing like ten things, might as well.
	dsma.alpha = 0
	dsma.plane = PLANE_LIGHTING
	dsma.blend_mode = BLEND_ADD
	dsoverlay.appearance = dsma

	selected_image = image(icon = GLOB.buildmode_hud, loc = src, icon_state = "ai_sel")

	rel_set(src, nameof(deaf_loop), new /datum/looping_sound/mob/deafened(list(src), FALSE)) // ALLOW(decl): looping_sound takes constructor args
	rel_set(src, nameof(firesoundloop), new /datum/looping_sound/mob/on_fire(list(src), FALSE)) // ALLOW(decl): looping_sound takes constructor args
	// stunnedloop = new(list(src), FALSE)
	if(firesoundloop) // Partly safety, partly so we can have different probs for randomization
		if(prob(40)) // Randomize our end_sound. Can't really do this easily in looping_sound without some work
			if(prob(30))
				firesoundloop.end_sound = 'sound/effects/mob_effects/on_fire/fire_extinguish2.ogg'
			else if(prob(20))
				firesoundloop.end_sound = 'sound/effects/mob_effects/on_fire/fire_extinguish3.ogg'
			else
				firesoundloop.end_sound = 'sound/effects/mob_effects/on_fire/fire_extinguish4.ogg'

/mob/living/proc/handle_vorefootstep(m_intent, turf/T) // Moved from living_ch.dm
	return FALSE

/mob/living/Check_Shoegrip()
	if(flying)
		return 1
	..()

/mob/living/verb/customsay()
	set category = VERB_CAT_IC_SETTINGS
	set name = "Customize Speech Verbs"
	set desc = "Customize the text which appears when you type- e.g. 'says', 'asks', 'exclaims'."

	if(src.client)
		open_request(src, /datum/prompt/choice, PROC_REF(custom_say_verb_chosen), answerer = src, title = "Select Verb", question = "Which say-verb do you wish to customize?", choices = list("Say", "Whisper", "Ask (?)", "Exclaim/Shout/Yell (!)", "Cancel"), buttons = TRUE, timeout = 0)

/// A custom speech verb; the selector is one of the four speech fields below.
/datum/prompt/text/custom_say
	timeout = 0
	var/say_var

/mob/living/proc/custom_say_verb_chosen(datum/act/request/A)
	if(!A.answer)
		return
	switch(A.answer.value)
		if("Say")
			open_request(src, /datum/prompt/text/custom_say, PROC_REF(custom_say_entered), answerer = src, title = "Custom Say", question = "This word or phrase will appear instead of 'says': [src] says, \"Hi.\"", say_var = "custom_say")
		if("Whisper")
			open_request(src, /datum/prompt/text/custom_say, PROC_REF(custom_say_entered), answerer = src, title = "Custom Whisper", question = "This word or phrase will appear instead of 'whispers': [src] whispers, \"Hi...\"", say_var = "custom_whisper")
		if("Ask (?)")
			open_request(src, /datum/prompt/text/custom_say, PROC_REF(custom_say_entered), answerer = src, title = "Custom Ask", question = "This word or phrase will appear instead of 'asks': [src] asks, \"Hi?\"", say_var = "custom_ask")
		if("Exclaim/Shout/Yell (!)")
			open_request(src, /datum/prompt/text/custom_say, PROC_REF(custom_say_entered), answerer = src, title = "Custom Exclaim", question = "This word or phrase will appear instead of 'exclaims', 'shouts' or 'yells': [src] exclaims, \"Hi!\"", say_var = "custom_exclaim")

/mob/living/proc/custom_say_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/text/custom_say/ask = A.request
	var/custom_verb = lowertext(ask.value)
	switch(ask.say_var)
		if("custom_say")
			custom_say = custom_verb
		if("custom_whisper")
			custom_whisper = custom_verb
		if("custom_ask")
			custom_ask = custom_verb
		if("custom_exclaim")
			custom_exclaim = custom_verb

/mob/living/verb/set_metainfo()
	set name = "Set OOC Metainfo"
	set desc = "Sets OOC notes about yourself or your RP preferences or status."
	set category = VERB_CAT_OOC_GAME_SETTINGS

	if(usr != src)
		return
	ask_metainfo(src, "notes", TRUE, list("likes", "dislikes", "favs", "maybes", "style"))

/mob/living/proc/set_metainfo_panel(mob/user)
	if(user != src)
		return
	ask_metainfo(src, "notes")

/mob/living/proc/set_metainfo_likes(mob/user, reopen = TRUE)
	if(user != src)
		return
	ask_metainfo(src, "likes", reopen)

/mob/living/proc/set_metainfo_dislikes(mob/user, reopen = TRUE)
	if(user != src)
		return
	ask_metainfo(src, "dislikes", reopen)

/// OOC note fields: field => list(identity var, preference type, what the question calls the preferences).
GLOBAL_LIST_INIT(metainfo_fields, list(
	"notes" = list("ooc_notes", /datum/preference/text/living/ooc_notes, null),
	"likes" = list("ooc_notes_likes", /datum/preference/text/living/ooc_notes_likes, "LIKED"),
	"dislikes" = list("ooc_notes_dislikes", /datum/preference/text/living/ooc_notes_dislikes, "DISLIKED"),
	"favs" = list("ooc_notes_favs", /datum/preference/text/living/ooc_notes_favs, "FAVOURITE"),
	"maybes" = list("ooc_notes_maybes", /datum/preference/text/living/ooc_notes_maybes, "MAYBE"),
))

/// An OOC note field (shared, read-only), or null for an unknown field.
/mob/living/proc/metainfo_field(field)
	return istext(field) ? GLOB.metainfo_fields[field] : null

/// Asks for one OOC note field; `chain` lists the fields asked next (and "style", which toggles the note style).
/mob/living/proc/ask_metainfo(mob/user, field, reopen = TRUE, list/chain)
	var/list/F = metainfo_field(field)
	var/message = F[3] ? "Enter any information you'd like others to see relating to your [F[3]] roleplay preferences. This will not be saved permanently unless you click save in the OOC notes panel! Type \"!clear\" to empty." : "Enter any information you'd like others to see, such as Roleplay-preferences. This will not be saved permanently unless you click save in the OOC notes panel!"
	open_request(src, /datum/prompt/text/metainfo, PROC_REF(metainfo_entered), answerer = src, question = message, default = html_decode(identity().vars[F[1]]), field = field, reopen = reopen, chain = chain)

/// One OOC note field. A cancel skips to the next field of the chain.
/datum/prompt/text/metainfo
	timeout = 0
	title = "Game Preference"
	multiline = TRUE
	var/field
	var/reopen = TRUE
	var/list/chain

/mob/living/proc/metainfo_entered(datum/act/request/A)
	var/datum/prompt/text/metainfo/ask = A.request
	if(!A.answer)
		if(ask.outcome == REQ_CANCELLED && isnull(ask.value))
			metainfo_skipped(ask)
		return
	var/field = ask.field
	var/list/F = metainfo_field(field)
	var/new_metadata = strip_html_simple(ask.value)
	if(new_metadata && CanUseTopic(src))
		if(F[3] && new_metadata == "!clear")
			new_metadata = ""
		identity().vars[F[1]] = new_metadata
		client.prefs.update_preference_by_type(F[2], new_metadata)
		to_chat(src, span_filter_notice(F[3] ? "OOC note [field] have been updated. Don't forget to save!" : "OOC notes updated. Don't forget to save!"))
		log_admin("[key_name(src)] updated their OOC [F[3] ? "note [field]" : "notes"] mid-round.")
		if(ask.reopen)
			ooc_notes_window(src)
	metainfo_skipped(ask)

/// Asks the next field of the chain, if any.
/mob/living/proc/metainfo_skipped(datum/prompt/text/metainfo/ask)
	var/list/chain = ask.chain
	if(!length(chain))
		return
	if(chain[1] == "style")
		set_metainfo_ooc_style(src, FALSE)
		return
	ask_metainfo(src, chain[1], FALSE, chain.Copy(2))

/mob/living/proc/save_ooc_panel(mob/user)
	if(user != src)
		return
	if(client.prefs.read_preference(/datum/preference/name/real_name) != real_name)
		to_chat(src, span_danger("Your selected character slot name is not the same as your character's name. Aborting save. Please select [real_name]'s character slot in character setup before saving."))
		return
	if(client.prefs.save_character())
		to_chat(src, span_filter_notice("Character preferences saved."))

/mob/living/proc/print_ooc_notes_chat(mob/user)
	if(!identity().ooc_notes)
		return
	var/msg = identity().ooc_notes
	if(identity().ooc_notes_style && (identity().ooc_notes_favs || identity().ooc_notes_likes || identity().ooc_notes_maybes || identity().ooc_notes_dislikes) && !user.client?.prefs?.read_preference(/datum/preference/toggle/vchat_enable)) // Oldchat hates proper formatting
		msg += "<br><br>"
		msg += "<table><tr>"
		if(identity().ooc_notes_favs)
			msg += "<th><b>\t[span_blue("FAVOURITES")]</b></th>"
		if(identity().ooc_notes_likes)
			msg += "<th><b>\t[span_green("LIKES")]</b></th>"
		if(identity().ooc_notes_maybes)
			msg += "<th><b>\t[span_yellow("MAYBES")]</b></th>"
		if(identity().ooc_notes_dislikes)
			msg += "<th><b>\t[span_red("DISLIKES")]</b></th>"
		msg += "</tr><tr>"
		if(identity().ooc_notes_favs)
			msg += "<td>"
			for(var/line in splittext(identity().ooc_notes_favs, "\n"))
				msg += "\t[line]\n"
			msg += "</td>"
		if(identity().ooc_notes_likes)
			msg += "<td>"
			for(var/line in splittext(identity().ooc_notes_likes, "\n"))
				msg += "\t[line]\n"
			msg += "</td>"
		if(identity().ooc_notes_maybes)
			msg += "<td>"
			for(var/line in splittext(identity().ooc_notes_maybes, "\n"))
				msg += "\t[line]\n"
			msg += "</td>"
		if(identity().ooc_notes_dislikes)
			msg += "<td>"
			for(var/line in splittext(identity().ooc_notes_dislikes, "\n"))
				msg += "\t[line]\n"
			msg += "</td>"
		msg += "</tr></table>"
	else
		if(identity().ooc_notes_favs)
			msg += "<br><br><b>[span_blue("FAVOURITES")]</b><br>[identity().ooc_notes_favs]"
		if(identity().ooc_notes_likes)
			msg += "<br><br><b>[span_green("LIKES")]</b><br>[identity().ooc_notes_likes]"
		if(identity().ooc_notes_maybes)
			msg += "<br><br><b>[span_yellow("MAYBES")]</b><br>[identity().ooc_notes_maybes]"
		if(identity().ooc_notes_dislikes)
			msg += "<br><br><b>[span_red("DISLIKES")]</b><br>[identity().ooc_notes_dislikes]"
	to_chat(user, span_chatexport("<b>[src]'s Metainfo:</b><br>[msg]"))
/mob/living/verb/set_custom_link()
	set name = "Set Custom Link"
	set desc = "Set a custom link to show up with your examine text."
	set category = VERB_CAT_IC_SETTINGS

	if(usr != src)
		return
	open_request(src, /datum/prompt/text, PROC_REF(custom_link_entered), answerer = src, title = "Custom Link", question = "Enter a link to add on to your examine text! This should be a related image link/gallery, or things like your F-list. This is not the place for memes.", default = html_decode(custom_link), max_len = 100, timeout = 0)

/mob/living/proc/custom_link_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/new_link = strip_html_simple(A.answer.value)
	if(new_link && CanUseTopic(src))
		if(length(new_link) > 100)
			to_chat(src, span_warning("Your entry is too long, it must be 100 characters or less."))
			return

		custom_link = new_link
		to_chat(src, span_notice("Link set: [custom_link]"))
		log_admin("[src]/[src.ckey] set their custom link to [custom_link]")

/mob/living/verb/set_voice_freq()
	set name = "Set Voice Frequency"
	set desc = "Sets your voice frequency to be higher or lower pitched!"
	set category = VERB_CAT_OOC_GAME_SETTINGS

	var/static/list/preset_voice_freqs = list("high" = MAX_VOICE_FREQ, "middle-high" = 56250, "middle" = 425000, "middle-low"= 28750, "low" = MIN_VOICE_FREQ, "custom" = 1, "random" = 0)
	open_request(src, /datum/prompt/choice, PROC_REF(voice_freq_preset_chosen), answerer = src, title = "Voice Frequency", question = "What would you like to set your voice frequency to?", choices = preset_voice_freqs, timeout = 0)

/mob/living/proc/voice_freq_preset_chosen(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/choice/ask = A.answer
	var/choice = ask.choices[ask.value]
	if(choice == 1)
		open_request(src, /datum/prompt/number, PROC_REF(voice_freq_entered), answerer = src, title = "Custom Voice Frequency", question = "Choose your character's voice frequency, ranging from [MIN_VOICE_FREQ] to [MAX_VOICE_FREQ]", max_value = MAX_VOICE_FREQ, min_value = MIN_VOICE_FREQ, timeout = 0)
		return
	apply_voice_freq(choice)

/mob/living/proc/voice_freq_entered(datum/act/request/A)
	if(!A.answer)
		return
	apply_voice_freq(A.answer.value)

/mob/living/proc/apply_voice_freq(choice)
	if(choice == 0)
		voice_freq = choice
		return
	voice_freq = clamp(choice, MIN_VOICE_FREQ, MAX_VOICE_FREQ)

/mob/living/verb/set_voice_type()
	set name = "Set Voice Type"
	set desc = "Sets your voice style!"
	set category = VERB_CAT_OOC_GAME_SETTINGS

	var/list/sound_choices = SSsounds.ready().talk_sound_sets()
	// The original empty list opened nothing and did not reset the voice.
	if(length(sound_choices))
		open_request(src, /datum/prompt/choice/voice_type, PROC_REF(voice_type_chosen), answerer = src, choices = sound_choices)

/// A cancel resets the voice to the default sounds.
/datum/prompt/choice/voice_type
	timeout = 0
	title = "Voice Sounds"
	question = "Which set of sounds would you like to use for your character's speech sounds?"

/mob/living/proc/voice_type_chosen(datum/act/request/A)
	if(!A.answer)
		var/datum/request/R = A.request
		if(R.outcome == REQ_CANCELLED && isnull(R.value))
			voice_sounds_list = DEFAULT_TALK_SOUNDS
		return
	voice_sounds_list = get_talk_sound(A.answer.value)

/mob/living/proc/save_private_notes(mob/user)
	if(user != src)
		return
	if(client.prefs.read_preference(/datum/preference/name/real_name) != real_name)
		to_chat(src, span_danger("Your selected character slot name is not the same as your character's name. Aborting save. Please select [real_name]'s character slot in character setup before saving."))
		return
	if(client.prefs.save_character())
		to_chat(src, span_filter_notice("Character preferences saved."))

/mob/living/verb/open_private_notes()
	set name = "Private Notes"
	set desc = "View and edit your character's private notes, that persist between rounds!"
	set category = VERB_CAT_IC_NOTES

	private_notes_window(src)

/mob/living/proc/set_metainfo_private_notes(mob/user)
	if(user != src)
		return
	open_request(src, /datum/prompt/text, PROC_REF(private_notes_entered), answerer = src, title = "Private Notes", question = "Write some notes for yourself. These can be anything that is useful, whether it's character events that you want to remember or a bit of lore. Things that you would normally stick in a txt file for yourself! This will not be saved unless you press save in the private notes panel.", default = html_decode(private_notes), multiline = TRUE, timeout = 0)

/mob/living/proc/private_notes_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_metadata = A.answer.value
	if(new_metadata && CanUseTopic(src))
		private_notes = new_metadata
		client.prefs.update_preference_by_type(/datum/preference/text/living/private_notes, new_metadata)
		to_chat(src, span_filter_notice("Private notes updated. Don't forget to save!"))
		private_notes_window(user)

/// after() target: the mob's AI picks up where it paused.
/mob/living/proc/ai_brain_resume()
	ai_busy_end()

