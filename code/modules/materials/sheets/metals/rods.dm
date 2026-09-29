/obj/item/stack/rods
	name = "metal rod"
	desc = "Some rods. Can be used for building, or something."
	singular_name = "metal rod"
	icon_state = "rods"
	w_class = ITEMSIZE_NORMAL
	force = 9.0
	throwforce = 15.0
	throw_speed = 5
	throw_range = 20
	drop_sound = 'sound/items/drop/metalweapon.ogg'
	pickup_sound = 'sound/items/pickup/metalweapon.ogg'
	MATERIAL_BULK(MAT_STEEL, REAGENTS_PER_ROD)
	max_amount = 60
	attack_verb = list("hit", "bludgeoned", "whacked")

	color = "#666666"

/obj/item/stack/rods/cyborg
	name = "metal rod synthesizer"
	desc = "A device that makes metal rods."
	gender = NEUTER
	MATERIAL_NONE
	uses_charge = 1
	charge_costs = list(500)
	stacktype = /obj/item/stack/rods
	no_variants = TRUE

/obj/item/stack/rods/Initialize(mapload)
	. = ..()
	recipes = GLOB.rods_recipes // ALLOW(ownership): a shared global recipe table (stack_recipe definitions, never owned); /obj/item/stack.recipes needs a SHARED declaration in stack.dm
	update_icon()

/obj/item/stack/rods/update_icon()
	var/amount = get_amount()
	if((amount <= 5) && (amount > 0))
		icon_state = "rods-[amount]"
	else
		icon_state = "rods"

EXTEND_INTERACTIONS(/obj/item/stack/rods, INTERACT_ITEM(null, PROC_REF(rods_interaction_item)))

/// Old attackby.
/obj/item/stack/rods/proc/rods_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if (istype(W, /obj/item/tape_roll))
		var/obj/item/stack/medical/splint/ghetto/new_splint = new(get_turf(user))
		new_splint.add_fingerprint(user)

		user.visible_message(span_infoplain(span_bold("\The [user]") + " constructs \a [new_splint] out of a [singular_name]."), \
				span_notice("You use make \a [new_splint] out of a [singular_name]."))
		src.use(1)
		return INTERACTION_HANDLED_PASS

	return FALSE

/obj/item/stack/rods/welder_act(mob/user, obj/item/tool)
	if(get_amount() < 2)
		to_chat(user, span_warning("You need at least two rods to do this."))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.remove_fuel(0, user))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/stack/material/steel/new_item = new(user.loc)
	new_item.add_to_stacks(user)
	visible_message(span_notice("[src] is shaped into metal by [user.name] with the welding tool."), span_notice("You hear welding."))
	var/replace = user.get_inactive_hand() == src
	use(2)
	if(QDELETED(src) && replace)
		user.put_in_hands(new_item)
	return ITEM_INTERACT_SUCCESS

/obj/item/stack/rods/reagents_per_sheet()
	return REAGENTS_PER_ROD
