#define DRYING_TIME 5 MINUTES                        //for 1 unit of depth in puddle (amount var)

/obj/effect/decal/cleanable/blood
	name = "blood"
	var/dryname = "dried blood"
	desc = "It's thick and gooey. Perhaps it's the chef's cooking?"
	var/drydesc = "It's dry and crusty. Someone is not doing their job."
	gender = PLURAL
	density = FALSE
	anchored = TRUE
	plane = BLOOD_PLANE
	layer = BLOOD_DECAL_LAYER
	icon = 'icons/effects/blood.dmi'
	icon_state = "mfloor1"
	random_icon_states = list("mfloor1", "mfloor2", "mfloor3", "mfloor4", "mfloor5", "mfloor6", "mfloor7")
	var/base_icon = 'icons/effects/blood.dmi'
	var/basecolor="#A10808" // Color when wet.
	var/synthblood = 0
	var/amount = 5
	generic_filth = TRUE
	persistent = FALSE
	var/delete_me = FALSE

/obj/effect/decal/cleanable/blood/reveal_blood()
	if(!dq_get_fluorescent(src))
		dq_set_fluorescent(src, 1)
		basecolor = COLOR_LUMINOL
		update_icon()

/obj/effect/decal/cleanable/blood/wash(clean_types)
	. = ..()
	dq_set_fluorescent(src, 0)
	if(invisibility != INVISIBILITY_MAXIMUM)
		invisibility = INVISIBILITY_MAXIMUM
		amount = 0

/obj/effect/decal/cleanable/blood/Initialize(mapload, _age)
	. = ..()
	if(delete_me)
		return INITIALIZE_HINT_QDEL
	update_icon()
	if(!mapload)
		after(src, DRYING_TIME * (amount+1), PROC_REF(dry))
	if(istype(src, /obj/effect/decal/cleanable/blood/gibs))
		return
	if(src.type == /obj/effect/decal/cleanable/blood)
		if(src.loc && isturf(src.loc))
			for(var/obj/effect/decal/cleanable/blood/B in src.loc)
				if(B != src)
					init_forensic_data().merge_blooddna(B.forensic_data)
					if(!(B.flags & ATOM_INITIALIZED))
						B.delete_me = TRUE
					else
						consume(B)

DECLARE_APPEARANCE_PROC(/obj/effect/decal/cleanable/blood, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/effect/decal/cleanable/blood/appearance_overlays()
	if(basecolor == "rainbow") basecolor = get_random_colour(1)
	. = list()
	color = basecolor

	if(basecolor == SYNTH_BLOOD_COLOUR)
		name = "oil"
		desc = "It's quite oily."
	else if(synthblood)
		name = "synthetic blood"
		desc = "It's quite greasy."
	else
		name = initial(name)
		desc = initial(desc)
	. += add_janitor_hud_overlay()

/obj/effect/decal/cleanable/blood/Crossed(mob/living/carbon/human/perp)
	if(perp.is_incorporeal())
		return
	if(!istype(perp))
		return
	if(perp.flying || dq_get_hovering(perp) || perp.is_floating) //if the perp isn't on the ground, they shouldn't be affected by the stuff on the floor.
		return
	if(amount < 1)
		return

	var/obj/item/organ/external/l_foot = perp.get_organ(BP_L_FOOT)
	var/obj/item/organ/external/r_foot = perp.get_organ(BP_R_FOOT)
	var/hasfeet = 1
	if((!l_foot || l_foot.is_stump()) && (!r_foot || r_foot.is_stump()))
		hasfeet = 0
	if(perp.get_equipped_item(SLOT_ID_SHOES) && !perp?.buckled_to())//Adding blood to shoes
		var/obj/item/clothing/shoes/S = perp.get_equipped_item(SLOT_ID_SHOES)
		if(istype(S))
			dq_set_blood_color(S, basecolor)
			S.track_blood = max(amount,S.track_blood)
			S.update_icon() // Cut previous overlays
			if(!S.blood_overlay)
				S.generate_blood_overlay()
			if(!forensic_data?.has_blooddna())
				S.blood_overlay.color = basecolor
				S.add_overlay(S.blood_overlay)
			if(S.blood_overlay && S.blood_overlay.color != basecolor)
				S.blood_overlay.color = basecolor
				S.add_overlay(S.blood_overlay)
			transfer_blooddna_to(S)
			perp.update_inv_shoes()

	else if (hasfeet)//Or feet
		perp.feet_blood_color = basecolor
		perp.track_blood = max(amount,perp.track_blood)
		LAZYINITLIST(perp.feet_blood_DNA)
		perp.feet_blood_DNA |= init_forensic_data().get_blooddna().Copy()
		perp.update_bloodied()
	else if (perp?.buckled_to() && istype(perp?.buckled_to(), /obj/structure/bed/chair/wheelchair))
		var/obj/structure/bed/chair/wheelchair/W = perp?.buckled_to()
		W.bloodiness = 4

	if(viruses)
		for(var/datum/affliction/contagion/D in viruses)
			if(D.IsSpreadByTouch())
				perp.expose_contagion(D, BP_R_FOOT)

	amount--

/obj/effect/decal/cleanable/blood/proc/dry()
	name = dryname
	desc = drydesc
	color = adjust_brightness(color, -50)
	amount = 0

CAPABILITIES(/obj/effect/decal/cleanable/blood)
	op("touch_blood", hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_touch_blood)))

