/**********************Resonator**********************/

/obj/item/resonator
	name = "resonator"
	icon = 'icons/obj/mining.dmi'
	icon_state = "resonator"
	item_state = "resonator"
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_vr.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_vr.dmi',
		)
	desc = "A handheld device that creates small fields of energy that resonate until they detonate, crushing rock. It can also be activated without a target to create a field at the user's location, to act as a delayed time trap. It's more effective in low temperature."
	w_class = ITEMSIZE_NORMAL
	force = 8
	throwforce = 10
	var/cooldown = 0
	var/fieldsactive = 0
	var/burst_time = 5 SECONDS
	var/fieldlimit = 3
	var/spreadmode = 0
	var/cascading  = 0

/obj/item/resonator/upgraded
	name = "upgraded resonator"
	desc = "An upgraded version of the resonator that can produce more fields at once."
	icon_state = "resonator_u"
	fieldlimit = 5

/obj/item/resonator/proc/CreateResonance(target, creator)
	var/turf/T = get_turf(target)
	if(locate_on(T, /obj/effect/resonance))
		return

	if(fieldsactive > fieldlimit || cascading)
		to_chat(creator, span_warning("You've exceeded the field limit! Wait for them to dissipate."))
		return
	if(spreadmode)
		set_cascading(TRUE)
		var/depth = 0
		var/fields = 0
		if(depth == 0)
			play_sfx(src, SFX_WEAPONS_RESONATOR_FIRE)
			new /obj/effect/resonance(T, creator, burst_time)
			fields++
			depth++
		var/origin_dir = get_cardinal_dir(creator, T)
		var/dir
		while(fields < fieldlimit)
			for(var/i=0, i<=2, i++)
				if(fields >= fieldlimit)
					after(src, burst_time, PROC_REF(end_cascade))
					return
				switch(i) //Using a switch statement rather than (-90 + i * 90) to favour going straight ahead
					if(0)
						dir = origin_dir
					if(1)
						dir = turn(origin_dir, 90)
					if(2)
						dir = turn(origin_dir, -90)
				var/turf/newT = T
				for(var/step = 1, step<=depth, step++)
					var/turf/oldT = newT
					newT = get_step(oldT, dir)
					if(step == depth)
						new /obj/effect/resonance(newT, creator, burst_time)
						fields++
						if(depth > 1 && fields < fieldlimit) //Works until 15 fieldlimit.
							oldT = newT
							dir = turn(dir, (i == 2 ? 135 : -135))
							newT = get_step(oldT, dir)
							new /obj/effect/resonance(newT, creator, burst_time)
							fields++
			depth++



	else
		play_sfx(src, SFX_WEAPONS_RESONATOR_FIRE)
		new /obj/effect/resonance(T, creator, burst_time)
		set_fieldsactive(fieldsactive + 1)
		after(src, burst_time, PROC_REF(field_burst))

TRACKED(/obj/item/resonator, burst_time)
TRACKED(/obj/item/resonator, spreadmode)
TRACKED(/obj/item/resonator, fieldsactive)
TRACKED(/obj/item/resonator, cascading)
TRACKED(/obj/item/resonator, fieldlimit)

CAPABILITIES(/obj/item/resonator)
	op("settings", in_hand(), label("Settings"),
		asks(/datum/prompt/choice, keeps = 0, fields = list("timeout" = 0, "question" = "Change Detonation Time or toggle Cascading?", "title" = "Setting", "choices" = list("Toggle Cascade", "Resonance Time"))),
		then(PROC_REF(settings_picked)))
	op("resonate", at_target(), priority(OP_PRIORITY_PART), answers(INTENT_USE, INTENT_ATTACK), label("Create resonance field"),
		needs(req_adjacent(), req(PROC_REF(resonance_allowed), because = PROC_REF(resonance_refusal))), then(PROC_REF(resonated)))

