/proc/playsound(atom/source, soundin, vol as num, vary, extrarange as num, falloff, is_global, frequency = null, channel = 0, pressure_affected = TRUE, ignore_walls = TRUE, preference = null, volume_channel = null)
	if(Kernel.current_runlevel < RUNLEVEL_LOBBY)
		return

	var/turf/turf_source = get_turf(source)
	if(!turf_source)
		return
	var/area/area_source = turf_source.loc

	//allocate a channel if necessary now so its the same for everyone
	channel = channel || SSsounds.ready().random_available_channel()

	var/maxdistance = (world.view + extrarange) * 2 // 3 to 2
	var/source_z = turf_source.z
	var/source_soundproof = area_source.flag_check(AREA_SOUNDPROOF)
	// Built on the first hearer and shared; playsound_local resets every field it uses per listener (Q6).
	var/sound/S

	// Looping through the player list has the added bonus of working for mobs inside containers.
	// Iterated in place: nothing below can add or remove players.
	for(var/mob/hearer as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!hearer.client)
			continue
		var/list/hear_turfs = list(get_turf(hearer))
		// AIs also hear through an active hologram.
		if(isAI(hearer))
			var/mob/living/silicon/ai/ai_hearer = hearer
			var/obj/effect/overlay/aiholo/holo = ai_hearer.holo ? LAZYACCESS(ai_hearer.holo.masters, ai_hearer) : null
			if(istype(holo))
				hear_turfs += get_turf(holo)
		for(var/turf/T as anything in hear_turfs)
			if(!T || T.z != source_z)
				continue
			var/area/A = T.loc
			if(A != area_source && (source_soundproof || A.flag_check(AREA_SOUNDPROOF)))
				continue
			if(get_dist(T, turf_source) > maxdistance)
				continue
			if(!ignore_walls && !can_see(turf_source, T, length = maxdistance * 2))
				continue
			if(!S)
				S = sound(get_sfx(soundin))
			hearer.playsound_local(turf_source, soundin, vol, vary, frequency, falloff, is_global, channel, pressure_affected, S, preference, volume_channel, T)
			SSmotiontracker.ping(source,vol) // Nearly everything pings this, the quieter the less likely