/// Old attack_hand: bare hands pick up some of the blood (and any touch-spread disease).
/obj/effect/decal/cleanable/blood/proc/interaction_touch_blood(datum/act/op/A)
	var/mob/living/carbon/human/user = A.actor
	if (amount && istype(user))
		add_fingerprint(user)

		if (user.get_equipped_item(SLOT_ID_GLOVES))
			return OP_OK
		var/taken = rand(1,amount)
		amount -= taken
		to_chat(user, span_notice("You get some of \the [src] on your hands."))
		transfer_blooddna_to(user)
		user.bloody_hands += taken
		user.hand_blood_color = basecolor
		user.update_inv_gloves(1)
		grant(user, granted_verb(/mob/living/carbon/human/proc/bloody_doodle), user)

	if(viruses)
		for(var/datum/affliction/contagion/D in viruses)
			if(D.IsSpreadByTouch())
				user.expose_contagion(D, BP_R_HAND)
	return OP_OK

/obj/effect/decal/cleanable/blood/splatter
		random_icon_states = list("mgibbl1", "mgibbl2", "mgibbl3", "mgibbl4", "mgibbl5")
		amount = 2

/obj/effect/decal/cleanable/blood/drip
	name = "drips of blood"
	desc = "It's red."
	gender = PLURAL
	icon = 'icons/effects/drip.dmi'
	icon_state = "1"
	random_icon_states = list("1","2","3","4","5")
	amount = 0
	var/list/drips

/obj/effect/decal/cleanable/blood/drip/Initialize(mapload)
	. = ..()
	LAZYOR(drips, icon_state)

/obj/effect/decal/cleanable/blood/writing
	icon_state = "tracks"
	desc = "It looks like a writing in blood."
	gender = NEUTER
	random_icon_states = list("writing1","writing2","writing3","writing4","writing5")
	amount = 0
	var/message

/obj/effect/decal/cleanable/blood/writing/Initialize(mapload)
	. = ..()
	if(length(random_icon_states))
		for(var/obj/effect/decal/cleanable/blood/writing/W in contents_of(loc))
			LAZYREMOVE(random_icon_states, W.icon_state)
		icon_state = DEFAULTPICK(random_icon_states, null)
	else
		icon_state = "writing1"

/obj/effect/decal/cleanable/blood/writing/examine(mob/user)
	. = ..()
	. += "It reads: <font color='[basecolor]'>\"[message]\"</font>"

/obj/effect/decal/cleanable/blood/gibs
	name = "gibs"
	desc = "They look bloody and gruesome."
	gender = PLURAL
	density = FALSE
	anchored = TRUE
	icon = 'icons/effects/blood.dmi'
	icon_state = "gib1"
	random_icon_states = list("gib1", "gib2", "gib3", "gib5", "gib6")
	var/fleshcolor = "#FFFFFF"