/obj/item/resonator/proc/settings_picked(datum/act/op/A)
	var/datum/prompt/choice/picked = A.answer
	switch(picked.value)
		if("Resonance Time")
			if(burst_time == 5 SECONDS)
				set_burst_time(3 SECONDS)
				to_chat(A.actor, span_info("You set the resonator's fields to detonate after 3 seconds."))
			else
				set_burst_time(5 SECONDS)
				to_chat(A.actor, span_info("You set the resonator's fields to detonate after 5 seconds."))
		if("Toggle Cascade")
			set_spreadmode(!spreadmode)
			to_chat(A.actor, span_info("You have [(spreadmode ? "enabled" : "disabled")] the resonance cascade mode."))
	return OP_OK

/obj/item/resonator/proc/resonance_allowed(datum/act/op/A)
	return isnull(resonance_refusal(A))

/// These native location queries are checked before instant creation; this operation never waits or prompts.
/obj/item/resonator/proc/resonance_refusal(datum/act/op/A)
	var/atom/target = A.target
	if(!target || (src in target))
		return MSG(op/not_available)
	if(!isturf(target) && !isturf(target.loc)) // ALLOW(reads): native location is queried immediately before instant field creation with no wait or prompt
		return MSG(op/not_available)
	var/turf/T = get_turf(target)
	if(length(turf_contents_of_type(T, /obj/effect/resonance)))
		return MSG(op/not_available)
	if(fieldsactive > fieldlimit || cascading)
		return span_warning("You've exceeded the field limit! Wait for them to dissipate.")
	return null

/obj/item/resonator/proc/resonated(datum/act/op/A)
	CreateResonance(A.target, A.actor)
	return OP_OK

/obj/effect/resonance
	name = "resonance field"
	desc = "A resonating field that significantly damages anything inside of it when the field eventually ruptures."
	icon = 'icons/effects/effects.dmi'
	icon_state = "shield1"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	mouse_opacity = 0
	var/resonance_damage = 20
	/// Relation view: who made the field (for attack logs); null once they are gone.
	var/tmp/mob/creator

CAPABILITIES(/obj/effect/resonance)
	param(nameof(creator), pos = 1)
	param(nameof(timetoburst), pos = 2, apply = PROC_REF(charge))

/// How long the field takes to burst (its constructor param).
/obj/effect/resonance/var/timetoburst = 0

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The field grows until it bursts.
/obj/effect/resonance/proc/charge(delay)
	// Start small and grow to big size as we are about to burst
	transform = matrix()*0.75
	animate(src, transform = matrix()*1.5, time = delay)
	after(src, delay, PROC_REF(burst))

/obj/effect/resonance/proc/burst()
	var/turf/T = get_turf(src)
	if(!T)
		return
	play_sfx(src, SFX_WEAPONS_RESONATOR_BLAST, 0.5, extrarange = 0)
	// Make the collapsing effect
	new /obj/effect/temp_visual/resonance_crush(T)

	// Mineral turfs get drilled!
	if(ismineralturf(T))
		var/turf/simulated/mineral/M = T
		M.GetDrilled()
		consume(src)
		return
	// Otherwise we damage mobs!  Boost damage if low tempreature
	var/datum/gas_mixture/environment = T.return_air()
	if(environment.return_temperature() < 250)
		name = "strong resonance field"
		resonance_damage = 50

	for(var/mob/living/L in src.loc)
		if(creator)
			add_attack_logs(creator, L, "used a resonator field on")
		to_chat(L, span_danger("\The [src] ruptured with you in it!"))
		L.injure(INJURY_BLUNT, resonance_damage, null, src)
	consume(src)


/obj/effect/temp_visual/resonance_crush
	icon_state = "shield1"
	plane = MOB_PLANE
	layer = ABOVE_MOB_LAYER
	duration = 0.4 SECONDS

/obj/effect/temp_visual/resonance_crush/Initialize(mapload)
	. = ..()
	transform = matrix()*1.5
	animate(src, transform = matrix()*0.1, alpha = 50, time = 0.4 SECONDS)

/obj/item/resonator/proc/end_cascade()
	set_cascading(FALSE)

/obj/item/resonator/proc/field_burst()
	set_fieldsactive(fieldsactive - 1)
