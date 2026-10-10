//Non-Canon on Virgo. Used downstream.
// The 60-second channel is the op's wait(); the portal only deploys, the one-time flag only sets and the energy only spends in the effect,
// all together, after the channel finishes AND every requirement (including "not already built one") still holds. The op is part of the
// shadekin_dark capability (dark_maw.dm).

/// The channel begins: the smoke and the announcement the legacy pay step made.
/mob/living/proc/ability_dark_tunnel_begins(datum/act/op/A)
	var/turf/T = get_turf(src)
	if(!T)
		return /datum/msg/shadekin_ability/no_turf
	var/datum/effect/effect/system/smoke_spread/smoke = new()
	smoke.attach(T)
	smoke.set_up(10, 0, T)
	smoke.start()
	act_message(src, null, others = span_notice("%U% begins pulling dark energies around themselves."))

/mob/living/proc/ability_no_dark_tunnel_yet(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return (!!SK && !SK.created_dark_tunnel) ? null : /datum/msg/req_failed

/// Checks the deploy site (dq_dark_tunnel_template()'s check_deploy()) without side effects.
/mob/living/proc/ability_dark_tunnel_site_ready(datum/act/op/A)
	var/turf/T = get_turf(src)
	if(!T)
		return /datum/msg/req_failed
	var/datum/map_template/shelter/template = dq_dark_tunnel_template()
	return (template.check_deploy(T) == SHELTER_DEPLOY_ALLOWED) ? null : /datum/msg/req_failed

/// Why the site is not ready: it varies by what's wrong with it.
/mob/living/proc/ability_dark_tunnel_site_text(datum/act/op/A)
	var/turf/T = get_turf(src)
	if(!T)
		return "you can't use that here"
	var/datum/map_template/shelter/template = dq_dark_tunnel_template()
	switch(template.check_deploy(T))
		if(SHELTER_DEPLOY_BAD_AREA)
			return "a tunnel to the Dark will not function in this area"
		if(SHELTER_DEPLOY_BAD_TURFS, SHELTER_DEPLOY_ANCHORED_OBJECTS)
			return "there is not enough open area for a tunnel to the Dark to form (needs [template.width]x[template.height])"
	return "you can't do that here"

/mob/living/proc/ability_can_afford_dark_tunnel(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	return (!!SK && SK.shadekin_get_energy() >= DARK_TUNNEL_COST) ? null : /datum/msg/req_failed

/// The dark_portal shelter template, loaded once and cached.
/proc/dq_dark_tunnel_template()
	var/static/datum/map_template/shelter/template
	if(!template)
		template = SSmapping.shelter_templates["dark_portal"]
		if(!template)
			throw EXCEPTION("Shelter template (dark_portal) not found!")
	return template

/mob/living/proc/ability_dark_tunneling(datum/act/op/A)
	var/datum/shadekin/SK = get_shadekin_state()
	if(!SK)
		return OP_FAILED
	var/turf/T = get_turf(src)
	if(!T)
		return OP_FAILED
	var/datum/map_template/shelter/template = dq_dark_tunnel_template()
	play_sfx(src, SFX_EFFECTS_PHASEIN)
	act_message(src, null, others = span_notice("%U% finishes pulling dark energies around themselves, creating a portal."))
	log_and_message_admins("[key_name_admin(src)] created a tunnel to the dark at [get_area(T)]!")
	template.annihilate_plants(T)
	template.load_async(T, TRUE, TYPE_PROC_REF(/datum/map_template/shelter, shelter_loaded), template, list(T.x, T.y, T.z))
	SK.created_dark_tunnel = TRUE
	SK.shadekin_adjust_energy(-(DARK_TUNNEL_COST - 10)) //Leaving enough energy to actually activate the portal
	return OP_OK

/datum/map_template/shelter/dark_portal
	name = "Dark Portal"
	shelter_id = "dark_portal"
	description = "A portal to a section of the Dark"
	mappath = "maps/submaps/shelters/dark_portal.dmm"

/datum/map_template/shelter/dark_portal/New()
	. = ..()
	blacklisted_turfs = typecacheof(list(/turf/unsimulated))
	GLOB.blacklisted_areas = typecacheof(list(/area/centcom, /area/shadekin))
