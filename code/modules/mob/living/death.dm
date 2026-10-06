// Living contributions to the death pipeline (/mob/proc/death(), code/modules/mob/death.dm).

/// Soul links, nests and vore death flags: everything a living mob is bound to hears once.
/mob/living/death_links(gibbed)
	if(nest) //Ew.
		if(istype(nest, /obj/structure/prop/nest))
			var/obj/structure/prop/nest/N = nest
			N.remove_creature(src)
		if(istype(nest, /obj/structure/blob/factory))
			var/obj/structure/blob/factory/F = nest
			rel_remove(F, nameof(F.spores), src) // pair: clears our factory view too
		if(istype(nest, /obj/structure/mob_spawner))
			var/obj/structure/mob_spawner/S = nest
			S.get_death_report(src)
		nest = null

	if(isbelly(loc) && tf_mob_holder)
		mind?.vore_death = TRUE
		if(tf_mob_holder.loc == src)
			tf_mob_holder.mind?.vore_death = TRUE

	for(var/datum/soul_link/S as anything in owned_soul_links)
		S.owner_died(gibbed)
	for(var/datum/soul_link/S as anything in shared_soul_links)
		S.sharer_died(gibbed)
	end_body_effects_on_death()

/mob/living/play_death_sound(gibbed)
	if(gibbed || isbelly(loc))
		return
	if(death_sound_override) // A few specific mobs override their species death sound.
		playsound(src, death_sound_override, 50, 1, 20, volume_channel = VOLUME_CHANNEL_DEATH_SOUNDS)
		return
	playsound(src, pick(get_species_sound(get_gendered_sound(src))["death"]), death_sound_volume(), 1, 20, volume_channel = VOLUME_CHANNEL_DEATH_SOUNDS)

/// Volume of the species death sound.
/mob/living/proc/death_sound_volume()
	return 50

/mob/living/on_death(gibbed)
	. = ..()
	clear_fullscreens()
	update_mob_action_buttons()
	ai_brain?.go_sleep()
	stop_aiming(no_message = TRUE)
	GLOB.cultnet.updateVisibility(src)

/mob/living/proc/delayed_gib()
	act_message(src, null, MSG_SELF(span_danger("You feel as if your body is tearing itself apart!")), \
		MSG_OTHERS(span_danger(span_bold("%U%") + " starts convulsing violently!")))
	status_at_least(STAT_WEAKENED, 30)
	status_adjust(STAT_JITTERY, 1000)
	after(src, rand(2 SECONDS, 10 SECONDS), PROC_REF(gib))