/// TRUE if any player could hear a playsound() from `turf_source` within `max_distance`.
/// Mirrors playsound()'s listener rules, minus soundproofing and walls.
/proc/playsound_has_listener(turf/turf_source, max_distance)
	var/source_z = turf_source.z
	for(var/mob/hearer as anything in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(!hearer.client)
			continue
		var/turf/T = get_turf(hearer)
		if(T && T.z == source_z && get_dist(T, turf_source) <= max_distance)
			return TRUE
		if(isAI(hearer))
			var/mob/living/silicon/ai/ai_hearer = hearer
			var/obj/effect/overlay/aiholo/holo = ai_hearer.holo ? LAZYACCESS(ai_hearer.holo.masters, ai_hearer) : null
			if(istype(holo))
				T = get_turf(holo)
				if(T && T.z == source_z && get_dist(T, turf_source) <= max_distance)
					return TRUE
	return FALSE

/mob/proc/check_sound_preference(list/preference)
	if(!islist(preference))
		preference = list(preference)

	for(var/p in preference)
		// Ignore nulls
		if(p)
			if(!read_preference(p))
				return FALSE

	return TRUE

/mob/proc/playsound_local(turf/turf_source, soundin, vol as num, vary, frequency, falloff, is_global, channel = 0, pressure_affected = TRUE, sound/S, preference, volume_channel = null)
	if(!client || has_status(STAT_DEAFENED))
		return

	if(!check_sound_preference(preference))
		return

	if(!S)
		S = sound(get_sfx(soundin))

	S.wait = 0 //No queue
	S.channel = channel || SSsounds.ready().random_available_channel()

	// I'm not sure if you can modify S.volume, but I'd rather not try to find out what
	// horrible things lurk in BYOND's internals, so we're just gonna do vol *=
	vol *= client.get_preference_volume_channel(volume_channel)
	vol *= client.get_preference_volume_channel(VOLUME_CHANNEL_MASTER)
	S.volume = vol

	if(vary || frequency)
		if(frequency)
			S.frequency = frequency
		else
			S.frequency = get_rand_frequency()

	// Check if an AI is listening through hologram...
	var/turf/T = get_turf(src)
	var/listener_position = T
	if(isAI(src))
		var/mob/living/silicon/ai/A = src
		if(A.holo && istype(LAZYACCESS(A.holo.masters, A),/obj/effect/overlay/aiholo))
			T = get_turf(LAZYACCESS(A.holo.masters, A))
			listener_position = LAZYACCESS(A.holo.masters, A)

	if(isturf(turf_source))
		//sound volume falloff with distance
		var/distance = get_dist(T, turf_source)

		S.volume -= max(distance - world.view, 0) * 2 //multiplicative falloff to add on top of natural audio falloff.

		//Atmosphere affects sound
		var/pressure_factor = 1
		if(pressure_affected)
			var/datum/gas_mixture/hearer_env = T.return_air()
			var/datum/gas_mixture/source_env = turf_source.return_air()

			if(hearer_env && source_env)
				var/pressure = min(hearer_env.return_pressure(), source_env.return_pressure())
				if(pressure < ONE_ATMOSPHERE)
					pressure_factor = max((pressure - SOUND_MINIMUM_PRESSURE)/(ONE_ATMOSPHERE - SOUND_MINIMUM_PRESSURE), 0)
			else //space
				pressure_factor = 0

			if(distance <= 1)
				pressure_factor = max(pressure_factor, 0.15) //touching the source of the sound

			S.volume *= pressure_factor
			//End Atmosphere affecting sound

		//Don't bother with doing anything below.
		if(S.volume <= 0)
			return //No sound

		//Apply a sound environment.
		if(!is_global)
			S.environment = get_sound_env(listener_position,pressure_factor)

		var/dx = turf_source.x - T.x // Hearing from the right/left
		S.x = dx
		var/dz = turf_source.y - T.y // Hearing from infront/behind
		S.z = dz
		// The y value is for above your head, but there is no ceiling in 2d spessmens.
		S.y = 1
		S.falloff = (falloff ? falloff : FALLOFF_SOUNDS)

	src << S

/proc/sound_to_playing_players(sound, volume = 100, vary)
	sound = get_sfx(sound)
	for(var/M in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
		if(ismob(M) && !isnewplayer(M))
			var/mob/MO = M
			MO.playsound_local(get_turf(MO), sound, volume, vary, pressure_affected = FALSE)

/mob/proc/stop_sound_channel(chan)
	src << sound(null, repeat = 0, wait = 0, channel = chan)

/mob/proc/set_sound_channel_volume(channel, volume)
	var/sound/S = sound(null, FALSE, FALSE, channel, volume)
	S.status = SOUND_UPDATE
	src << S

/proc/get_rand_frequency()
	return rand(32000, 55000) //Frequency stuff only works with 45kbps oggs.

/client/proc/playtitlemusic()
	if(!SSticker || !SSmedia_tracks.lobby_tracks.len || !media)	return
	if(prefs?.read_preference(/datum/preference/toggle/play_lobby_music))
		var/datum/track/T = pick(SSmedia_tracks.lobby_tracks)
		media.push_music(T.url, world.time, 0.35)
		to_chat(src,span_notice("Lobby music: " + span_bold("[T.title]") + " by " + span_bold("[T.artist]") + "."))

//Are these even used?	//Yes
GLOBAL_LIST_INIT(keyboard_sound, list('sound/effects/keyboard/keyboard1.ogg','sound/effects/keyboard/keyboard2.ogg','sound/effects/keyboard/keyboard3.ogg', 'sound/effects/keyboard/keyboard4.ogg'))
GLOBAL_LIST_INIT(talk_sound, list('sound/talksounds/a.ogg','sound/talksounds/b.ogg','sound/talksounds/c.ogg','sound/talksounds/d.ogg','sound/talksounds/e.ogg','sound/talksounds/f.ogg','sound/talksounds/g.ogg','sound/talksounds/h.ogg'))

GLOBAL_LIST_INIT(wf_speak_lure_sound, list ('sound/talksounds/wf/lure_1.ogg', 'sound/talksounds/wf/lure_2.ogg', 'sound/talksounds/wf/lure_3.ogg', 'sound/talksounds/wf/lure_4.ogg', 'sound/talksounds/wf/lure_5.ogg'))
GLOBAL_LIST_INIT(wf_speak_lyst_sound, list ('sound/talksounds/wf/lyst_1.ogg', 'sound/talksounds/wf/lyst_2.ogg', 'sound/talksounds/wf/lyst_3.ogg', 'sound/talksounds/wf/lyst_4.ogg', 'sound/talksounds/wf/lyst_5.ogg', 'sound/talksounds/wf/lyst_6.ogg'))
GLOBAL_LIST_INIT(wf_speak_void_sound, list ('sound/talksounds/wf/void_1.ogg', 'sound/talksounds/wf/void_2.ogg', 'sound/talksounds/wf/void_3.ogg'))
GLOBAL_LIST_INIT(wf_speak_vomva_sound, list ('sound/talksounds/wf/vomva_1.ogg', 'sound/talksounds/wf/vomva_2.ogg', 'sound/talksounds/wf/vomva_3.ogg', 'sound/talksounds/wf/vomva_4.ogg'))

#define canine_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/scream/canine/wolf_scream.ogg', 'sound/voice/scream/canine/wolf_scream2.ogg', 'sound/voice/scream/canine/wolf_scream3.ogg', 'sound/voice/scream/canine/wolf_scream4.ogg', 'sound/voice/scream/canine/wolf_scream5.ogg', 'sound/voice/scream/canine/wolf_scream6.ogg'), "pain" = list('sound/voice/pain/canine/wolf_pain.ogg', 'sound/voice/pain/canine/wolf_pain2.ogg', 'sound/voice/pain/canine/wolf_pain3.ogg', 'sound/voice/pain/canine/wolf_pain4.ogg'), "gasp" = list('sound/voice/gasp/canine/wolf_gasp.ogg'), "death" = list('sound/voice/death/canine/wolf_death1.ogg', 'sound/voice/death/canine/wolf_death2.ogg', 'sound/voice/death/canine/wolf_death3.ogg', 'sound/voice/death/canine/wolf_death4.ogg', 'sound/voice/death/canine/wolf_death5.ogg'))
#define feline_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/scream/feline/feline_scream.ogg'), "pain" = list('sound/voice/pain/feline/feline_pain.ogg'), "gasp" = list('sound/voice/gasp/feline/feline_gasp.ogg'), "death" = list('sound/voice/death/feline/feline_death.ogg'))
#define cervine_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/scream/cervine/cervine_scream.ogg'), "pain" = null, "gasp" = null, "death" = list('sound/voice/death/cervine/cervine_death.ogg'))
#define robot_sounds list("cough" = list('sound/effects/mob_effects/m_machine_cougha.ogg', 'sound/effects/mob_effects/m_machine_coughb.ogg', 'sound/effects/mob_effects/m_machine_coughc.ogg'), "sneeze" = list('sound/effects/mob_effects/machine_sneeze.ogg'), "scream" = list('sound/voice/scream_silicon.ogg', 'sound/voice/android_scream.ogg', 'sound/voice/scream/robotic/robot_scream1.ogg', 'sound/voice/scream/robotic/robot_scream2.ogg', 'sound/voice/scream/robotic/robot_scream3.ogg'), "pain" = list('sound/voice/pain/robotic/robot_pain1.ogg', 'sound/voice/pain/robotic/robot_pain2.ogg', 'sound/voice/pain/robotic/robot_pain3.ogg'), "gasp" = null, "death" = list('sound/voice/borg_deathsound.ogg'))
#define male_generic_sounds list("cough" = list('sound/effects/mob_effects/m_cougha.ogg','sound/effects/mob_effects/m_coughb.ogg', 'sound/effects/mob_effects/m_coughc.ogg'), "sneeze" = list('sound/effects/mob_effects/sneeze.ogg'), "scream" = list('sound/voice/scream/generic/male/male_scream_1.ogg', 'sound/voice/scream/generic/male/male_scream_2.ogg', 'sound/voice/scream/generic/male/male_scream_3.ogg', 'sound/voice/scream/generic/male/male_scream_4.ogg', 'sound/voice/scream/generic/male/male_scream_5.ogg', 'sound/voice/scream/generic/male/male_scream_6.ogg'), "pain" = list('sound/voice/pain/generic/male/male_pain_1.ogg', 'sound/voice/pain/generic/male/male_pain_2.ogg', 'sound/voice/pain/generic/male/male_pain_3.ogg', 'sound/voice/pain/generic/male/male_pain_4.ogg', 'sound/voice/pain/generic/male/male_pain_5.ogg', 'sound/voice/pain/generic/male/male_pain_6.ogg', 'sound/voice/pain/generic/male/male_pain_7.ogg', 'sound/voice/pain/generic/male/male_pain_8.ogg'), "gasp" = list('sound/voice/gasp/generic/male/male_gasp1.ogg', 'sound/voice/gasp/generic/male/male_gasp2.ogg', 'sound/voice/gasp/generic/male/male_gasp3.ogg'), "death" = list('sound/voice/death/generic/male/male_death_1.ogg', 'sound/voice/death/generic/male/male_death_2.ogg', 'sound/voice/death/generic/male/male_death_3.ogg', 'sound/voice/death/generic/male/male_death_4.ogg', 'sound/voice/death/generic/male/male_death_5.ogg', 'sound/voice/death/generic/male/male_death_6.ogg', 'sound/voice/death/generic/male/male_death_7.ogg'))
#define female_generic_sounds list("cough" = list('sound/effects/mob_effects/f_cougha.ogg','sound/effects/mob_effects/f_coughb.ogg'), "sneeze" = list('sound/effects/mob_effects/f_sneeze.ogg'), "scream" = list('sound/voice/scream/generic/female/female_scream_1.ogg', 'sound/voice/scream/generic/female/female_scream_2.ogg', 'sound/voice/scream/generic/female/female_scream_3.ogg', 'sound/voice/scream/generic/female/female_scream_4.ogg', 'sound/voice/scream/generic/female/female_scream_5.ogg'), "pain" = list('sound/voice/pain/generic/female/female_pain_1.ogg', 'sound/voice/pain/generic/female/female_pain_2.ogg', 'sound/voice/pain/generic/female/female_pain_3.ogg'), "gasp" = list('sound/voice/gasp/generic/female/female_gasp1.ogg', 'sound/voice/gasp/generic/female/female_gasp2.ogg'), "death" = list('sound/voice/death/generic/female/female_death_1.ogg', 'sound/voice/death/generic/female/female_death_2.ogg', 'sound/voice/death/generic/female/female_death_3.ogg', 'sound/voice/death/generic/female/female_death_4.ogg', 'sound/voice/death/generic/female/female_death_5.ogg', 'sound/voice/death/generic/female/female_death_6.ogg'))
#define spider_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/spiderchitter.ogg'), "pain" = list('sound/voice/spiderchitter.ogg'), "gasp" = null, "death" = list('sound/voice/death/spider/spider_death.ogg'))
#define mouse_sounds list("cough" = list('sound/effects/mouse_squeak.ogg'), "sneeze" = list('sound/effects/mouse_squeak.ogg'), "scream" = list('sound/effects/mouse_squeak_loud.ogg'), "pain" = list('sound/effects/mouse_squeak.ogg'), "gasp" = list('sound/effects/mouse_squeak.ogg'), "death" = list('sound/effects/mouse_squeak_loud.ogg'))
#define lizard_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/effects/mob_effects/una_scream1.ogg','sound/effects/mob_effects/una_scream2.ogg'), "pain" = list('sound/voice/pain/lizard/lizard_pain.ogg'), "gasp" = null, "death" = list('sound/voice/death/lizard/lizard_death.ogg'))
#define vox_sounds list("cough" = list('sound/voice/shriekcough.ogg'), "sneeze" = list('sound/voice/shrieksneeze.ogg'), "scream" = list('sound/voice/shriek1.ogg'), "pain" = list('sound/voice/shriek1.ogg'), "gasp" = null, "death" = null)
#define slime_sounds list("cough" = list('sound/effects/slime_squish.ogg'), "sneeze" = null, "scream" = null, "pain" = null, "gasp" = null, "death" = null)
#define xeno_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/effects/mob_effects/x_scream1.ogg','sound/effects/mob_effects/x_scream2.ogg','sound/effects/mob_effects/x_scream3.ogg'), "pain" = list('sound/voice/pain/xeno/alien_roar1.ogg', 'sound/voice/pain/xeno/alien_roar2.ogg', 'sound/voice/pain/xeno/alien_roar3.ogg', 'sound/voice/pain/xeno/alien_roar4.ogg', 'sound/voice/pain/xeno/alien_roar5.ogg', 'sound/voice/pain/xeno/alien_roar6.ogg', 'sound/voice/pain/xeno/alien_roar7.ogg', 'sound/voice/pain/xeno/alien_roar8.ogg', 'sound/voice/pain/xeno/alien_roar9.ogg', 'sound/voice/pain/xeno/alien_roar10.ogg', 'sound/voice/pain/xeno/alien_roar11.ogg', 'sound/voice/pain/xeno/alien_roar12.ogg'), "gasp" = list('sound/voice/gasp/xeno/alien_hiss1.ogg'), "death" = list('sound/voice/death/xeno/xeno_death.ogg', 'sound/voice/death/xeno/xeno_death2.ogg'))
#define teshari_sounds list("cough" = list('sound/effects/mob_effects/tesharicougha.ogg','sound/effects/mob_effects/tesharicoughb.ogg'), "sneeze" = list('sound/effects/mob_effects/tesharisneeze.ogg'), "scream" = list('sound/effects/mob_effects/teshariscream.ogg'), "pain" = null, "gasp" = null, "death" = null)
#define raccoon_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/raccoon.ogg'), "pain" = list('sound/voice/raccoon.ogg'), "gasp" = null, "death" = list('sound/voice/raccoon.ogg'))
#define metroid_sounds list("cough" = list('sound/metroid/metroid_cough.ogg'), "sneeze" = list('sound/metroid/metroid_sneeze.ogg'), "scream" = list('sound/metroid/metroid_scream.ogg'), "pain" = list('sound/metroid/metroidsee.ogg'), "gasp" = list('sound/metroid/metroid_gasp.ogg'), "death" = list('sound/metroid/metroiddeath.ogg'))
#define vulpine_sounds list("cough" = null, "sneeze" = null, "scream" = list('sound/voice/scream/vulpine/fox_yip1.ogg', 'sound/voice/scream/vulpine/fox_yip2.ogg', 'sound/voice/scream/vulpine/fox_yip3.ogg'), "pain" = list('sound/voice/pain/vulpine/fox_pain1.ogg', 'sound/voice/pain/vulpine/fox_pain2.ogg', 'sound/voice/pain/vulpine/fox_pain3.ogg', 'sound/voice/pain/vulpine/fox_pain4.ogg'), "gasp" = list('sound/voice/gasp/canine/wolf_gasp.ogg'), "death" = list('sound/voice/death/canine/wolf_death1.ogg', 'sound/voice/death/canine/wolf_death2.ogg', 'sound/voice/death/canine/wolf_death3.ogg', 'sound/voice/death/canine/wolf_death4.ogg', 'sound/voice/death/canine/wolf_death5.ogg'))
#define no_sounds list("cough" = null, "sneeze" = null, "scream" = null, "pain" = null, "gasp" = null, "death" = null)
#define use_default list("cough" = null, "sneeze" = null, "scream" = null, "pain" = null, "gasp" = null, "death" = null)
/*
 * TBD Sound Defines below
*/

// Not sure we even really need this
// var/list/species_sounds = list()

// Global list containing all of our sound options.
GLOBAL_LIST_INIT(species_sound_map, list(
	"Canine" = canine_sounds,
	"Cervine" = cervine_sounds,
	"Feline" = feline_sounds,
	"Human Male" = male_generic_sounds,
	"Human Female" = female_generic_sounds,
	"Lizard" = lizard_sounds,
	"Metroid" = metroid_sounds,
	"Mouse" = mouse_sounds,
	"Raccoon" = raccoon_sounds,
	"Robotic" = robot_sounds,
	"Slime" = slime_sounds,
	"Spider" = spider_sounds,
	"Teshari" = teshari_sounds,
	"Vox" = vox_sounds,
	"Vulpine" = vulpine_sounds,
	"Xeno" = xeno_sounds,
	"None" = no_sounds,
	"Unset" = use_default
))

/*
 * Call this for when you need a sound from an already-identified list - IE, "Canine". pick() cannot parse procs.
 * Indexes must be pre-calculated by the time it reaches here - for instance;
 * var/mob/living/M = user
 * get_species_sound(M.client.pref.species_sound)["scream"] will return get_species_sound("Robotic")["scream"]
 * This can be paired with get_gendered_sound, like so: get_species_sound(get_gendered_sound(M))["emote"] <- get_gendered_sound will return whatever we have of the 3 valid options, and then get_species_sound will match that to the actual sound list.
 * The get_species_sound proc will retrieve and return the list based on the key given - get_species_sound("Robotic")["scream"] will return list('sound/voice/scream_silicon.ogg', 'sound/voice/android_scream.ogg', etc)
 * If you are adding new calls of this, follow the syntax of get_species_sound(species)["scream"] - you must attach ["emote"] to the end, outside the ()
 * If your species has a gendered sound, DON'T PANIC. Simply set the gender_specific_species_sounds var on the species to true, and when you call this, do it like so:
 * get_species_sound(H.species.species_sounds_male)["emote"] // If we're male, and want an emote sound gendered correctly.
*/
/proc/get_species_sound(sounds)
	if(!islist(GLOB.species_sound_map[sounds])) // We check here if this list actually has anything in it, or if we're about to return a null index
		return null // Shitty failsafe but better than rewriting an entire litany of procs rn when I'm low on time - Rykka // list('sound/voice/silence.ogg')
	return GLOB.species_sound_map[sounds] // Otherwise, successfully return our sound

/*
 * The following helper proc will select a species' default sounds - useful for if we're set to "Unset"
 * This is ONLY called by Unset, meaning we haven't chosen a species sound.
*/
/proc/select_default_species_sound(datum/preferences/pref) // Called in character setup. This is similar to check_gendered_sounds, except here we pull from the prefs.
	// First, we determine if we're custom-choosing a body or if we're a base game species.
	var/pref_species = pref.read_preference(/datum/preference/choiced/species)
	var/datum/species/valid = GLOB.all_species[pref_species]
	if(valid.selects_bodytype == SELECTS_BODYTYPE_CUSTOM || valid.selects_bodytype == SELECTS_BODYTYPE_SHAPESHIFTER) // Custom species or xenochimera handling here
		valid = GLOB.all_species[pref.read_preference(/datum/preference/text/human/custom_base)] || GLOB.all_species[pref_species] // migrated pref
	// Now we start getting our sounds.
	var/id_gender = pref.read_preference(/datum/preference/choiced/gender/identifying)
	if(valid.gender_specific_species_sounds) // Do we have gender-specific sounds?
		if(id_gender == FEMALE && valid.species_sounds_female)
			return valid.species_sounds_female
		else if(id_gender == MALE && valid.species_sounds_male)
			return valid.species_sounds_male
		else // Failsafe. Update if there's ever gendered sounds for HERM/Neuter/etc
			return valid.species_sounds
	else
		return valid.species_sounds

/proc/get_gendered_sound(mob/living/user) // Called anywhere we need gender-specific species sounds. Gets the gender-specific sound if one exists, but otherwise, will return the species-generic sound list.
	var/mob/living/carbon/human/H = user
	if(ishuman(H))
		if(H.species.gender_specific_species_sounds) // Do we have gender-specific sounds?
			if(H.identifying_gender == FEMALE && H.species.species_sounds_female)
				return H.species.species_sounds_female
			else if(H.identifying_gender == MALE && H.species.species_sounds_male)
				return H.species.species_sounds_male
			else // Failsafe. Update if there's ever gendered sounds for HERM/Neuter/etc
				return H.species.species_sounds
		else
			return H.species.species_sounds
	else
		return user.species_sounds
