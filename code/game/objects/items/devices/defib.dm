#define DEFIB_TIME_LOSS  (2 MINUTES) //past this many seconds, brain damage occurs.

//backpack item
/obj/item/defib_kit
	name = "defibrillator"
	desc = "A device that delivers powerful shocks to detachable paddles that resuscitate incapacitated patients."
	icon = 'icons/obj/defibrillator.dmi'
	icon_state = "defibunit"
	item_state = "defibunit"
	slot_flags = SLOT_BACK
	force = 5
	throwforce = 6
	preserve_item = 1
	w_class = ITEMSIZE_LARGE
	unacidable = TRUE

	var/paddle_path = /obj/item/shockpaddles/linked
	var/obj/item/cell/bcell = null
	pickup_sound = 'sound/items/pickup/device.ogg'
	drop_sound = 'sound/items/drop/device.ogg'

/obj/item/defib_kit/get_cell()
	return bcell

/obj/item/defib_kit/Initialize(mapload) //starts without a cell for rnd
	make_tethered(paddle_path)
	. = ..()
	if(ispath(bcell))
		bcell = new bcell(src)
	update_icon()

REF_OWNED(/obj/item/defib_kit, "bcell")

/obj/item/defib_kit/loaded //starts with a cell
	bcell = /obj/item/cell/apc

/obj/item/defib_kit/proc/get_paddles()
	return tethered_handheld()

/obj/item/defib_kit/update_icon()
	cut_overlays()

	var/obj/item/shockpaddles/linked/paddles = get_paddles()
	if(paddles && paddles.loc == src)
		add_overlay("[initial(icon_state)]-paddles")
	if(bcell && paddles)
		if(bcell.check_charge(paddles.chargecost))
			if(paddles.combat)
				add_overlay("[initial(icon_state)]-combat")
			else if(!paddles.safety)
				add_overlay("[initial(icon_state)]-emagged")
			else
				add_overlay("[initial(icon_state)]-powered")

		var/ratio = CEILING(bcell.percent()/25, 1) * 25
		add_overlay("[initial(icon_state)]-charge[ratio]")
	else
		add_overlay("[initial(icon_state)]-nocell")

DECLARE_INTERACTIONS(/obj/item/defib_kit, \
	INTERACT_HAND(null, PROC_REF(interaction_hand)), \
	INTERACT_ITEM("Load", PROC_REF(interaction_item)), \
)

/// Old attack_hand: let the tether swap the paddles into hand before falling through to pickup.
/obj/item/defib_kit/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	// See important note in code/datums/behaviours/tethered_item.dm
	if(tether_swap(user))
		return TRUE
	return FALSE

/obj/item/defib_kit/MouseDrop()
	if(ismob(src.loc))
		if(!CanMouseDrop(src))
			return
		var/mob/M = src.loc
		if(!M.unEquip(src))
			return
		src.add_fingerprint(usr)
		M.put_in_any_hand_if_possible(src)


/obj/item/defib_kit/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W, /obj/item/cell))
		if(bcell)
			to_chat(user, span_notice("\The [src] already has a cell."))
		else
			if(!user.unEquip(W))
				return TRUE
			W.forceMove(src)
			bcell = W
			to_chat(user, span_notice("You install a cell in \the [src]."))
			update_icon()
		return TRUE
	return FALSE

/obj/item/defib_kit/screwdriver_act(mob/user, obj/item/tool)
	if(!bcell)
		return ITEM_INTERACT_BLOCKING
	bcell.update_icon()
	bcell.forceMove(get_turf(loc))
	user.put_in_any_hand_if_possible(bcell)
	bcell = null
	to_chat(user, span_notice("You remove the cell from \the [src]."))
	update_icon()
	return ITEM_INTERACT_SUCCESS

/obj/item/defib_kit/emag_act(remaining_charges, mob/user)
	var/obj/item/shockpaddles/linked/paddles = get_paddles()
	if(paddles)
		. = paddles.emag_act(user)
		update_icon()
	return

//checks that the base unit is in the correct slot to be used
/obj/item/defib_kit/proc/slot_check()
	var/mob/M = loc
	if(!istype(M))
		return 0 //not equipped

	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_BACK) == src)
		return 1
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_BELT) == src)
		return 1
	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src)
		return 1
	if(HAS_TAG(src, TAG_WEAR_BELT) && M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src)
		return 1

	return 0

/*
	Base Unit Subtypes
*/

