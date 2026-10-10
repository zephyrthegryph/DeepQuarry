/obj/item/stack/sandbags
	name = "sandbag"
	desc = "Filled sandbags. Fortunately pre-filled."
	singular_name = "sandbag"
	icon = 'icons/obj/sandbags.dmi'
	icon_state = "sandbag"
	w_class = ITEMSIZE_LARGE
	force = 10.0
	throwforce = 20.0
	throw_speed = 5
	throw_range = 3
	drop_sound = SFX_ITEMS_DROP_CLOTHING
	pickup_sound = SFX_ITEMS_PICKUP_CLOTHING
	MATERIAL_BULK(MAT_CLOTH, SHEET_MATERIAL_AMOUNT * 2)
	max_amount = 30
	attack_verb = list("hit", "bludgeoned", "pillowed")
	no_variants = TRUE
	stacktype = /obj/item/stack/sandbags

	pass_color = TRUE

	var/bag_material = MAT_CLOTH

/obj/item/stack/sandbags/cyborg
	name = "sandbag synthesizer"
	desc = "A device that makes filled sandbags. Don't ask how."
	gender = NEUTER
	MATERIAL_NONE
	uses_charge = 1
	charge_costs = list(500)
	stacktype = /obj/item/stack/sandbags

	bag_material = MAT_SYNCLOTH

CAPABILITIES(/obj/item/stack/sandbags)
	param(nameof(bag_material), pos = 2)

// ALLOW(init/INSTANCE_STATE): sandbags take their recipes, slowdown and their bags' colour
/obj/item/stack/sandbags/Initialize(mapload)
	. = ..()
	recipes = GLOB.sandbag_recipes
	update_slowdown()
	var/datum/material/M = get_material_by_name("[bag_material]")
	if(!M)
		return INITIALIZE_HINT_QDEL
	color = M.icon_colour

/// A bigger pile slows its carrier more.
/obj/item/stack/sandbags/proc/update_slowdown()
	slowdown = round(get_amount() / 10, 0.1)

/obj/item/stack/sandbags/set_amount(new_amount, no_limits = FALSE)
	. = ..()
	if(!QDELETED(src))
		update_slowdown()

/obj/item/stack/sandbags/produce_recipe(datum/stack_recipe/recipe, quantity, mob/user)
	var/required = quantity*recipe.req_amount
	var/produced = min(quantity*recipe.res_amount, recipe.max_res_amount)

	if (!can_use(required))
		if (produced>1)
			to_chat(user, span_warning("You haven't got enough [src] to build \the [produced] [recipe.title]\s!"))
		else
			to_chat(user, span_warning("You haven't got enough [src] to build \the [recipe.title]!"))
		return

	if (recipe.one_per_turf && (locate_within(user.loc, recipe.result_type)))
		to_chat(user, span_warning("There is another [recipe.title] here!"))
		return

	if (recipe.on_floor && !isfloor(user.loc))
		to_chat(user, span_warning("\The [recipe.title] must be constructed on the floor!"))
		return

	if (recipe.time)
		to_chat(user, span_notice("Building [recipe.title] ..."))
	start_build(user, recipe, required, produced)

/obj/item/stack/sandbags/produce_recipe_done(datum/act/op/A)
	var/datum/stack_recipe/recipe = A.arg("recipe")
	var/mob/user = A.actor
	var/required = A.arg("required")
	var/produced = A.arg("produced")
	if (use(required))
		var/atom/O = new recipe.result_type(user.loc, bag_material)

		if(istype(O, /obj/item))
			var/obj/item/Ob = O

			// Law of equivalent exchange: the product is made of exactly what it cost.
			var/mattermult = istype(Ob, /obj/item) ? min(2000, 400 * Ob.w_class) : 2000
			Ob.set_single_material(recipe.use_material, mattermult / produced * required)

		O.set_dir(user.dir)
		O.add_fingerprint(user)

		if (istype(O, /obj/item/stack))
			var/obj/item/stack/S = O
			S.set_amount(produced, TRUE)
			S.add_to_stacks(user)

		if (istype(O, /obj/item/storage)) //BubbleWrap - so newly formed boxes are empty
			for (var/obj/item/I in O)
				spent(I)

		if ((pass_color || recipe.pass_color))
			if(!color)
				if(recipe.use_material)
					var/datum/material/MAT = get_material_by_name(recipe.use_material)
					if(MAT.icon_colour)
						O.color = MAT.icon_colour
				else
					return OP_OK
			else
				O.color = color
		return OP_OK
	return OP_FAILED

// Empty bags. Yes, you need to fill them.

/obj/item/stack/emptysandbag
	name = "sandbag"
	desc = "Empty sandbags. You know what must be done."
	singular_name = "sandbag"
	icon = 'icons/obj/sandbags.dmi'
	icon_state = "sandbag_e"
	w_class = ITEMSIZE_LARGE

	strict_color_stacking = TRUE
	max_amount = 30
	stacktype = /obj/item/stack/emptysandbag

	pass_color = TRUE

	var/bag_material = MAT_CLOTH

// ALLOW(init/INSTANCE_STATE): empty bags take their material's colour
/obj/item/stack/emptysandbag/Initialize(mapload)
	. = ..()
	var/datum/material/M = get_material_by_name("[bag_material]")
	if(!M)
		return INITIALIZE_HINT_QDEL
	color = M.icon_colour

CAPABILITIES(/obj/item/stack/emptysandbag)
	without("ui_open")
	// A bag is filled each second while the user stays put; the series stops when the pile is gone or the ground is no longer outdoors.
	op("emptysandbag_self", in_hand(), label("Fill"), wait(1 SECOND, repeats = PROC_REF(fill_more), after_step = PROC_REF(fill_bag_done)))
	param(nameof(bag_material), pos = 2)

/// Another bag follows while there is a bag left and the ground is outdoors.
/obj/item/stack/emptysandbag/proc/fill_more(datum/act/op/A)
	return !QDELETED(src) && can_use(1) && istype(get_turf(src), /turf/simulated/floor/outdoors)

/// A bag filled: one used, one sandbag made where the pile lies.
/obj/item/stack/emptysandbag/proc/fill_bag_done(datum/act/op/A)
	if(!can_use(1) || !istype(get_turf(src), /turf/simulated/floor/outdoors))
		return
	var/mob/user = A.actor
	use(1)
	var/obj/item/stack/sandbags/SB = new (get_turf(src), 1, bag_material)
	SB.color = color
	if(user)
		to_chat(user, span_notice("You fill a sandbag."))
