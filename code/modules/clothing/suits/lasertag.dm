/*
 * Lasertag
 */

///DO NOT USE THIS BASE VARIANT, STUFF WILL BREAK!
/obj/item/clothing/suit/lasertag
	name = "laser tag armor"
	desc = "An example laser tag armor. Can not actually be used and is just for demonstrations."
	icon = 'icons/inventory/suit/item.dmi'
	icon_state = "omnitag"
	item_icons = list(slot_l_hand_str = 'icons/mob/items/lefthand_suits.dmi', slot_r_hand_str = 'icons/mob/items/righthand_suits.dmi')
	item_state_slots = list(slot_r_hand_str = "tdomni", slot_l_hand_str = "tdomni")
	blood_overlay_type = "armor"
	body_parts_covered = UPPER_TORSO
	siemens_coefficient = 3.0
	description_fluff = "Laser tag armor can have its health and 'healing' time adjusted. Additionally, DonkSoft brand darts are compatible with laser tag vests, proving a projectile based alternative!"
	description_antag = "Laser tag armor can be emagged, causing the user to not only have a heart attack when eliminated, but also take massive damage based on the amount of 'lives' the vest had."

	var/lasertag_max_health = 3
	var/lasertag_health = 3

	///How long it takes for us to heal one point of health
	var/time_to_heal = 10 SECONDS

	///When we were last hit!
	COOLDOWN_DECLARE(heal_cooldown)

	///If we're emagged or not.
	var/emagged

TYPE_TABLE(/obj/item/clothing/suit/lasertag, suit_storage_spec, list(HOLD_ONLY(list (/obj/item/gun/energy/lasertag))))

DECLARE_EMAG(/obj/item/clothing/suit/lasertag, PROC_REF(on_emag), null, null)

/obj/item/clothing/suit/lasertag/mark_emagged()
	emagged = TRUE
/obj/item/clothing/suit/lasertag/proc/on_emag(remaining_charges, mob/user, obj/item/emag_source)
	emagged = TRUE
	to_chat(user, span_warning("You disable the safeties on the lasertag vest."))
	return TRUE


/obj/item/clothing/suit/lasertag/examine(mob/user)
	. = ..()
	. += "It currently has [lasertag_health] hits out of [lasertag_max_health] remaining!"
	. += "It regenerates one hit every [time_to_heal*0.1] seconds."

CAPABILITIES(/obj/item/clothing/suit/lasertag)
	op("lasertag_adjust_health_verb", menu(), label("Adjust Suit Health"), needs(carried()), then(PROC_REF(lasertag_adjust_health_verb)))
	op("lasertag_adjust_heal_time_verb", menu(), label("Adjust Healing Timer"), needs(carried()), then(PROC_REF(lasertag_adjust_heal_time_verb)))

/// Old verb "Adjust Suit Health".
/obj/item/clothing/suit/lasertag/proc/lasertag_adjust_health_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		adjust_health_proc(user)

/obj/item/clothing/suit/lasertag/proc/adjust_health_proc(mob/living/user)
	var/max_health = 10
	var/min_health = 1
	var/_answer_a1 = rerun_ask(user, "a1", PROC_REF(adjust_health_proc), args, /datum/om/prompt/number, message = "Select Suit Health (Between 1 and 10)", title = "Tag Health", default = lasertag_max_health, max = max_health, min = min_health)
	if(isnull(_answer_a1))
		return
	var/new_health = _answer_a1 //If you need to go above 10, ask admins.
	if(isnull(new_health))
		return null
	if(new_health > max_health || new_health < min_health)
		to_chat(user, span_danger("Invalid health value! Must be between [min_health] and [max_health]."))
		return null
	if(!Adjacent(user))
		to_chat(user, span_danger("You must be adjacent to the suit to adjust its healing timer!"))
		return null
	lasertag_max_health = new_health
	lasertag_health = lasertag_max_health
	act_message(user, src, MSG_SELF(span_notice("Set %T%'s allowed shots to [lasertag_max_health], fully healing the vest!")))

/// Old verb "Adjust Healing Timer".
/obj/item/clothing/suit/lasertag/proc/lasertag_adjust_heal_time_verb(datum/act/op/A)
	var/mob/user = A.actor
	if(isliving(user))
		adjust_heal_time_proc(user)

/obj/item/clothing/suit/lasertag/proc/adjust_heal_time_proc(mob/living/user)
	var/max_heal_time = 60
	var/min_heal_time = 0
	var/_answer_a2 = rerun_ask(user, "a2", PROC_REF(adjust_heal_time_proc), args, /datum/om/prompt/number, message = "Select Heal Timer (Between 0(off) to 60 seconds)", title = "Heal Timer", default = time_to_heal*0.1, max = max_heal_time, min = min_heal_time)
	if(isnull(_answer_a2))
		return
	var/new_heal_timer = _answer_a2 //If you need to go above 10, ask admins.
	if(isnull(new_heal_timer))
		return null
	if(new_heal_timer > max_heal_time || new_heal_timer < min_heal_time)
		to_chat(user, span_danger("Invalid health value! Must be between [min_heal_time] and [max_heal_time]."))
		return null
	if(!Adjacent(user))
		to_chat(user, span_danger("You must be adjacent to the suit to adjust its healing timer!"))
		return null
	time_to_heal = (new_heal_timer*10)
	if(time_to_heal)
		user.visible_message(span_notice("[src]'s heal speed has been set to [new_heal_timer] seconds!"))
	else
		user.visible_message(span_notice("[src]'s healing function has been turned off!"))