/obj/item/defib_kit/compact
	name = "compact defibrillator"
	desc = "A belt-equipped defibrillator that can be rapidly deployed."
	icon_state = "defibcompact"
	item_state = "defibcompact"
	w_class = ITEMSIZE_NORMAL
	slot_flags = SLOT_BELT

/obj/item/defib_kit/compact/loaded
	bcell = /obj/item/cell/high

/obj/item/defib_kit/compact/combat
	name = "combat defibrillator"
	desc = "A belt-equipped blood-red defibrillator that can be rapidly deployed. Does not have the restrictions or safeties of conventional defibrillators and can revive through space suits."
	paddle_path = /obj/item/shockpaddles/linked/combat

/obj/item/defib_kit/compact/combat/loaded
	bcell = /obj/item/cell/high

/obj/item/shockpaddles/linked/combat
	combat = 1
	safety = 0
	chargetime = (1 SECONDS)

//paddles

/obj/item/shockpaddles
	name = "defibrillator paddles"
	desc = "A pair of plastic-gripped paddles with flat metal surfaces that are used to deliver powerful electric shocks."
	icon = 'icons/obj/defibrillator.dmi'
	icon_state = "defibpaddles"
	item_state = "defibpaddles"
	gender = PLURAL
	force = 2
	throwforce = 6
	w_class = ITEMSIZE_LARGE
	item_flags = NOSTRIP

	var/safety = 1 //if you can zap people with the paddles on harm mode
	var/combat = 0 //If it can be used to revive people wearing thick clothing (e.g. spacesuits)
	var/cooldowntime = (6 SECONDS) // How long in deciseconds until the defib is ready again after use.
	var/chargetime = (2 SECONDS)
	var/chargecost = 1250 //units of charge per zap	//With the default APC level cell, this allows 4 shocks
	var/burn_damage_amt = 5
	var/use_on_synthetic = 0 //If 1, this is only useful on FBPs, if 0, this is only useful on fleshies

	var/wielded = 0
	var/cooldown = 0

/obj/item/shockpaddles/proc/set_cooldown(delay)
	cooldown = 1
	update_icon()

	om_after(src, delay, PROC_REF(recharged))

/obj/item/shockpaddles/update_held_icon()
	var/mob/living/M = loc
	if(istype(M) && M.item_is_in_hands(src) && !M.hands_are_full())
		wielded = 1
		name = "[initial(name)] (wielded)"
	else
		wielded = 0
		name = initial(name)
	update_icon()
	..()

/obj/item/shockpaddles/update_icon()
	icon_state = "defibpaddles[wielded]"
	item_state = "defibpaddles[wielded]"
	if(cooldown)
		icon_state = "defibpaddles[wielded]_cooldown"

/obj/item/shockpaddles/proc/can_use(mob/user, mob/M)
	if(om_busy(src))
		return 0
	if(!check_charge(chargecost))
		to_chat(user, span_warning("\The [src] doesn't have enough charge left to do that."))
		return 0
	if(!wielded && !isrobot(user))
		to_chat(user, span_warning("You need to wield the paddles with both hands before you can use them on someone!"))
		return 0
	if(cooldown)
		to_chat(user, span_warning("\The [src] are re-energizing!"))
		return 0
	return 1

//Checks for various conditions to see if the mob is revivable
/obj/item/shockpaddles/proc/can_defib(mob/living/carbon/human/H) //This is checked before doing the defib operation
	if((H.species.flags & NO_DEFIB))
		return "buzzes, \"Incompatible physiology. Operation aborted.\""
	else if(H.isSynthetic() && !use_on_synthetic)
		return "buzzes, \"Synthetic Body. Operation aborted.\""
	else if(!H.isSynthetic() && use_on_synthetic)
		return "buzzes, \"Organic Body. Operation aborted.\""

	// Rhythm analysis: only VF (or an unstable tachyarrhythmia) is shockable.
	var/datum/affliction/cardiac_arrhythmia/rhythm = H.cardiac_arrhythmia()
	if(rhythm?.rhythm == CARDIAC_RHYTHM_ASYSTOLE)
		return "buzzes, \"Asystole detected - no shockable rhythm. Continue CPR and administer a vasopressor.\""
	if(H.stat != DEAD && !rhythm?.is_shockable())
		return "buzzes, \"No shockable rhythm detected. Operation aborted.\""

	if(!check_contact(H))
		return "buzzes, \"Patient's chest is obstructed. Operation aborted.\""

	return null

