/obj/item/grenade/chem_grenade
	name = "grenade casing"
	icon_state = "chemg"
	item_state = "grenade"
	desc = "A hand made chemical grenade."
	w_class = ITEMSIZE_SMALL
	force = 2.0
	det_time = null
	unacidable = TRUE

	var/stage = 0
	var/state = 0
	var/path = 0
	/// If TRUE, grenade is permanently sealed when fully assembled, useful for things like off-the-shelf grenades.
	var/sealed = FALSE
	var/obj/item/assembly_holder/detonator = null
	var/list/beakers
	var/list/allowed_containers = list(/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/glass/bottle) // ALLOW(instance_list): c: read-only per-subtype constant table (1 subtype overrides); a getter would share it, not worth it on a rare type
	var/affected_area = 3
	special_handling = TRUE

DECLARE_REAGENTS(/obj/item/grenade/chem_grenade, 1000, null)

DECLARE_REF(/obj/item/grenade/chem_grenade, "detonator", OWNED, null)
DECLARE_REF(/obj/item/grenade/chem_grenade, "beakers", OWNED_LIST, null)

/// Old attack_self.
/obj/item/grenade/chem_grenade/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!stage || stage==1)
		if(detonator)
			detonator.detached()
			user.put_in_hands(detonator)
			detonator=null
			det_time = null
			stage=0
			icon_state = initial(icon_state)
		else if(length(beakers))
			for(var/obj/B in beakers)
				if(istype(B))
					LAZYREMOVE(beakers, B)
					user.put_in_hands(B)
		name = "unsecured grenade with [length(beakers)] containers[detonator?" and detonator":""]"
	if(stage > 1 && !active && clown_check(user))
		to_chat(user, span_warning("You prime \the [name]!"))

		msg_admin_attack("[key_name_admin(user)] primed \a [src]")

		activate()
		add_fingerprint(user)
		if(iscarbon(user))
			var/mob/living/carbon/C = user
			C.throw_mode_on()

DECLARE_INTERACTIONS(/obj/item/grenade/chem_grenade, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attackby.
/obj/item/grenade/chem_grenade/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(istype(W,/obj/item/assembly_holder) && (!stage || stage==1) && !detonator && path != 2)
		var/obj/item/assembly_holder/det = W
		if(istype(det.a_left,det.a_right.type) || (!isigniter(det.a_left) && !isigniter(det.a_right)))
			to_chat(user, span_warning("Assembly must contain one igniter."))
			return INTERACTION_HANDLED_PASS
		if(!det.secured)
			to_chat(user, span_warning("Assembly must be secured with screwdriver."))
			return INTERACTION_HANDLED_PASS
		path = 1
		to_chat(user, span_notice("You add [W] to the metal casing."))
		play_sfx(src, SFX_ITEMS_SCREWDRIVER2)
		user.remove_from_mob(det)
		det.forceMove(src)
		detonator = det
		if(istimer(detonator.a_left))
			var/obj/item/assembly/timer/T = detonator.a_left
			det_time = 10*T.time
		if(istimer(detonator.a_right))
			var/obj/item/assembly/timer/T = detonator.a_right
			det_time = 10*T.time
		icon_state = initial(icon_state) +"_ass"
		name = "unsecured grenade with [length(beakers)] containers[detonator?" and detonator":""]"
		stage = 1
	else if(is_type_in_list(W, allowed_containers) && (!stage || stage==1) && path != 2)
		path = 1
		if(length(beakers) == 2)
			to_chat(user, span_warning("The grenade can not hold more containers."))
			return INTERACTION_HANDLED_PASS
		else
			if(W.reagents.total_volume)
				to_chat(user, span_notice("You add \the [W] to the assembly."))
				user.drop_item()
				W.forceMove(src)
				LAZYADD(beakers, W)
				stage = 1
				name = "unsecured grenade with [length(beakers)] containers[detonator?" and detonator":""]"
			else
				to_chat(user, span_warning("\The [W] is empty."))
	return INTERACTION_HANDLED_PASS

/obj/item/grenade/chem_grenade/screwdriver_act(mob/user, obj/item/tool)
	if(path == 2)
		return ..()
	if(stage == 1)
		path = 1
		if(length(beakers))
			to_chat(user, span_notice("You lock the assembly."))
			name = "grenade"
		else
			to_chat(user, span_notice("You lock the empty assembly."))
			name = "fake grenade"
		playsound(src, tool.usesound, 50, TRUE)
		icon_state = "[initial(icon_state)]_locked"
		stage = 2
		return ITEM_INTERACT_SUCCESS
	if(stage != 2)
		return ..()
	if(active && prob(95))
		to_chat(user, span_warning("You trigger the assembly!"))
		detonate()
	else if(sealed)
		to_chat(user, span_warning("This grenade lacks a way to disassemble it."))
	else
		to_chat(user, span_notice("You unlock the assembly."))
		playsound(src, tool.usesound, 50, TRUE)
		name = "unsecured grenade with [length(beakers)] containers[detonator ? " and detonator" : ""]"
		icon_state = initial(icon_state) + (detonator ? "_ass" : "")
		stage = 1
		active = FALSE
	return ITEM_INTERACT_SUCCESS

/obj/item/grenade/chem_grenade/examine(mob/user)
	. = ..()
	if(detonator)
		. += "It has [detonator.name] attached to it."

/obj/item/grenade/chem_grenade/activate(mob/user as mob)
	if(active) return

	if(detonator)
		if(!isigniter(detonator.a_left))
			detonator.a_left.activate()
			active = 1
		if(!isigniter(detonator.a_right))
			detonator.a_right.activate()
			active = 1
	if(active)
		icon_state = initial(icon_state) + "_active"

		if(user)
			msg_admin_attack("[key_name_admin(user)] primed \a [src.name]")

	return

/obj/item/grenade/chem_grenade/proc/primed(primed = 1)
	if(active)
		icon_state = initial(icon_state) + (primed?"_primed":"_active")

/obj/item/grenade/chem_grenade/detonate()
	if(!stage || stage<2) return

	var/has_reagents = 0
	for(var/obj/item/reagent_containers/glass/G in beakers)
		if(G.reagents.total_volume) has_reagents = 1

	active = 0
	if(!has_reagents)
		icon_state = initial(icon_state) +"_locked"
		play_sfx(src, SFX_ITEMS_SCREWDRIVER2, 2)
		om_after(src, 0, PROC_REF(sync_det_time)) //Otherwise det_time is erroneously set to 0 after this
		return

	play_sfx(src, SFX_EFFECTS_BAMF, volume = 50)

	for(var/obj/item/reagent_containers/glass/G in beakers)
		G.reagents.trans_to_obj(src, G.reagents.total_volume)

	if(src.reagents.total_volume) //The possible reactions didnt use up all reagents.
		var/datum/effect/effect/system/steam_spread/steam = new /datum/effect/effect/system/steam_spread()
		steam.set_up(10, 0, get_turf(src))
		steam.attach(src)
		steam.start()

		for(var/atom/A in view(affected_area, src.loc))
			if( A == src ) continue
			src.reagents.touch(A)

	if(istype(loc, /mob/living/carbon))		//drop dat grenade if it goes off in your hand
		var/mob/living/carbon/C = loc
		C.drop_from_inventory(src)
		C.throw_mode_off()

	invisibility = INVISIBILITY_MAXIMUM //Why am i doing this?
	expire(5 SECONDS) //To make sure all reagents can work correctly before deleting the grenade.

/obj/item/grenade/chem_grenade/large
	name = "large chem grenade"
	desc = "An oversized grenade that affects a larger area."
	icon_state = "large_grenade"
	allowed_containers = list(/obj/item/reagent_containers/glass)
	affected_area = 4

/obj/item/grenade/chem_grenade/metalfoam
	name = "metal-foam grenade"
	desc = "Used for emergency sealing of air breaches."
	icon_state = "foam"
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a, null, list(REAGENT_ID_ALUMINIUM = 30))

