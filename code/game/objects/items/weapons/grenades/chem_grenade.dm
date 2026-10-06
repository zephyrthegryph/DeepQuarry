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
	var/affected_area = 3
	special_handling = TRUE

CAPABILITIES(/obj/item/grenade/chem_grenade)
	reagents(1000)
	owns_many(nameof(beakers))
	owns_one(nameof(detonator), /obj/item/assembly_holder)
	without("prime")   // its own self-use takes the assembly apart or primes it
	op("assemble", in_hand(), then(PROC_REF(interaction_self)))
	op("assembly_item", item(/obj/item), then(PROC_REF(interaction_item)))

TYPE_TABLE_DECLARE(/obj/item/grenade/chem_grenade, chem_grenade_containers, list(/obj/item/reagent_containers/glass/beaker, /obj/item/reagent_containers/glass/bottle))



/// Old attack_self: take the detonator or the containers out, or prime it once assembled.
/obj/item/grenade/chem_grenade/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	if(!stage || stage==1)
		if(detonator)
			detonator.detached()
			user.put_in_hands(detonator)
			rel_take(src, nameof(detonator))
			det_time = null
			stage=0
			icon_state = initial(icon_state)
		else if(length(beakers))
			for(var/obj/B in beakers)
				if(istype(B))
					own_take_member(src, nameof(beakers), B)
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
	return OP_OK

/// A matching chemical container must be releasable before grenade assembly changes it: null, or why not.
/obj/item/grenade/chem_grenade/proc/container_refusal(mob/user, obj/item/held)
	return held.loc?.release_refusal(held, user)

/// Old attackby: fit a detonator assembly or a chemical container.
/obj/item/grenade/chem_grenade/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(istype(W,/obj/item/assembly_holder) && (!stage || stage==1) && !detonator && path != 2)
		var/obj/item/assembly_holder/det = W
		if(istype(det.a_left,det.a_right.type) || (!isigniter(det.a_left) && !isigniter(det.a_right)))
			to_chat(user, span_warning("Assembly must contain one igniter."))
			return OP_PASS
		if(!det.secured)
			to_chat(user, span_warning("Assembly must be secured with screwdriver."))
			return OP_PASS
		path = 1
		to_chat(user, span_notice("You add [W] to the metal casing."))
		play_sfx(src, SFX_ITEMS_SCREWDRIVER2)
		if(!move_into(src, nameof(src.detonator), det, user))
			return OP_PASS
		if(istimer(detonator.a_left))
			var/obj/item/assembly/timer/T = detonator.a_left
			det_time = 10*T.time
		if(istimer(detonator.a_right))
			var/obj/item/assembly/timer/T = detonator.a_right
			det_time = 10*T.time
		icon_state = initial(icon_state) +"_ass"
		name = "unsecured grenade with [length(beakers)] containers[detonator?" and detonator":""]"
		stage = 1
	else if(is_type_in_list(W, TYPE_TABLE_GET(src, chem_grenade_containers)) && (!stage || stage==1) && path != 2)
		var/why = container_refusal(user, W)
		if(why)
			to_chat(user, span_warning(capitalize("[why].")))
			return OP_PASS
		path = 1
		if(length(beakers) == 2)
			to_chat(user, span_warning("The grenade can not hold more containers."))
			return OP_PASS
		else
			if(W.reagents.total_volume)
				if(!move_into(src, nameof(beakers), W, user))
					return OP_PASS
				to_chat(user, span_notice("You add \the [W] to the assembly."))
				stage = 1
				name = "unsecured grenade with [length(beakers)] containers[detonator?" and detonator":""]"
			else
				to_chat(user, span_warning("\The [W] is empty."))
	return OP_PASS

/obj/item/grenade/chem_grenade/screwdriver_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
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
		return OP_OK
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
	return OP_OK

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
		after(src, 0, PROC_REF(sync_det_time)) //Otherwise det_time is erroneously set to 0 after this
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
	affected_area = 4

TYPE_TABLE(/obj/item/grenade/chem_grenade/large, chem_grenade_containers, list(/obj/item/reagent_containers/glass))