/obj/item/shockpaddles/proc/can_revive(mob/living/carbon/human/H) //This is checked right before attempting to revive
	// D11: there is nothing to restart without a heart.
	if(H.should_have_organ(O_HEART) && !H.internal_organs_by_name[O_HEART])
		return "buzzes, \"Resuscitation failed - No cardiac activity: patient has no heart. Further attempts futile without replacement.\""
	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	if(H.should_have_organ(O_BRAIN))
		if(!brain)
			return "buzzes, \"Resuscitation failed - Patient lacks a brain. Further attempts futile without replacement.\""
		else if(istype(brain, /obj/item/organ/internal/brain)) //Some species have weird 'brains' that aren't technically brains. Those don't have defib timers.
			if(brain.is_brain_dead())
				return "buzzes, \"Resuscitation failed - Brain death detected. Patient requires resleeving.\""
			if(brain.defib_window_left() <= 0)
				return "buzzes, \"Resuscitation failed - Patient's brain has naturally degraded past a recoverable state. Further attempts futile.\""

	// Structural damage (physical + thermal + cellular) at twice the patient's endurance or more
	// means the body can't sustain a restarted heart. Oxygen debt and toxins don't count - the
	// restored circulation repays the debt, and the shock deals with the toxins.
	var/structural_damage = H.injury_load(INJURY_CATEGORY_PHYSICAL) + H.injury_load(INJURY_CATEGORY_THERMAL) + H.injury_load(INJURY_CATEGORY_GENETIC)
	var/too_damaged = structural_damage >= 2 * H.get_endurance()
	if(too_damaged && H.isSynthetic())
		return "buzzes, \"Resuscitation failed - Severe damage detected. Begin damage restoration before further attempts.\""

	else if(too_damaged) //They need to be healed first.
		return "buzzes, \"Resuscitation failed - Severe tissue damage detected. Repair of anatomical damage required.\""

	else if(H.has_mutation(HUSK)) //Husked! Need to fix their husk status first.
		return "buzzes, \"Resuscitation failed - Anatomical structure malformation detected. 'De-Husk' surgery required.\""

	else if(!H.can_defib) //We can frankensurgery them! Let's tell the user.
		return "buzzes, \"Resuscitation failed - Severe neurological deformation detected. Brain-stem reattachment surgery required.\""

	var/bad_vital_organ = H.check_vital_organs() //CONTRARY to what you may think, your HEART AND LUNGS ARE NOT VITAL. Only the brain is. This is here in case a species has a special vital organ they need to survive in addiition to their brain.
	if(bad_vital_organ)
		return "buzzes, \"Resuscitation failed - Patient's ([bad_vital_organ]) is missing / suffering extensive damage. Further attempts futile without surgical intervention.\""

	//this needs to be last since if any of the 'other conditions are met their messages take precedence
	//if(!H.client && !H.teleop)
	// return "buzzes, \"Resuscitation failed - Mental interface error. Further attempts may be successful.\""// removing this check to allow revival through bad internet connections.

	return null

/obj/item/shockpaddles/proc/check_contact(mob/living/carbon/human/H)
	if(!combat)
		for(var/obj/item/clothing/cloth in list(H.get_equipped_item(SLOT_ID_SUIT), H.get_equipped_item(SLOT_ID_UNIFORM)))
			if((cloth.body_parts_covered & UPPER_TORSO) && (cloth.item_flags & THICKMATERIAL))
				return FALSE
	return TRUE

/obj/item/shockpaddles/proc/check_vital_organs(mob/living/carbon/human/H)
	var/bad_vital = H.check_vital_organs()
	if(!bad_vital) //All organs are A-OK. Let's go!
		return null
	//Otherwise, we have a bad vital organ, return a message to the user
	return "buzzes, \"Resuscitation failed - Patient is vital organ ([bad_vital]) is missing / suffering extensive damage. Further attempts futile without surgical intervention.\""

/obj/item/shockpaddles/proc/check_blood_level(mob/living/carbon/human/H)
	if(!H.should_have_organ(O_HEART))
		return FALSE

	var/obj/item/organ/internal/heart/heart = H.internal_organs_by_name[O_HEART]
	if(!heart)
		return TRUE

	var/blood_volume = H.vessel.get_reagent_amount(REAGENT_ID_BLOOD)
	if(!heart || heart.is_broken())
		blood_volume *= 0.3
	else if(heart.is_bruised())
		blood_volume *= 0.7
	else if(heart.damage > 5) // so ONE heart damage isnt 20% of blood missing, now its 5
		blood_volume *= 0.9 //chompedit, 90% instead of 80%
	return blood_volume < H.species.blood_volume*H.species.blood_level_fatal