/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b, null, list(REAGENT_ID_FOAMINGAGENT = 10, REAGENT_ID_PACID = 10))

DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/metalfoam, "beakers", list(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b))
DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/metalfoam, "detonator", /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/incendiary
	name = "incendiary grenade"
	desc = "Used for clearing rooms of living things."
	icon_state = "incendiary"
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a, null, list(REAGENT_ID_ALUMINIUM = 15, REAGENT_ID_FUEL = 40))

/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b, null, list(REAGENT_ID_PHORON = 15, REAGENT_ID_SACID = 15))

DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/incendiary, "beakers", list(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b))
DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/incendiary, "detonator", /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/antiweed
	icon_state = "grenade"
	name = "weedkiller grenade"
	desc = "Used for purging large areas of invasive plant species. Contents under pressure. Do not directly inhale contents."
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a, null, list(REAGENT_ID_PLANTBGONE = 25, REAGENT_ID_POTASSIUM = 25))

/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b, null, list(REAGENT_ID_PHOSPHORUS = 25, REAGENT_ID_SUGAR = 25))

DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/antiweed, "beakers", list(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b))
DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/antiweed, "detonator", /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/cleaner
	name = "cleaner grenade"
	desc = "BLAM!-brand foaming space cleaner. In a special applicator for rapid cleaning of wide areas."
	icon_state = "cleaner"
	stage = 2
	path = 1
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a, null, list(REAGENT_ID_FLUOROSURFACTANT = 40))

/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b, null, list(REAGENT_ID_WATER = 40, REAGENT_ID_CLEANER = 10))

DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/cleaner, "beakers", list(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b))
DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/cleaner, "detonator", /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/teargas
	name = "tear gas grenade"
	desc = "Concentrated Capsaicin. Contents under pressure. Use with caution."
	icon_state = "teargas"
	stage = 2
	path = 1
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a, null, list(REAGENT_ID_PHOSPHORUS = 40, REAGENT_ID_POTASSIUM = 40, REAGENT_ID_CONDENSEDCAPSAICIN = 40))

/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b

DECLARE_REAGENTS(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b, null, list(REAGENT_ID_SUGAR = 40, REAGENT_ID_CONDENSEDCAPSAICIN = 80))

DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/teargas, "beakers", list(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a, /obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b))
DECLARE_DEFAULT_CHILD(/obj/item/grenade/chem_grenade/teargas, "detonator", /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/proc/sync_det_time()
	if(istimer(detonator.a_left)) //Make sure description reflects that the timer has been reset
		var/obj/item/assembly/timer/T = detonator.a_left
		det_time = 10*T.time
	if(istimer(detonator.a_right))
		var/obj/item/assembly/timer/T = detonator.a_right
		det_time = 10*T.time