/obj/item/grenade/chem_grenade/metalfoam
	name = "metal-foam grenade"
	desc = "Used for emergency sealing of air breaches."
	icon_state = "foam"
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a)
	configure(reagents(add = list(REAGENT_ID_ALUMINIUM = 30)))

/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b)
	configure(reagents(add = list(REAGENT_ID_FOAMINGAGENT = 10, REAGENT_ID_PACID = 10)))

CAPABILITIES(/obj/item/grenade/chem_grenade/metalfoam)
	owns_many(nameof(beakers), starts = list(/obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_metalfoam_b))
	owns_one(nameof(detonator), /obj/item/assembly_holder, starts = /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/incendiary
	name = "incendiary grenade"
	desc = "Used for clearing rooms of living things."
	icon_state = "incendiary"
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a)
	configure(reagents(add = list(REAGENT_ID_ALUMINIUM = 15, REAGENT_ID_FUEL = 40)))

/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b)
	configure(reagents(add = list(REAGENT_ID_PHORON = 15, REAGENT_ID_SACID = 15)))

CAPABILITIES(/obj/item/grenade/chem_grenade/incendiary)
	owns_many(nameof(beakers), starts = list(/obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_incendiary_b))
	owns_one(nameof(detonator), /obj/item/assembly_holder, starts = /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/antiweed
	icon_state = "grenade"
	name = "weedkiller grenade"
	desc = "Used for purging large areas of invasive plant species. Contents under pressure. Do not directly inhale contents."
	path = 1
	stage = 2
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a)
	configure(reagents(add = list(REAGENT_ID_PLANTBGONE = 25, REAGENT_ID_POTASSIUM = 25)))

/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b)
	configure(reagents(add = list(REAGENT_ID_PHOSPHORUS = 25, REAGENT_ID_SUGAR = 25)))

CAPABILITIES(/obj/item/grenade/chem_grenade/antiweed)
	owns_many(nameof(beakers), starts = list(/obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_antiweed_b))
	owns_one(nameof(detonator), /obj/item/assembly_holder, starts = /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/cleaner
	name = "cleaner grenade"
	desc = "BLAM!-brand foaming space cleaner. In a special applicator for rapid cleaning of wide areas."
	icon_state = "cleaner"
	stage = 2
	path = 1
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a)
	configure(reagents(add = list(REAGENT_ID_FLUOROSURFACTANT = 40)))

/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b)
	configure(reagents(add = list(REAGENT_ID_WATER = 40, REAGENT_ID_CLEANER = 10)))

CAPABILITIES(/obj/item/grenade/chem_grenade/cleaner)
	owns_many(nameof(beakers), starts = list(/obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_a, /obj/item/reagent_containers/glass/beaker/grenade_fill_cleaner_b))
	owns_one(nameof(detonator), /obj/item/assembly_holder, starts = /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/teargas
	name = "tear gas grenade"
	desc = "Concentrated Capsaicin. Contents under pressure. Use with caution."
	icon_state = "teargas"
	stage = 2
	path = 1
	sealed = TRUE

/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a)
	configure(reagents(add = list(REAGENT_ID_PHOSPHORUS = 40, REAGENT_ID_POTASSIUM = 40, REAGENT_ID_CONDENSEDCAPSAICIN = 40)))

/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b

CAPABILITIES(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b)
	configure(reagents(add = list(REAGENT_ID_SUGAR = 40, REAGENT_ID_CONDENSEDCAPSAICIN = 80)))

CAPABILITIES(/obj/item/grenade/chem_grenade/teargas)
	owns_many(nameof(beakers), starts = list(/obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_a, /obj/item/reagent_containers/glass/beaker/large/grenade_fill_teargas_b))
	owns_one(nameof(detonator), /obj/item/assembly_holder, starts = /obj/item/assembly_holder/timer_igniter)

/obj/item/grenade/chem_grenade/proc/sync_det_time()
	if(istimer(detonator.a_left)) //Make sure description reflects that the timer has been reset
		var/obj/item/assembly/timer/T = detonator.a_left
		det_time = 10*T.time
	if(istimer(detonator.a_right))
		var/obj/item/assembly/timer/T = detonator.a_right
		det_time = 10*T.time