/obj/item/shockpaddles/proc/check_charge(charge_amt)
	return 0

/obj/item/shockpaddles/proc/checked_use(charge_amt)
	return 0

/obj/item/shockpaddles/proc/get_power_cell()
	RETURN_TYPE(/obj/item/cell)
	return null

/obj/item/shockpaddles/proc/power_output_envelope(charge_amt)
	var/obj/item/cell/power_cell = get_power_cell()
	return power_cell ? power_cell.material_output_envelope(charge_amt, 1.5) : 1

/obj/item/shockpaddles/proc/consume_enhanced_charge(charge_amt, output_envelope)
	if(!checked_use(charge_amt * output_envelope))
		return FALSE
	get_power_cell()?.material_record_enhanced_output(charge_amt, output_envelope)
	return TRUE

/obj/item/shockpaddles/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	var/mob/living/carbon/human/H = M
	if(!istype(H) || IS_HARMING(user))
		return ..() //Do a regular attack. Harm intent shocking happens as a hit effect

	if(can_use(user, H))
		do_revive(H, user)

	return ITEM_INTERACT_SUCCESS

//Since harm-intent now skips the delay for deliberate placement, you have to be able to hit them in combat in order to shock people.
/obj/item/shockpaddles/apply_hit_effect(mob/living/target, mob/living/user, hit_zone)
	if(ishuman(target) && can_use(user, target))
		do_electrocute(target, user, hit_zone)

		return 1

	return ..()

// The revive chain: each timed action claims the paddles (om_busy()) while it runs.
/obj/item/shockpaddles/proc/do_revive(mob/living/carbon/human/H, mob/user)
	var/mob/observer/dead/ghost = H.get_ghost()
	if(ghost)
		ghost.notify_revive("Someone is trying to resuscitate you. Re-enter your body if you want to be revived!", 'sound/effects/genetics.ogg', source = src)

	//beginning to place the paddles on patient's chest to allow some time for people to move away to stop the process
	user.visible_message(span_warning("\The [user] begins to place [src] on [H]'s chest."), span_warning("You begin to place [src] on [H]'s chest..."))
	om_do_after(user, 3 SECONDS, target = H, receiver = src, on_done = PROC_REF(do_revive_timed_done), done_args = list(H, user), busy = src)
	return TRUE

