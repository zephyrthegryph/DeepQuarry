#define SHOULD_DISABLE_FOOTSTEPS(source)

///Footstep behaviour (was /datum/element/footstep). Plays footsteps at the mob's location
///when it is appropriate. A capability hooked on the moved notice; the per-mob settings and step
///counter use a type trait and a sparse per-mob slot. L.enable_footsteps() grants it.
CAPABILITY_TYPE(footstep, CAP_FOOTSTEP, /datum/capability/footstep, key = NONE)
/datum/capability/footstep

/datum/capability/footstep/entries()
	return list(on_notice(/datum/notice/moved, then(CAP_PROC(footstep_moved))))

#define ENTRY_FOOTSTEP_SETTINGS "footstep_settings"
#define FOOTSTEP_SETTINGS_KEY "footstep_settings"

STATIC_ENTRY(footstep_settings)
/proc/footstep_settings(sound_type = null, volume = null, e_range = null, vary = null)
	RETURN_TYPE(/datum/entry)
	return entry_make(ENTRY_FOOTSTEP_SETTINGS, null, list("sound_type" = sound_type, "volume" = volume, "e_range" = e_range, "vary" = vary))

/datum/type_trait/footstep_settings
	var/sound_type = FOOTSTEP_MOB_BAREFOOT
	var/volume = 0.1
	var/e_range = -8
	var/vary = FALSE

/datum/type_trait/footstep_settings/copy_values(datum/type_trait/footstep_settings/into)
	into.sound_type = sound_type
	into.volume = volume
	into.e_range = e_range
	into.vary = vary

/datum/entry_engine/type_trait/footstep_settings
	kind = ENTRY_FOOTSTEP_SETTINGS
	trait_type = /datum/type_trait/footstep_settings
	publish_key = FOOTSTEP_SETTINGS_KEY
	base_type = /mob/living
	var_names = list("footstep_type" = "sound_type", "footstep_volume" = "volume", "footstep_e_range" = "e_range", "footstep_vary" = "vary")

READS_AS(/proc/footstep_settings_of, FOOTSTEP_SETTINGS_KEY)
/proc/footstep_settings_of(mob/living/holder) as /datum/type_trait/footstep_settings
	READS_FROM(holder)
	return type_trait_of(holder, ENTRY_FOOTSTEP_SETTINGS)

sparse(/mob/living, footstep_steps, type = num)

/mob/living/proc/enable_footsteps(type = FOOTSTEP_MOB_BAREFOOT, volume = 0.1, e_range = -8, vary = FALSE)
	set_trait(src, ENTRY_FOOTSTEP_SETTINGS, "sound_type", type)
	set_trait(src, ENTRY_FOOTSTEP_SETTINGS, "volume", volume)
	set_trait(src, ENTRY_FOOTSTEP_SETTINGS, "e_range", e_range)
	set_trait(src, ENTRY_FOOTSTEP_SETTINGS, "vary", vary)
	sparse_set(src, footstep_steps, null)
	grant(src, /datum/capability/footstep, src)

/mob/living/proc/disable_footsteps()
	revoke(src, /datum/capability/footstep, src)

/datum/capability/footstep/proc/footstep_moved(datum/act/A)
	var/mob/living/source = A.holder
	if(ishuman(source))
		play_humanstep(source)
	else
		play_simplestep(source)

/datum/capability/footstep/proc/check_footstep_type(footstep_type)
	var/footstep_ret
	switch(footstep_type)
		if(FOOTSTEP_MOB_TESHARI)
			footstep_ret = GLOB.lightclawfootstep
		if(FOOTSTEP_MOB_CLAW)
			footstep_ret = GLOB.clawfootstep
		if(FOOTSTEP_MOB_HEAVY)
			footstep_ret = GLOB.heavyfootstep
		if(FOOTSTEP_MOB_SHOE)
			footstep_ret = GLOB.footstep
		if(FOOTSTEP_MOB_SLIME)
			footstep_ret = GLOB.slimefootstep
		if(FOOTSTEP_MOB_SLITHER)
			footstep_ret = GLOB.slitherfootstep
		if(FOOTSTEP_MOB_HEAVY_ALT)
			footstep_ret = GLOB.heavyaltfootstep
		if(FOOTSTEP_MOB_MECHY)
			footstep_ret = GLOB.mechfootstep
		else
			footstep_ret = GLOB.barefootstep
	return footstep_ret

