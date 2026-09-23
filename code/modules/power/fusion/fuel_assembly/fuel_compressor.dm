#define FUSION_ROD_SHEET_AMT 15
/obj/machinery/fusion_fuel_compressor
	maintenance_flags = MACHINE_MAINT_STANDARD
	var/blitzprogress = 0
	name = "fuel compressor"
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "fuel_compressor1"
	density = TRUE
	anchored = TRUE

	circuit = /obj/item/circuitboard/fusion_fuel_compressor

/obj/machinery/fusion_fuel_compressor/Initialize(mapload)
	. = ..()
	default_apply_parts()

/obj/machinery/fusion_fuel_compressor/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_item/part_replacement,
		/datum/interaction/machine_item/fuel_compressor_stack_material,
		/datum/interaction/machine_item/fuel_compressor_special,
		/datum/interaction/machine_drag/fuel_compressor_compress,
		/datum/interaction/machine_verb/fuel_compressor_eject_sheet,
	)
	..()

/// Old MouseDrop_T.
/datum/interaction/machine_drag/fuel_compressor_compress
	id = "fuel_compressor_compress"
	name = "Compress"
	requires = list(REQ_INTERACTION_REACH, REQ_ON(PRED_ACTOR, /obj/machinery/fusion_fuel_compressor/proc/actor_can_act, "you can't do that right now"))
	effect = /obj/machinery/fusion_fuel_compressor/proc/interaction_compress

/obj/machinery/fusion_fuel_compressor/proc/actor_can_act(mob/actor, atom/target, obj/item/held)
	return !actor.incapacitated()

/obj/machinery/fusion_fuel_compressor/proc/interaction_compress(mob/user, atom/movable/dropping, datum/interaction/interaction)
	do_special_fuel_compression(dropping, user)
	return TRUE

/obj/machinery/fusion_fuel_compressor/proc/do_special_fuel_compression(obj/item/thing, mob/user)
	if(istype(thing) && thing.reagents && thing.reagents.total_volume && thing.is_open_container())
		if(thing.reagents.reagent_list.len > 1)
			to_chat(user, span_warning("The contents of \the [thing] are impure and cannot be used as fuel."))
			return 1
		if(thing.reagents.total_volume < 300)
			to_chat(user, span_warning("You need at least three hundred units of material to form a fuel rod."))
			return 1
		var/datum/reagent/R = thing.reagents.reagent_list[1]
		visible_message(span_infoplain(span_bold("\The [src]") + " compresses the contents of \the [thing] into a new fuel assembly."))
		var/obj/item/fuel_assembly/F = new(get_turf(src), R.id, R.color)
		thing.reagents.remove_reagent(R.id, R.volume)
		user.put_in_hands(F)

	else if(istype(thing, /obj/machinery/power/supermatter))
		var/obj/item/fuel_assembly/F = new(get_turf(src), MAT_SUPERMATTER)
		visible_message(span_infoplain(span_bold("\The [src]") + " compresses \the [thing] into a new fuel assembly."))
		qdel(thing)
		user.put_in_hands(F)
		return 1
	return 0

/// Old attackby's stack/material branch (part_replacement checked first, matching the old body's first check).
/datum/interaction/machine_item/fuel_compressor_stack_material
	id = "fuel_compressor_stack_material"
	name = "Compress into fuel rod"
	held_type = /obj/item/stack/material
	effect = /obj/machinery/fusion_fuel_compressor/proc/interaction_stack_material

/obj/machinery/fusion_fuel_compressor/proc/interaction_stack_material(mob/user, obj/item/stack/material/M, datum/interaction/interaction)
	var/datum/material/mat = M.get_material()
	if(!blitzprogress)
		if(!mat.is_fusion_fuel)
			to_chat(user, span_warning("It would be pointless to make a fuel rod out of [mat.use_name]."))
			return TRUE
		if(M.get_amount() < FUSION_ROD_SHEET_AMT)
			if(mat.name==MAT_SUPERMATTER)
				visible_message(span_notice("\The [user] places the [mat.use_name] into the compressor."))
				M.use(1)
				blitzprogress = 1
				return TRUE
			to_chat(user, span_warning("You need at least 25 [mat.sheet_plural_name] to make a fuel rod."))
			return TRUE
		var/obj/item/fuel_assembly/F = new(get_turf(src), mat.name)
		visible_message(span_infoplain(span_bold("\The [src]") + " compresses \the [M] into a new fuel assembly."))
		M.use(FUSION_ROD_SHEET_AMT)
		user.put_in_hands(F)
	else
		if(mat.name==MAT_PHORON)
			if(M.get_amount() < 25)
				to_chat(user, span_warning("You need at least 25 phoron sheets to make a blitz rod!"))
				return TRUE
			var/obj/item/fuel_assembly/blitz/unshielded/F = new(get_turf(src))
			visible_message(span_notice("\The [src] compresses the supermatter and phoron into a new blitz rod! It looks unstable, maybe you should be careful with it."))
			M.use(25)
			user.put_in_hands(F)
			blitzprogress = 0
		else
			to_chat(user, span_warning("A blitz rod is currently in progress! Either add 25 phoron sheets to complete it, or eject the supermatter sheet!"))
			return TRUE
	return TRUE

/// Old attackby's final else/return ..() branch: try the special compression, else fall through.
/datum/interaction/machine_item/fuel_compressor_special
	id = "fuel_compressor_special"
	name = "Compress"
	held_type = /obj/item
	effect = /obj/machinery/fusion_fuel_compressor/proc/interaction_special_or_base

/obj/machinery/fusion_fuel_compressor/proc/interaction_special_or_base(mob/user, obj/item/thing, datum/interaction/interaction)
	if(do_special_fuel_compression(thing, user))
		return TRUE
	return FALSE

/// Old verb, offered only while a blitz rod is in progress (the old code added/removed it dynamically).
/datum/interaction/machine_verb/fuel_compressor_eject_sheet
	id = "fuel_compressor_eject_sheet"
	name = "Eject Supermatter Sheet"
	offered_when = list(REQ_ON(PRED_TARGET, /obj/machinery/fusion_fuel_compressor/proc/has_blitz_progress, "nothing to eject"))
	effect = /obj/machinery/fusion_fuel_compressor/proc/interaction_eject_sheet

/obj/machinery/fusion_fuel_compressor/proc/has_blitz_progress(mob/actor, atom/target, obj/item/held)
	return blitzprogress

/obj/machinery/fusion_fuel_compressor/proc/interaction_eject_sheet(mob/user, obj/item/held, datum/interaction/interaction)
	if(blitzprogress)
		new/obj/item/stack/material/supermatter(get_turf(src))
		blitzprogress = 0
	return TRUE

#undef FUSION_ROD_SHEET_AMT
