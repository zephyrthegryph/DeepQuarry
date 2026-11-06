/obj/item/clothing/suit/armor/reactive/teleport
	name = "reactive teleport armor"
	desc = "Someone separated our Research Director from his own head!"
	emp_message = span_warning("The reactive armor's teleportation calculations begin spewing errors!")
	cooldown_message = span_danger("The reactive teleport system is still recharging! It fails to activate!")
	reactivearmor_cooldown_duration = 10 SECONDS
	var/tele_range = 6

/obj/item/clothing/suit/armor/reactive/teleport/reactive_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", final_block_chance = 0, damage = 0)
	act_message(owner, null, others = span_danger("The reactive teleport system flings %U% clear of [attack_text]!"))
	play_sfx(get_turf(owner), SFX_EFFECTS_PHASEIN)
	do_teleport(owner, get_turf(owner), tele_range, no_effects = TRUE, channel = TELEPORT_CHANNEL_BLUESPACE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return TRUE

/obj/item/clothing/suit/armor/reactive/teleport/emp_activation(mob/living/carbon/human/owner, atom/movable/hitby, attack_text = "the attack", final_block_chance = 0, damage = 0)
	owner.visible_message(span_danger("The reactive teleport system flings itself clear of [attack_text], leaving someone behind in the process!"))
	owner.drop_from_inventory(src, get_turf(src))
	play_sfx(get_turf(owner), SFX_MACHINES_BUZZ_SIGH, vary = TRUE)
	play_sfx(get_turf(owner), SFX_EFFECTS_PHASEIN)
	do_teleport(src, get_turf(owner), tele_range, no_effects = TRUE, channel = TELEPORT_CHANNEL_BLUESPACE)
	COOLDOWN_START(src, reactivearmor_cooldown, reactivearmor_cooldown_duration)
	return FALSE
