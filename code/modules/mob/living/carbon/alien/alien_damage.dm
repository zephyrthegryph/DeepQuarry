DAMAGE_REACTION(/mob/living/carbon/alien, DAMAGE_EXPLOSION, PROC_REF(alien_blast))

/// Aliens take the blast through their own ladder (the mob explosion entry delivers no damage).
/mob/living/carbon/alien/proc/alien_blast(datum/damage_packet/packet)
	var/severity = packet.severity

	if(!blinded)
		flash_eyes()

	var/b_loss = null
	var/f_loss = null
	switch (severity)
		if (1.0)
			b_loss += 500
			gib()
			return

		if (2.0)

			b_loss += 60

			f_loss += 60

			set_ear_damage(ear_damage + (30))
			status_adjust(EFFECT_DEAFENED, 120)
			deaf_loop.start() // Ear Ringing/Deafness

		if(3.0)
			b_loss += 30
			if (prob(50))
				status_at_least(EFFECT_PARALYZED, 1)
			set_ear_damage(ear_damage + (15))
			status_adjust(EFFECT_DEAFENED, 60)
			deaf_loop.start() // Ear Ringing/Deafness

	if(b_loss)
		injure(INJURY_BLUNT, b_loss, null, null, 0, null, INJURE_SILENT)
	if(f_loss)
		injure(INJURY_BURN, f_loss, null, null, 0, null, INJURE_SILENT)
