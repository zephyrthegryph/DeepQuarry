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
	drop_sound = SFX_ITEMS_DROP_METALWEAPON
	pickup_sound = SFX_ITEMS_PICKUP_METALWEAPON
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
	recipes = GLOB.rods_recipes

/// A few rods show their count; a pile shows the plain state.
/obj/item/stack/rods/look_state()
	var/count = get_amount()
	if((count <= 5) && (count > 0))
		return "rods-[count]"
	return "rods"

CAPABILITIES(/obj/item/stack/rods)
	op("splint", item(/obj/item/tape_roll), passes(), then(PROC_REF(taped_into_splint)))

/// Tape wound round a rod makes a makeshift splint.
/obj/item/stack/rods/proc/taped_into_splint(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/medical/splint/ghetto/new_splint = new(get_turf(user))
	new_splint.add_fingerprint(user)

	act_message(user, null, MSG_SELF(span_notice("You use make \a [new_splint] out of a [singular_name].")), \
		MSG_OTHERS(span_infoplain(span_bold("%U%") + " constructs \a [new_splint] out of a [singular_name].")))
	src.use(1)
	return OP_OK

/obj/item/stack/rods/welder_act(mob/user, obj/item/tool)
	if(get_amount() < 2)
		to_chat(user, span_warning("You need at least two rods to do this."))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/weldingtool/welder = tool.get_welder()
	if(!welder.remove_fuel(0, user))
		return ITEM_INTERACT_BLOCKING
	var/obj/item/stack/material/steel/new_item = new(user.loc)
	new_item.add_to_stacks(user)
	act_message(src, user, others = span_notice("%U% is shaped into metal by %T% with the welding tool."), blind = span_notice("You hear welding."))
	var/replace = user.get_inactive_hand() == src
	use(2)
	if(QDELETED(src) && replace)
		user.put_in_hands(new_item)
	return ITEM_INTERACT_SUCCESS

/obj/item/stack/rods/reagents_per_sheet()
	return REAGENTS_PER_ROD
