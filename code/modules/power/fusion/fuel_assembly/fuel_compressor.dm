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

TRACKED(/obj/machinery/fusion_fuel_compressor, blitzprogress)

// The fuel compressor (doc/rewrite/final_api.html section 16): sheets of a fusion fuel (FUSION_ROD_SHEET_AMT of them), an open container
// holding 300 units of one pure reagent, or a supermatter crystal dragged onto it become a fuel rod. One supermatter sheet starts a blitz rod,
// which 25 phoron sheets finish; until then the sheet can be ejected.
CAPABILITIES(/obj/machinery/fusion_fuel_compressor)
	part_replacement()
	op("compress_sheets", item(/obj/item/stack/material), label("Compress into fuel rod"), wait(0), then(PROC_REF(sheets_compressed)))
	op("compress", item(/obj/item/reagent_containers), label("Compress"), wait(0), then(PROC_REF(container_compressed)))
	op("compress_drag", item(/obj/machinery/power/supermatter), gesture(GESTURE_DRAG), label("Compress"), wait(0), then(PROC_REF(dragged_compressed)))
	op("eject_sheet", menu(), label("Eject Supermatter Sheet"), wait(0), when(nameof(blitzprogress)), then(PROC_REF(sheet_ejected)))
	default_parts()

/obj/machinery/fusion_fuel_compressor/proc/dragged_compressed(datum/act/op/A)
	do_special_fuel_compression(A.held, A.actor)
	return OP_OK

/obj/machinery/fusion_fuel_compressor/proc/container_compressed(datum/act/op/A)
	do_special_fuel_compression(A.held, A.actor)
	return OP_OK

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
		consume(thing, user)
		user.put_in_hands(F)
		return 1
	return 0

/// Sheets in: a fuel rod, a blitz rod started or finished, or what is missing.
/obj/machinery/fusion_fuel_compressor/proc/sheets_compressed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/M = A.held
	. = OP_OK
	var/datum/material/mat = M.get_material()
	if(!blitzprogress)
		if(!mat.is_fusion_fuel)
			to_chat(user, span_warning("It would be pointless to make a fuel rod out of [mat.use_name]."))
			return
		if(M.get_amount() < FUSION_ROD_SHEET_AMT)
			if(mat.name==MAT_SUPERMATTER)
				act_message(user, null, others = span_notice("%U% places the [mat.use_name] into the compressor."))
				M.use(1)
				set_blitzprogress(1)
				return
			to_chat(user, span_warning("You need at least 25 [mat.sheet_plural_name] to make a fuel rod."))
			return
		var/obj/item/fuel_assembly/F = new(get_turf(src), mat.name)
		visible_message(span_infoplain(span_bold("\The [src]") + " compresses \the [M] into a new fuel assembly."))
		M.use(FUSION_ROD_SHEET_AMT)
		user.put_in_hands(F)
	else
		if(mat.name==MAT_PHORON)
			if(M.get_amount() < 25)
				to_chat(user, span_warning("You need at least 25 phoron sheets to make a blitz rod!"))
				return
			var/obj/item/fuel_assembly/blitz/unshielded/F = new(get_turf(src))
			visible_message(span_notice("\The [src] compresses the supermatter and phoron into a new blitz rod! It looks unstable, maybe you should be careful with it."))
			M.use(25)
			user.put_in_hands(F)
			set_blitzprogress(0)
		else
			to_chat(user, span_warning("A blitz rod is currently in progress! Either add 25 phoron sheets to complete it, or eject the supermatter sheet!"))

/// The supermatter sheet of an unfinished blitz rod comes back out.
/obj/machinery/fusion_fuel_compressor/proc/sheet_ejected(datum/act/op/A)
	if(blitzprogress)
		new/obj/item/stack/material/supermatter(get_turf(src))
		set_blitzprogress(0)
	return OP_OK

#undef FUSION_ROD_SHEET_AMT
