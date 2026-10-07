//There has to be a better way to define this shit. ~ Z
//can't equip anything
/mob/living/carbon/alien/attack_ui(slot_id)
	return

/mob/living/carbon/alien/unarmed_touch(mob/living/M, stance = I_HELP)

	..()

	switch(stance)

		if (I_HELP)
			help_shake_act(M)

		if (I_GRAB)
			if (M == src)
				return
			var/obj/item/grab/G = new /obj/item/grab( M, src )

			M.put_in_active_hand(G)

			// new /obj/item/grab(M, src) already ran Initialize(mapload, src),
			// which established the grabbing relation (grabbed_by/affecting).
			G.synch()

			rel_set(src, nameof(LAssailant), M)

			play_sfx(src, SFX_WEAPONS_THUDSWOOSH)
			for(var/mob/O in viewers(src, null))
				if ((O.client && !( O.blinded )))
					O.show_message(span_danger(text("[] has grabbed [] passively!", M, src)), 1)

		else
			var/damage = rand(1, 9)
			if (prob(90))
				if (M.has_mutation(HULK))
					damage += 5
					status_at_least(STAT_PARALYZED, 1)
					step_away(src,M,15)
					after(src, 0.3 SECONDS, PROC_REF(knocked_away_from), with = list(M))
				play_sfx(src, SFX_PUNCH, 0.5, extrarange = -1)
				for(var/mob/O in viewers(src, null))
					if ((O.client && !( O.blinded )))
						O.show_message(span_bolddanger(text("[] has punched []!", M, src)), 1)
				if (damage > 4.9)
					status_at_least(STAT_WEAKENED, rand(10,15))
					for(var/mob/O in viewers(M, null))
						if ((O.client && !( O.blinded )))
							O.show_message(span_bolddanger(text("[] has weakened []!", M, src)), 1, span_red("You hear someone fall."), 2)
				injure(INJURY_BLUNT, damage, null, M)
			else
				play_sfx(src, SFX_WEAPONS_PUNCHMISS)
				for(var/mob/O in viewers(src, null))
					if ((O.client && !( O.blinded )))
						O.show_message(span_bolddanger(text("[] has attempted to punch []!", M, src)), 1)
	return

/// The second shove of a hulk punch.
/mob/living/carbon/alien/proc/knocked_away_from(mob/M)
	if(!M)
		return
	step_away(src, M, 15)