/obj/item/shockpaddles/proc/do_revive_timed_done(mob/living/carbon/human/H, mob/user)
	user.visible_message(span_infoplain(span_bold("\The [user]") + " places [src] on [H]'s chest."), span_warning("You place [src] on [H]'s chest."))
	playsound(src, 'sound/machines/defib_charge.ogg', 50, 0)

	var/error = can_defib(H)
	if(error)
		make_announcement(error, "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	if(check_blood_level(H))
		make_announcement("buzzes, \"Warning - Patient is in hypovolemic shock.\"", "warning") //also includes heart damage

	//placed on chest and short delay to shock for dramatic effect, revive time is 5sec total
	var/output_envelope = power_output_envelope(chargecost)
	om_task_start(/datum/om/task/timed/shockpaddles_do_revive_charged, user, H, receiver = src, duration = chargetime / output_envelope, output_envelope = output_envelope, busy = src)

/datum/om/task/timed/shockpaddles_do_revive_charged
	complete_proc = /obj/item/shockpaddles/proc/do_revive_charged
	var/output_envelope

/obj/item/shockpaddles/proc/do_revive_charged(datum/om/task/timed/shockpaddles_do_revive_charged/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/output_envelope = task.output_envelope
	//deduct charge here, in case the base unit was EMPed or something during the delay time
	if(!consume_enhanced_charge(chargecost, output_envelope))
		make_announcement("buzzes, \"Insufficient charge.\"", "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	H.visible_message(span_warning("\The [H]'s body convulses a bit."))
	playsound(src, "bodyfall", 50, 1)
	playsound(src, 'sound/machines/defib_zap.ogg', 50, 1, -1)
	set_cooldown(cooldowntime)

	// A living patient in a shockable rhythm: cardiovert, no resurrection involved.
	if(H.stat != DEAD)
		H.injure(INJURY_BURN, burn_damage_amt, BP_TORSO, src)
		if(H.defibrillate_heart())
			make_announcement("pings, \"Rhythm converted. Pulse detected.\"", "notice")
			playsound(src, 'sound/machines/defib_success.ogg', 50, 0)
		else
			make_announcement("buzzes, \"Conversion failed. Continue CPR.\"", "warning")
			playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		add_attack_logs(user, H, "Cardioverted using [name]")
		return

	var/error = can_revive(H)
	if(error)
		make_announcement(error, "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	H.injure(INJURY_BURN, burn_damage_amt, BP_TORSO, src)
	if(HAS_TRAIT(H, TRAIT_UNLUCKY) && prob(5))
		make_announcement("buzzes, \"Unknown error occurred. Please try again.\"", "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, FALSE)
		return

	// A fibrillating corpse needs its rhythm converted to come back.
	var/datum/affliction/cardiac_arrhythmia/rhythm = H.cardiac_arrhythmia()
	if(rhythm && !rhythm.is_perfusing() && !H.defibrillate_heart())
		make_announcement("buzzes, \"Resuscitation failed - rhythm did not convert. Continue CPR.\"", "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	// Flush synthetic system faults (a no-op on organic parts).
	H.mend(TREAT_SYSTEM_RESTORE, H.injury_load(INJURY_CATEGORY_TOXIC))

	var/revived = make_alive(H)
	if(revived != TRUE)
		make_announcement("buzzes, \"Resuscitation failed - [revived]. Further attempts futile without treatment.\"", "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	make_announcement("pings, \"Resuscitation successful.\"", "notice")
	playsound(src, 'sound/machines/defib_success.ogg', 50, 0)

	log_and_message_admins("used \a [src] to revive [key_name(H)].")

/obj/item/shockpaddles/proc/do_electrocute(mob/living/carbon/human/H, mob/user, target_zone)
	var/obj/item/organ/external/affecting = H.get_organ(target_zone)
	if(!affecting)
		to_chat(user, span_warning("They are missing that body part!"))
		return

	//no need to spend time carefully placing the paddles, we're just trying to shock them
	user.visible_message(span_danger("\The [user] slaps [src] onto [H]'s [affecting.name]."), span_danger("You overcharge [src] and slap them onto [H]'s [affecting.name]."))

	//Just stop at awkwardly slapping electrodes on people if the safety is enabled
	if(safety)
		to_chat(user, span_warning("You can't do that while the safety is enabled."))
		return

	playsound(src, 'sound/machines/defib_charge.ogg', 50, 0)
	audible_message(span_warning("\The [src] lets out a steadily rising hum..."), runemessage = "whines")

	var/output_envelope = power_output_envelope(chargecost)
	om_task_start(/datum/om/task/timed/shockpaddles_do_electrocute, user, H, receiver = src, duration = chargetime / output_envelope, target_zone_arg = target_zone, output_envelope = output_envelope, busy = src)
	return TRUE

/datum/om/task/timed/shockpaddles_do_electrocute
	complete_proc = /obj/item/shockpaddles/proc/do_electrocute_timed_done
	var/target_zone_arg
	var/output_envelope

/obj/item/shockpaddles/proc/do_electrocute_timed_done(datum/om/task/timed/shockpaddles_do_electrocute/task)
	var/mob/living/carbon/human/H = task.target
	var/mob/user = task.actor
	var/target_zone = task.target_zone_arg
	var/output_envelope = task.output_envelope

	//deduct charge here, in case the base unit was EMPed or something during the delay time
	if(!consume_enhanced_charge(chargecost, output_envelope))
		make_announcement("buzzes, \"Insufficient charge.\"", "warning")
		playsound(src, 'sound/machines/defib_failed.ogg', 50, 0)
		return

	user.visible_message(span_danger(span_italics("\The [user] shocks [H] with \the [src]!")), span_warning("You shock [H] with \the [src]!"))
	playsound(src, 'sound/machines/defib_zap.ogg', 100, 1, -1)
	playsound(src, 'sound/weapons/egloves.ogg', 100, 1, -1)
	set_cooldown(cooldowntime)

	H.stun_effect_act(2, 120, target_zone, electric = TRUE)
	var/burn_damage = H.electrocute_act(burn_damage_amt*2, src, def_zone = target_zone)
	if(burn_damage > 15 && H.can_feel_pain())
		H.emote("scream")

	add_attack_logs(user,H,"Shocked using [name]")

/// Revive the patient through return_from_death(). Returns TRUE, or the refusal reason.
/obj/item/shockpaddles/proc/make_alive(mob/living/carbon/human/M)
	M.body?.begin_revival_grace(src)
	. = M.return_from_death("defibrillated", src, REVIVE_UNCONSCIOUS) //Life() can bring them back to consciousness if it needs to.
	if(. != TRUE)
		return

	M.emote("gasp")
	M.status_at_least(EFFECT_WEAKENED, rand(10,25))
	apply_brain_damage(M)
	M.injure(INJURY_PAIN, 40, BP_TORSO, src) // Moderate amount of halloss for EVERYONE being defibbed. Defibs feel like being kicked in the chest by a mule. Shit hurts if you're awake.
	// s Start: Defib pain
	var/datum/xenochimera/xc = M.get_xenochimera_state()
	if(xc) // Only do the following to Xenochimera. Handwave this however you want, this is to balance defibs on an alien race.
		M.injure(INJURY_PAIN, 220, BP_TORSO, src) // This hurts a LOT, stacks on top of the previous halloss.
		xc.feral += 100 // If they somehow weren't already feral, force them feral by increasing ferality var directly, to avoid any messy checks. handle_feralness() will immediately set our feral properly according to halloss anyhow.
	// s End
	// SSgame_master.adjust_danger(-20) // We don't use SSgame_master yet.

/obj/item/shockpaddles/proc/apply_brain_damage(mob/living/carbon/human/H)
	if(!H.should_have_organ(O_BRAIN))
		return // No brain.

	var/obj/item/organ/internal/brain/brain = H.internal_organs_by_name[O_BRAIN]
	if(!brain)
		return // Still no brain.

	if(!istype(brain))
		return // an MMI holder or posibrain does not decay
	var/brain_damage = brain.revival_brain_damage(H.injury_load(INJURY_CATEGORY_NEURAL))
	if(brain_damage <= 0)
		return // Revived before brain damage set in.
	H.injure(INJURY_NEURAL, brain_damage, BP_HEAD, src, flags = INJURE_IGNORE_RESISTANCE)

/obj/item/shockpaddles/proc/make_announcement(message, msg_class)
	audible_message(span_bold(span_info("\The [src]") + " [message]"), span_info("\The [src] vibrates slightly."), runemessage = "buzz")

/obj/item/shockpaddles/emag_act(mob/user)
	if(safety)
		safety = 0
		to_chat(user, span_warning("You silently disable \the [src]'s safety protocols with the cryptographic sequencer."))
		update_icon()
		return 1
	else
		safety = 1
		to_chat(user, span_notice("You silently enable \the [src]'s safety protocols with the cryptographic sequencer."))
		update_icon()
		return 1

/obj/item/shockpaddles/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	var/new_safety = rand(0, 1)
	if(safety != new_safety)
		safety = new_safety
		if(safety)
			make_announcement("beeps, \"Safety protocols enabled!\"", "notice")
			playsound(src, 'sound/machines/defib_SafetyOn.ogg', 50, 0)
		else
			make_announcement("beeps, \"Safety protocols disabled!\"", "warning")
			playsound(src, 'sound/machines/defib_safetyOff.ogg', 50, 0)
		update_icon()

/obj/item/shockpaddles/robot
	name = "defibrillator paddles"
	desc = "A pair of advanced shockpaddles powered by a robot's internal power cell, able to penetrate thick clothing."
	chargecost = 50
	combat = 1
	icon_state = "defibpaddles0"
	item_state = "defibpaddles0"
	cooldowntime = (3 SECONDS)

/obj/item/shockpaddles/robot/check_charge(charge_amt)
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return (R.cell && R.cell.check_charge(charge_amt))

/obj/item/shockpaddles/robot/get_power_cell()
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return R.cell

/obj/item/shockpaddles/robot/checked_use(charge_amt)
	if(isrobot(src.loc))
		var/mob/living/silicon/robot/R = src.loc
		return R.draw_power(ROBOT_CELL_JOULES(charge_amt), src)

/obj/item/shockpaddles/robot/combat
	name = "combat defibrillator paddles"
	desc = "A pair of advanced shockpaddles powered by a robot's internal power cell, able to penetrate thick clothing.  This version \
	appears to be optimized for combat situations, foregoing the safety inhabitors in favor of a faster charging time."
	safety = 0
	chargetime = (1 SECONDS)

/*
	Shockpaddles that are linked to a base unit
*/
/obj/item/shockpaddles/linked/check_charge(charge_amt)
	var/obj/item/defib_kit/base_unit = src?.tether_host()
	return (base_unit.bcell && base_unit.bcell.check_charge(charge_amt))

/obj/item/shockpaddles/linked/get_power_cell()
	var/obj/item/defib_kit/base_unit = src?.tether_host()
	return base_unit?.bcell

/obj/item/shockpaddles/linked/checked_use(charge_amt)
	var/obj/item/defib_kit/base_unit = src?.tether_host()
	return (base_unit.bcell && base_unit.bcell.checked_use(charge_amt))

/obj/item/shockpaddles/linked/make_announcement(message, msg_class)
	var/obj/item/defib_kit/base_unit = src?.tether_host()
	base_unit.audible_message(span_infoplain(span_bold("\The [base_unit]") + " [message]"), span_info("\The [base_unit] vibrates slightly."))

/*
	Standalone Shockpaddles
*/

/obj/item/shockpaddles/standalone
	desc = "A pair of shockpaddles powered by an experimental miniaturized reactor" //Inspired by the advanced e-gun
	var/fail_counter = 0
	var/last_event = 0
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/obj/item/shockpaddles/standalone/check_charge(charge_amt)
	return 1

/obj/item/shockpaddles/standalone/checked_use(charge_amt)
	radiation_pulse(
		src,
		max_range = 5,
		threshold = RAD_MEDIUM_INSULATION,
		chance = URANIUM_IRRADIATION_CHANCE,
		strength = 50
	)
	return 1

/obj/item/shockpaddles/standalone/periodic_step()
	if(fail_counter > 0)
		radiation_pulse(
			src,
			max_range = 5,
			threshold = RAD_MEDIUM_INSULATION,
			chance = URANIUM_IRRADIATION_CHANCE,
			strength = 15
		)
		fail_counter--
	else
		PERIODIC_STOP(src)

/obj/item/shockpaddles/standalone/emp_act(severity, recursive)
	. = ..()
	if (. & EMP_PROTECT_SELF)
		return
	var/new_fail = 0
	switch(severity)
		if(1)
			new_fail = max(fail_counter, 20)
			visible_message("\The [src]'s reactor overloads!")
		if(2)
			new_fail = max(fail_counter, 8)
			if(ismob(loc))
				to_chat(loc, span_warning("\The [src] feel pleasantly warm."))

	if(new_fail && !fail_counter)
		PERIODIC_START(src, PERIODIC_SLOW)
	fail_counter = new_fail

/* From the Bay port, this doesn't seem to have a sprite.
/obj/item/shockpaddles/standalone/traitor
	name = "defibrillator paddles"
	desc = "A pair of unusual looking paddles powered by an experimental miniaturized reactor. It possesses both the ability to penetrate armor and to deliver powerful shocks."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "defibpaddles0"
	item_state = "defibpaddles0"
	combat = 1
	safety = 0
	chargetime = (1 SECONDS)
*/

//FBP Defibs
/obj/item/defib_kit/jumper_kit
	name = "jumper cable kit"
	desc = "A device that delivers powerful shocks to detachable jumper cables that are capable of reviving full body prosthetics."
	icon_state = "jumperunit"
	item_state = "defibunit"
//	item_state = "jumperunit"
	paddle_path = /obj/item/shockpaddles/linked/jumper

/obj/item/defib_kit/jumper_kit/loaded
	bcell = /obj/item/cell/high

/obj/item/shockpaddles/linked/jumper
	name = "jumper cables"
	icon_state = "jumperpaddles"
	item_state = "jumperpaddles"
	use_on_synthetic = 1

/obj/item/shockpaddles/robot/jumper
	name = "jumper cables"
	desc = "A pair of advanced shockpaddles powered by a robot's internal power cell, able to penetrate thick clothing."
	icon_state = "jumperpaddles0"
	item_state = "jumperpaddles0"
	use_on_synthetic = 1

#undef DEFIB_TIME_LOSS

/obj/item/shockpaddles/proc/recharged()
	if(cooldown)
		cooldown = 0
		update_icon()

		make_announcement("beeps, \"Unit is re-energized.\"", "notice")
		playsound(src, 'sound/machines/defib_ready.ogg', 50, 0)
