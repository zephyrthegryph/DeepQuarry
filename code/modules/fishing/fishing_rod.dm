
/obj/item/material/fishing_rod/get_mechanics_info(list/additional_information)
	return ..(list("Needs cable to be used. Attached bait (food containing protein, sugar or nutriment) speeds up fishing based on its amount.") + additional_information)

/obj/item/material/fishing_rod
	name = "crude fishing rod"
	desc = "A crude rod made for catching fish."
	icon_state = "fishing_rod"
	item_state = "fishing_rod"
	force_divisor = 0.02
	applies_material_colour = TRUE
	default_material = MAT_WOOD
	can_dull = FALSE
	var/strung = TRUE
	var/line_break = TRUE

	var/obj/item/reagent_containers/food/snacks/Bait
	var/bait_type = /obj/item/reagent_containers/food/snacks

	var/cast = FALSE


/obj/item/material/fishing_rod/built
	strung = FALSE

/obj/item/material/fishing_rod/examine(mob/user)
	. = ..()
	if(Bait)
		. += span_notice("It has [Bait] hanging on its hook: ")
		. += Bait.examine(user)

/obj/item/material/fishing_rod/item_ctrl_click(mob/user)
	if((src.loc == user || Adjacent(user)) && Bait)
		Bait.forceMove(get_turf(user))
		to_chat(user, span_notice("You remove the bait from \the [src]."))
		rel_take(src, nameof(Bait))
	else
		..()

/obj/item/material/fishing_rod/proc/string_done(datum/act/op/A)
	var/mob/user = A.actor
	if(strung)
		return
	set_strung(TRUE)
	to_chat(user, span_notice("You string \the [src]!"))

/// How long stringing takes: ten to twenty seconds, rolled when it starts.
/obj/item/material/fishing_rod/proc/string_time(datum/act/op/A)
	return rand(10 SECONDS, 20 SECONDS)

CAPABILITIES(/obj/item/material/fishing_rod)
	configure(item_combat(injury_kind = INJURY_PIERCE))
	configure(examine_text(antag = "Some fishing rods can be utilized as long-range, sharp weapons, though their pseudo ranged ability comes at the cost of slow speed."))
	configure(item_thrown(force = 1))
	configure(item_combat(sharp = TRUE, attack_verbs = list("whipped", "battered", "slapped", "fished", "hooked"), attack_speed = 3 SECONDS))
	configure(item_sounds(hit = SFX_WEAPONS_PUNCHMISS))
	op("fishing_rod_string", stack(/obj/item/stack/cable_coil, 5), priority(OP_PRIORITY_DEFAULT), label("Use"), when(req_is(nameof(strung), FALSE)), wait(PROC_REF(string_time)), then(PROC_REF(string_done)))
	op("fishing_rod_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(fishing_rod_item)))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	owns_one(nameof(Bait), on_destroy = ON_DESTROY_CONTAINED)

/// Old attackby: swap the rod's bait; anything else falls through as its ..() did.
/obj/item/material/fishing_rod/proc/fishing_rod_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, bait_type))
		if(Bait)
			Bait.forceMove(get_turf(user))
			to_chat(user, span_notice("You swap \the [Bait] with \the [I]."))
		if(!move_into(src, nameof(src.Bait), I, user))
			return OP_PASS
		update_bait()
	return OP_DECLINE

/obj/item/material/fishing_rod/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	if(!strung)
		return OP_OK
	set_strung(FALSE)
	to_chat(user, span_notice("You cut \the [src]'s string!"))
	return OP_OK

/obj/item/material/fishing_rod/draw(datum/look/look)
	..()
	var/drawn_state = look.state_so_far(src)
	if(strung)
		look.overlay("[drawn_state]_string")

/obj/item/material/fishing_rod/proc/update_bait()
	if(istype(Bait, bait_type))
		var/foodvolume
		for(var/datum/reagent/re in Bait.reagents.reagent_list)
			if(re.id == REAGENT_ID_NUTRIMENT || re.id == REAGENT_ID_PROTEIN || re.id == REAGENT_ID_GLUCOSE || re.id == REAGENT_ID_FISHBAIT)
				foodvolume += re.volume

		set_toolspeed(tooling_of_type(type).speed * 10*(0.01/(0.2*(foodvolume/Bait.reagents.maximum_volume + 0.5))))// gives fishing a universal formula because Polaris' doesn't work here. Min value of 1, max value of 1/3, 0.5 at 1/2 filled with bait reagents.

	else
		set_toolspeed(tooling_of_type(type).speed)

/obj/item/material/fishing_rod/proc/consume_bait()
	if(Bait)
		rel_clear(src, nameof(Bait), OWN_DELETE)
		return TRUE
	return FALSE

/obj/item/material/fishing_rod/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(cast)
		to_chat(user, span_notice("You cannot cast \the [src] when it is already in use!"))
		return ITEM_INTERACT_FAILURE
	update_bait()
	return ..()

/obj/item/material/fishing_rod/modern
	name = "fishing rod"
	desc = "A refined rod for catching fish."
	icon_state = "fishing_rod_modern"
	item_state = "fishing_rod"
	default_material = MAT_TITANIUM


CAPABILITIES(/obj/item/material/fishing_rod/modern)
	configure(item_tooling(speed = 0.75))
	configure(item_combat(reach = 4, attack_speed = 2 SECONDS))

/obj/item/material/fishing_rod/modern/built
	strung = FALSE

/obj/item/material/fishing_rod/modern/cheap //A rod sold by the fishing vendor. Done so that the rod sold by mining reward vendors doesn't loose its value.
	name = "cheap fishing rod"
	desc = "Mass produced, but somewhat reliable."
	default_material = MAT_PLASTIC

CAPABILITIES(/obj/item/material/fishing_rod/modern/cheap)
	configure(item_tooling(speed = 0.9))


/obj/item/material/fishing_rod/modern/strong
	desc = "A extremely refined rod for catching fish."
	default_material = MAT_DURASTEEL

CAPABILITIES(/obj/item/material/fishing_rod/modern/strong)
	configure(item_tooling(speed = 0.5))


// The bait sits in the rod's contents.
