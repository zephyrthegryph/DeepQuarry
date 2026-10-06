/obj/item/mecha_parts/mecha_equipment/weapon/honker
	name = "sound emission device"
	desc = "A perfectly normal bike-horn, for your exosuit."
	icon_state = "mecha_honker"
	energy_drain = 300
	equip_cooldown = 150

	equip_type = EQUIP_SPECIAL

/obj/item/mecha_parts/mecha_equipment/weapon/honker/action(target)
	if(!chassis)
		return 0
	if(energy_drain && chassis.get_charge() < energy_drain)
		return 0
	if(!equip_ready)
		return 0

	play_sfx(src, SFX_EFFECTS_BANG, 0.6, extrarange = 30)
	chassis.occupant_message(span_warning("You emit a high-pitched noise from the mech."))
	for(var/mob/living/carbon/M in ohearers(6, chassis))
		if(ishuman(M))
			var/ear_safety = 0
			ear_safety = M.get_ear_protection()
			if(ear_safety > 0)
				continue
		to_chat(M, span_warning("Your ears feel like they're bleeding!"))
		play_sfx(M, SFX_EFFECTS_BANG, 1.4, extrarange = 30)
		M.status_set(STAT_SLEEPING, 0)
		M.status_adjust(STAT_DEAFENED, 30)
		M.deaf_loop.start() // Ear Ringing/Deafness
		M.set_ear_damage(M.ear_damage + (rand(5, 20)))
		M.status_at_least(STAT_WEAKENED, 3)
		M.status_at_least(STAT_STUNNED, 5)
	chassis.use_power(energy_drain)
	src.mecha_log_message("Used a sound emission device.")
	do_after_cooldown()
	return
