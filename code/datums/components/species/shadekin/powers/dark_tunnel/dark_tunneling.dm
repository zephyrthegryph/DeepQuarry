//Non-Canon on Virgo. Used downstream.
// Ported to the ability framework (doc/rewrite/rules.md §5). The 60-second
// channel is the ability's time cost (pay_cost()); the portal only deploys,
// the one-time flag only sets and the energy only spends in the effect, all
// together, after the channel finishes AND every requirement (including
// "not already built one") still holds - the same "commit only once, all at
// once" shape do_after() gave the legacy verb, just made structural.

/datum/interaction/ability/self/shadekin_dark_tunneling
	id = ABILITY_ID_SHADEKIN_DARK_TUNNELING
	name = "Dark tunneling"
	category = ABILITY_CAT_UTILITY
	requires = list(
		REQ_CONSCIOUS,
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_vr, "the VR systems cannot comprehend this power"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_shadekin, "you aren't shadekin"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_not_shifted, "you can't use that while phase shifted"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_no_dark_tunnel_yet, "you have already made a tunnel to the Dark"),
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_dark_tunnel_site_ready, null), // reason varies by what's wrong with the site
		REQ_ON(PRED_ACTOR, /mob/living/proc/dq_pred_dark_tunnel_afford, "not enough energy for that ability"),
	)
	effect = /mob/living/proc/dq_do_dark_tunneling

/datum/interaction/ability/self/shadekin_dark_tunneling/pay_cost(mob/actor, atom/target, obj/item/held)
	var/turf/T = get_turf(actor)
	if(!T)
		return FALSE
	var/datum/effect/effect/system/smoke_spread/smoke = new()
	smoke.attach(T)
	smoke.set_up(10, 0, T)
	smoke.start()
	actor.visible_message(span_notice("[actor] begins pulling dark energies around themselves."))
	return do_after(actor, DARK_TUNNEL_CHANNEL_TIME, target = actor)

/mob/living/proc/dq_pred_no_dark_tunnel_yet(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return !SK.created_dark_tunnel || "you have already made a tunnel to the Dark"

/// Checks the deploy site (dq_dark_tunnel_template()'s check_deploy()) without side effects.
/mob/living/proc/dq_pred_dark_tunnel_site_ready(mob/living/actor, atom/target, obj/item/held)
	var/datum/map_template/shelter/template = dq_dark_tunnel_template()
	var/turf/T = get_turf(actor)
	if(!T)
		return "you can't use that here"
	switch(template.check_deploy(T))
		if(SHELTER_DEPLOY_ALLOWED)
			return TRUE
		if(SHELTER_DEPLOY_BAD_AREA)
			return "a tunnel to the Dark will not function in this area"
		if(SHELTER_DEPLOY_BAD_TURFS, SHELTER_DEPLOY_ANCHORED_OBJECTS)
			return "there is not enough open area for a tunnel to the Dark to form (needs [template.width]x[template.height])"
	return "you can't do that here"

/mob/living/proc/dq_pred_dark_tunnel_afford(mob/living/actor, atom/target, obj/item/held)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return "you aren't shadekin"
	return (SK.shadekin_get_energy() >= DARK_TUNNEL_COST) || "not enough energy for that ability"

/// The dark_portal shelter template, loaded once and cached.
/proc/dq_dark_tunnel_template()
	var/static/datum/map_template/shelter/template
	if(!template)
		template = SSmapping.shelter_templates["dark_portal"]
		if(!template)
			throw EXCEPTION("Shelter template (dark_portal) not found!")
	return template

/mob/living/proc/dq_do_dark_tunneling(mob/living/actor, obj/item/held, datum/interaction/ability/interaction)
	var/datum/component/shadekin/SK = actor.get_shadekin_component()
	if(!SK)
		return FALSE
	var/turf/T = get_turf(actor)
	if(!T)
		return FALSE
	var/datum/map_template/shelter/template = dq_dark_tunnel_template()
	playsound(actor, 'sound/effects/phasein.ogg', 100, 1)
	actor.visible_message(span_notice("[actor] finishes pulling dark energies around themselves, creating a portal."))
	log_and_message_admins("[key_name_admin(actor)] created a tunnel to the dark at [get_area(T)]!")
	template.annihilate_plants(T)
	template.load(T, centered = TRUE)
	template.update_lighting(T)
	SK.created_dark_tunnel = TRUE
	SK.shadekin_adjust_energy(-(DARK_TUNNEL_COST - 10)) //Leaving enough energy to actually activate the portal
	return TRUE

/datum/map_template/shelter/dark_portal
	name = "Dark Portal"
	shelter_id = "dark_portal"
	description = "A portal to a section of the Dark"
	mappath = "maps/submaps/shelters/dark_portal.dmm"

/datum/map_template/shelter/dark_portal/New()
	. = ..()
	blacklisted_turfs = typecacheof(list(/turf/unsimulated))
	GLOB.blacklisted_areas = typecacheof(list(/area/centcom, /area/shadekin))