/// TRUE from equipped() until dropped(): it heals over time while worn.
OM_FIELD(/obj/item/clothing/suit/lasertag, tag_worn, FALSE, CHANGE_EXPLICIT)
DECLARE_PERIODIC_WHILE(/obj/item/clothing/suit/lasertag, PERIODIC_SLOW, "tag_worn")

/obj/item/clothing/suit/lasertag/dropped(mob/user, equipping, slot)
	..()
	set_tag_worn(FALSE)
	visible_message(span_notice("[src] is unequipped, its health going back to full!"))
	lasertag_health = lasertag_max_health

/obj/item/clothing/suit/lasertag/equipped()
	..()
	set_tag_worn(TRUE)

/obj/item/clothing/suit/lasertag/periodic_step()
	if(lasertag_health >= lasertag_max_health) //If we're at or above max health(due to admemes), no need to process.
		return
	if(!time_to_heal) //We have healing disabled.
		return

	if(COOLDOWN_FINISHED(src, heal_cooldown))
		if(lasertag_health < 0) //overkill protection
			lasertag_health = 0
		lasertag_health++
		if(lasertag_health == lasertag_max_health)
			if(ismob(src.loc)) //sanity check
				var/mob/wearer = src.loc
				to_chat(wearer, span_notice("Your [src] beeps happily as it fully recharges! You can now be hit [lasertag_health] times before you are downed!"))

/obj/item/clothing/suit/lasertag/proc/handle_hit(damage)
	if(lasertag_health > 0)
		if(damage)
			lasertag_health -= damage
		else
			lasertag_health--
		COOLDOWN_START(src, heal_cooldown, time_to_heal)
		if(isliving(src.loc))
			var/mob/living/wearer = src.loc

			if(lasertag_health > 0) //Still have HP, keep going.
				wearer.visible_message(span_warning("[src] beeps as it takes a shot! [lasertag_health] shots remaining!"))
				return

			act_message(src, wearer, others = span_boldwarning("%U% beeps as its health is fully depleted! %T% is down!"))
			to_chat(wearer, span_large(span_danger("You're out!"))) //People KEEP MISSING THAT THEY'RE OUT, SO NOW THEY WON'T.
			wearer.status_at_least(EFFECT_STUNNED, 5)
			wearer.status_at_least(EFFECT_WEAKENED, 5)
			// The thing just to drop the ball if hit
			if(emagged)
				to_chat(wearer, span_bolddanger(span_massive("OH GOD! YOUR HEART!"))) //this is the last thing you see before you (presumably) die.
				wearer.injure(INJURY_ELECTRIC, lasertag_max_health*50, BP_TORSO, src) // High-voltage electrical shock
				if(ishuman(wearer))
					var/mob/living/carbon/human/human_wearer = wearer
					var/obj/item/organ/internal/heart/H = human_wearer.organ_in(O_HEART)
					if(H)
						if(H.robotic)
							H.break_organ()
						else
							H.bruise()
							// bruise() leaves the heart at min_bruised_damage (15);
							// trim it to 14 so we aren't KO'd from a heart attack.
							if(H.damage > 14)
								human_wearer.mend(TREAT_RESTORATION, H.damage - 14, H)
			return

		if(lasertag_health > 0)
			visible_message(span_warning("[src] beeps as its health is takes a hit! [lasertag_health] shots remaining!"))
		else
			visible_message(span_boldwarning("[src] beeps as its health is depleted!"))
		return

	visible_message(span_warning("[src] beeps - its health is already depleted!"))
	return

/obj/item/clothing/suit/lasertag/bluetag
	name = "blue laser tag armor"
	desc = "Blue Pride, Station Wide."
	icon_state = "bluetag"
	item_state_slots = list(slot_r_hand_str = "tdblue", slot_l_hand_str = "tdblue")

TYPE_TABLE(/obj/item/clothing/suit/lasertag/bluetag, suit_storage_spec, list(HOLD_ONLY(list (/obj/item/gun/energy/lasertag/blue))))

/obj/item/clothing/suit/lasertag/redtag
	name = "red laser tag armor"
	desc = "Reputed to go faster."
	icon_state = "redtag"
	item_state_slots = list(slot_r_hand_str = "tdred", slot_l_hand_str = "tdred")

TYPE_TABLE(/obj/item/clothing/suit/lasertag/redtag, suit_storage_spec, list(HOLD_ONLY(list (/obj/item/gun/energy/lasertag/red))))

/obj/item/clothing/suit/lasertag/bluetag/sub
	name = "Brigader Armor"
	desc = "Replica armor commonly worn by Spacer Union Brigade members from the hit series Spacer Trail. Modified for Laser Tag (Blue Team)."
	icon_state = "bluetag2"

/obj/item/clothing/suit/lasertag/redtag/dom
	name = "Mu'tu'bi Armor"
	desc = "Replica armor commonly worn by Dominion Of Mu'tu'bi soldiers from the hit series Spacer Trail. Modified for Laser Tag (Red Team)."
	icon_state = "redtag2"

/obj/item/clothing/suit/lasertag/omni
	name = "universal laser tag armour"
	desc = "Laser tag armor with no allegiance. For the true renegade, or a free for all."

TYPE_TABLE(/obj/item/clothing/suit/lasertag/omni, suit_storage_spec, list(HOLD_ONLY(list (/obj/item/gun/energy/lasertag/omni))))