DECLARE_APPEARANCE_PROC(/obj/effect/decal/cleanable/blood/gibs, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/effect/decal/cleanable/blood/gibs/appearance_overlays()
	. = list()

	var/image/giblets = new(base_icon, "[icon_state]_flesh", dir)
	if(!fleshcolor || fleshcolor == "rainbow")
		fleshcolor = get_random_colour(1)
	giblets.color = fleshcolor

	var/icon/blood = new(base_icon,"[icon_state]",dir)
	if(basecolor == "rainbow") basecolor = get_random_colour(1)
	blood.Blend(basecolor,ICON_MULTIPLY)

	icon = blood
	. += giblets
	. += add_janitor_hud_overlay()

/obj/effect/decal/cleanable/blood/gibs/up
	random_icon_states = list("gib1", "gib2", "gib3", "gib5", "gib6","gibup1","gibup1","gibup1")

/obj/effect/decal/cleanable/blood/gibs/down
	random_icon_states = list("gib1", "gib2", "gib3", "gib5", "gib6","gibdown1","gibdown1","gibdown1")

/obj/effect/decal/cleanable/blood/gibs/body
	random_icon_states = list("gibhead", "gibtorso")

/obj/effect/decal/cleanable/blood/gibs/limb
	random_icon_states = list("gibleg", "gibarm")

/obj/effect/decal/cleanable/blood/gibs/core
	random_icon_states = list("gibmid1", "gibmid2", "gibmid3")

/obj/effect/decal/cleanable/blood/gibs/proc/streak(list/directions)
	streak_async(directions)

/obj/effect/decal/cleanable/blood/gibs/proc/streak_async(list/directions)
	after(src, 0.3 SECONDS, PROC_REF(streak_step), with = list(pick(directions), 0, pick(1, 200; 2, 150; 3, 50; 4)))

/// One streak step every 0.3 s: splatter behind (after the first), slide on.
/obj/effect/decal/cleanable/blood/gibs/proc/streak_step(direction, i, steps)
	if (i > 0)
		streak_splat()
	if (step_to(src, get_step(src, direction), 0))
		return
	if (i + 1 < steps)
		after(src, 0.3 SECONDS, PROC_REF(streak_step), with = list(direction, i + 1, steps))

/obj/effect/decal/cleanable/blood/gibs/proc/streak_splat()
	var/obj/effect/decal/cleanable/blood/b = new /obj/effect/decal/cleanable/blood/splatter(src.loc)
	b.basecolor = src.basecolor
	b.update_icon()

/obj/effect/decal/cleanable/mucus
	name = "mucus"
	desc = "Disgusting mucus."
	gender = PLURAL
	density = FALSE
	anchored = TRUE
	icon = 'icons/effects/blood.dmi'
	icon_state = "mucus"
	random_icon_states = list("mucus")

	var/dry = 0 // Keeps the lag down
	var/sampled = FALSE

//This version should be used for admin spawns and pre-mapped virus vectors (e.g. in PoIs), this version does not dry
/obj/effect/decal/cleanable/mucus/mapped/Initialize(mapload)
	. = ..()
	rel_add(src, nameof(viruses), new /datum/affliction/contagion/engineered/random(rand(3, 6), 9, 4, infected = src))

/obj/effect/decal/cleanable/mucus/Crossed(mob/living/carbon/human/perp)
	if(perp.is_incorporeal())
		return
	if(!istype(perp))
		return
	if(viruses)
		for(var/datum/affliction/contagion/D in viruses)
			if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))
				continue
			perp.expose_contagion(D, BP_R_FOOT)

CAPABILITIES(/obj/effect/decal/cleanable/mucus)
	op("touch_mucus", hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_touch_contagion)))

/// Old mucus/vomit attack_hand: touching it can pass on its contagious diseases.
/obj/effect/decal/cleanable/proc/interaction_touch_contagion(datum/act/op/A)
	var/mob/living/carbon/human/perp = A.actor
	if(perp.is_incorporeal())
		return OP_OK
	if(!istype(perp))
		return OP_OK
	if(viruses)
		for(var/datum/affliction/contagion/D in viruses)
			if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))
				continue
			perp.expose_contagion(D, BP_R_HAND)
	return OP_OK

/obj/effect/decal/cleanable/vomit/Crossed(mob/living/carbon/human/perp)
	if(perp.is_incorporeal())
		return
	if(!istype(perp))
		return
	if(viruses)
		for(var/datum/affliction/contagion/D in viruses)
			if(D.spread_flags & (DISEASE_SPREAD_SPECIAL | DISEASE_SPREAD_NON_CONTAGIOUS))
				continue
			perp.expose_contagion(D, BP_R_FOOT)

CAPABILITIES(/obj/effect/decal/cleanable/vomit)
	op("touch_vomit", hand(), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_touch_contagion)))

/obj/effect/decal/cleanable/mucus/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., viruses)

/obj/effect/decal/cleanable/vomit/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., viruses)

/obj/effect/decal/cleanable/blood/extrapolator_act(mob/living/user, obj/item/extrapolator/extrapolator, dry_run)
	. = ..()
	EXTRAPOLATOR_ACT_ADD_DISEASES(., viruses)

#undef DRYING_TIME

