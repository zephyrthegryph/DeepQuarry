//Personal shielding for the combat module.
/obj/item/borg/combat/shield
	name = "personal shielding"
	desc = "A powerful experimental module that turns aside or absorbs incoming attacks at the cost of charge."
	icon = 'icons/obj/decals.dmi'
	icon_state = "shock"
	var/shield_level = 0.5			//Percentage of damage absorbed by the shield.
	var/overload_threshold = 3		//Number of flashes it takes to overload the shield
	var/shield_refresh = 15 SECONDS	//Time it takes for the shield to reboot after destabilizing
	COOLDOWN_DECLARE(overload_cooldown)	//When the shield reboots after an overload
	COOLDOWN_DECLARE(flash_refresh_cooldown)	//When the flash count clears after the last flash

/// If the shield is on (off while it recovers from an overload).
/obj/item/borg/combat/shield/var/active = TRUE

/// Counter for how many times the shield has been flashed.
/obj/item/borg/combat/shield/var/flash_count = 0

/obj/item/borg/combat/shield/proc/recovering()
	return !active || flash_count

CAPABILITIES(/obj/item/borg/combat/shield)
	op("level", in_hand(),
		asks(/datum/prompt/choice, fields = list("ask_flags" = ASK_CARRIED | ASK_CAPABLE, "title" = "Shield Level", "question" = "How much damage should the shield absorb?", "choices" = list("5", "10", "25", "50", "75", "100"), "timeout" = 0), step = "level"),
		then(PROC_REF(shield_ask_level)))
	op("set_level", menu(), label("Set shield level"), needs(carried()),
		asks(/datum/prompt/choice, fields = list("ask_flags" = ASK_CARRIED | ASK_CAPABLE, "title" = "Shield Level", "question" = "How much damage should the shield absorb?", "choices" = list("5", "10", "25", "50", "75", "100"), "timeout" = 0), step = "level"),
		then(PROC_REF(shield_ask_level)))
	/// Cools its flash count or recovers from an overload while either is pending (an overload or a flash count is pending recovery).
	every(2 SECONDS, then(PROC_REF(shield_step)), when = any_of(not(nameof(active)), nameof(flash_count)))

/// Cools its flash count or recovers from an overload every 2 s while either is pending (a flash
/// or an overload starts it); otherwise it sleeps.
/obj/item/borg/combat/shield/proc/shield_step(datum/act/timer/A)
	if(active)
		if(flash_count && COOLDOWN_FINISHED(src, flash_refresh_cooldown))
			set_flash_count(0)
			COOLDOWN_RESET(src, flash_refresh_cooldown)
	else if(COOLDOWN_FINISHED(src, overload_cooldown))
		set_active(TRUE)
		set_flash_count(0)
		COOLDOWN_RESET(src, overload_cooldown)

		var/mob/living/user = src.loc
		if(isliving(user))
			act_message(user, null, MSG_SELF(span_danger("Your shield reactivates!")), MSG_OTHERS(span_danger("%U%'s shield reactivates!")))

/obj/item/borg/combat/shield/proc/adjust_flash_count(mob/living/user, amount)
	if(active)			//Can't destabilize a shield that's not on
		set_flash_count(flash_count + amount)

		if(amount > 0)
			COOLDOWN_START(src, flash_refresh_cooldown, shield_refresh)
			if(flash_count >= overload_threshold)
				overload(user)

/obj/item/borg/combat/shield/proc/overload(mob/living/user)
	set_active(FALSE)
	act_message(user, null, MSG_SELF(span_danger("Your shield destabilizes!")), MSG_OTHERS(span_danger("%U%'s shield destabilizes!")))
	COOLDOWN_START(src, overload_cooldown, shield_refresh)

/// Using the shield in hand, or its menu entry: the level the question was answered with.
/obj/item/borg/combat/shield/proc/shield_ask_level(datum/act/op/A)
	var/datum/prompt/answer = A.answer
	if(!answer)
		return
	shield_level = text2num(answer.value)/100