///Prepares a footstep for living mobs. Determines if it should get played. Returns the turf it should get played on. Note that it is always a /turf/simulated
/datum/capability/footstep/proc/prepare_step(mob/living/source)
	var/volume = footstep_settings_of(source).volume
	var/sound_vary = footstep_settings_of(source).vary
	var/turf/simulated/turf = get_turf(source)
	if(!istype(turf))
		return

	if(source.is_incorporeal())
		return

	if(source?.buckled_to() || source.throwing || source.movement_type & (source.is_ventcrawling | stat_value(source, STAT_FLYING)))
		return

	if(source.lying) //play crawling sound if we're lying
		if(turf.footstep)
			play_sfx(turf, SFX_EFFECTS_FOOTSTEP_CRAWL1, volume = 15 * volume, vary = sound_vary)
		return

	if(iscarbon(source))
		var/mob/living/carbon/carbon_source = source
		if(!carbon_source.get_organ(BP_L_LEG) && !carbon_source.get_organ(BP_R_LEG))
			return
		if(carbon_source.m_intent == I_WALK)
			return// stealth
	sparse_set_or(source, footstep_steps, sparse_get_or(source, footstep_steps, 0) + 1, 0)
	var/steps = sparse_get_or(source, footstep_steps, 0)

	if(steps >= 6)
		sparse_set(source, footstep_steps, null)
		steps = 0

	if(steps % 2)
		return

	if(steps != 0 && !get_gravity(source)) // don't need to step as often when you hop around
		return

	. = list(
		FOOTSTEP_MOB_SHOE = turf.footstep,
		FOOTSTEP_MOB_BAREFOOT = turf.barefootstep,
		FOOTSTEP_MOB_HEAVY = turf.heavyfootstep,
		FOOTSTEP_MOB_CLAW = turf.clawfootstep,
		STEP_SOUND_PRIORITY = STEP_SOUND_NO_PRIORITY
		)

	//The turf has no footstep sound (e.g. open space)
	if(isnull(turf.footstep))
		return null
	return .

/datum/capability/footstep/proc/play_simplestep(mob/living/source)
	var/volume = footstep_settings_of(source).volume
	var/e_range = footstep_settings_of(source).e_range
	var/sound_vary = footstep_settings_of(source).vary
	var/footstep_type = footstep_settings_of(source).sound_type
	var/footstep_sounds = check_footstep_type(footstep_type)

	var/volume_multiplier = 0.3

	if(!isturf(source.loc))
		return

	var/list/prepared_steps = prepare_step(source)
	if(isnull(prepared_steps))
		return

	if(isfile(footstep_sounds) || istext(footstep_sounds))
		playsound(source.loc, footstep_sounds, volume * volume_multiplier, falloff = 1, vary = sound_vary)
		return

	var/turf_footstep = prepared_steps[footstep_type]
	if(isnull(turf_footstep) || !footstep_sounds[turf_footstep])
		return
	playsound(source.loc, pick(footstep_sounds[turf_footstep][1]), footstep_sounds[turf_footstep][2] * volume, TRUE, footstep_sounds[turf_footstep][3] + e_range, falloff = 1, vary = sound_vary)

/datum/capability/footstep/proc/play_humanstep(mob/living/carbon/human/source)
	var/volume = footstep_settings_of(source).volume
	var/e_range = footstep_settings_of(source).e_range
	var/sound_vary = footstep_settings_of(source).vary

	var/volume_multiplier = 0.3
	var/range_adjustment = 0

	var/list/prepared_steps = prepare_step(source)
	if(isnull(prepared_steps))
		return

	if (source.client?.prefs?.read_preference(/datum/preference/toggle/human/ignore_shoes))
		play_barefoot_sound(source, prepared_steps, volume_multiplier, range_adjustment)
		return

	//cache for sanic speed (lists are references anyways)
	var/footstep_sounds = GLOB.footstep

	if ( istype(source.get_equipped_item(SLOT_ID_SHOES), /obj/item/clothing/shoes) || ( source.get_equipped_item(SLOT_ID_SUIT) && (worn_of(source.get_equipped_item(SLOT_ID_SUIT)).covers & FEET) ) )
		// we are wearing shoes

		var/obj/item/clothing/shoes/feet = source.get_equipped_item(SLOT_ID_SHOES)
		if(istype(feet) && feet.blocks_footsteps)
			var/shoestep_type = prepared_steps[FOOTSTEP_MOB_SHOE]
			if(!isnull(shoestep_type) && footstep_sounds[shoestep_type]) // shoestep type can be null
				playsound(source.loc, pick(footstep_sounds[shoestep_type][1]),
					footstep_sounds[shoestep_type][2] * volume * volume_multiplier,
					TRUE,
					footstep_sounds[shoestep_type][3] + e_range + range_adjustment, falloff = 1, vary = sound_vary)
				return

	// we are barefoot
	play_barefoot_sound(source, prepared_steps, volume_multiplier, range_adjustment)

/datum/capability/footstep/proc/play_barefoot_sound(mob/living/carbon/human/source, list/prepared_steps, volume_multiplier, range_adjustment)
	var/volume = footstep_settings_of(source).volume
	var/e_range = footstep_settings_of(source).e_range
	var/sound_vary = footstep_settings_of(source).vary

	if(source.species.special_step_sounds)
		playsound(source.loc, pick(source.species.special_step_sounds), volume, TRUE, falloff = 1, vary = sound_vary)
		return

	var/barefoot_type = prepared_steps[FOOTSTEP_MOB_BAREFOOT]
	var/bare_footstep_sounds
	if(source.custom_footstep != FOOTSTEP_MOB_HUMAN)
		bare_footstep_sounds = check_footstep_type(source.custom_footstep)
	else
		bare_footstep_sounds = GLOB.barefootstep

	if(!isnull(barefoot_type) && bare_footstep_sounds[barefoot_type]) // barefoot_type can be null
		playsound(source.loc, pick(bare_footstep_sounds[barefoot_type][1]),
			bare_footstep_sounds[barefoot_type][2] * volume * volume_multiplier,
			TRUE,
			bare_footstep_sounds[barefoot_type][3] + e_range + range_adjustment, falloff = 1, vary = sound_vary)

#undef SHOULD_DISABLE_FOOTSTEPS
