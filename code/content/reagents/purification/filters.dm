// The funnel and its filters (code/domains/world_model/reagents/holder.dm: trans_to_holder() sends what is poured into a container with a filtered funnel through
// the filter first).
//
// A funnel fits on a glass container (code/content/reagents/purification/funnel_and_catalyst.dm) and takes one filter. The liquid poured in lands in an open basin,
// the filter takes out what it takes out of that, a little of the product stays in the filter, and what is left goes into the container. A filter takes
// contaminants by TAG (the tags of a contaminant come from its block structure, code/domains/world_model/reagents/blocks/structure.dm), each tag with a strength
// (0..1: the share it takes from what passes, while it is fresh); a contaminant with several tags is taken at the strongest:
//
//   paper     solid                          the particulate
//   charcoal  nonpolar, organic              oils, tar, dioxin, organic residue, endotoxin
//   sorbent   (an ion-exchange sorbent) made from a sheet of a material, the material's stats decide the tags and how well:
//               sorption (reagent porosity, gas sorption)  ionic, metallic, sulfurous, nonpolar: salts, heavy metals, sulfur, oils
//               catalytic activity                         oxidiser, sulfurous: reactive impurity, peroxide, sulfur
//               antimicrobial activity                     biological: endotoxin
//
// A contaminant also has a floor (/datum/reagent/contaminant/filter_floor): the share of the mixture below which no filter takes it any further. A trace of
// dioxin or nitrosamine goes through whatever it is poured through; only not making it keeps it out.
//
// A filter has a capacity: every unit it takes out and every unit of product it keeps back uses it up, it works less well as it fills (linearly: half full, half
// as good), and a full filter passes everything. Nothing here is a free purification: the product it keeps back is lost yield. Every filtering is written to
// the world log under GLOB.chem_trace.

/// The funnel: fits on the mouth of a glass container and holds a filter.
/obj/item/chem_funnel
	name = "funnel"
	desc = "A small funnel. Fit it on a beaker, put a filter in it, and whatever is poured into the beaker goes through the filter."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "dropper0"
	w_class = ITEMSIZE_SMALL
	/// The filter in the funnel, or null.
	var/obj/item/chem_filter/filter

CAPABILITIES(/obj/item/chem_funnel)
	owns_one(nameof(filter), /obj/item/chem_filter)
	op("insert_filter", item(/obj/item/chem_filter), label("Put the filter in the funnel"), \
		needs(req(PROC_REF(filter_slot_free))), then(PROC_REF(filter_inserted)))
	op("remove_filter", menu(), when(req_actor_kind(/mob/living)), label("Take the filter out"), \
		needs(req_capable(), req(PROC_REF(filter_in_place), silent = TRUE)), then(PROC_REF(filter_removed)))

MSG_DEF_SELF(chem_funnel/has_filter, "There is a filter in the funnel already.")

/obj/item/chem_funnel/examine(mob/user)
	. = ..()
	if(filter)
		. += span_notice("It holds \a [filter].")

/obj/item/chem_funnel/proc/filter_slot_free(datum/act/op/A)
	return filter ? MSG(chem_funnel/has_filter) : null

/obj/item/chem_funnel/proc/filter_in_place(datum/act/op/A)
	return filter ? null : /datum/msg/req_failed

/obj/item/chem_funnel/proc/filter_inserted(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_filter/F = A.held
	if(!move_into(src, nameof(src.filter), F, user))
		return OP_OK
	to_chat(user, span_notice("You put \the [F] in \the [src]."))
	return OP_OK

/obj/item/chem_funnel/proc/filter_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_filter/F = filter
	if(!F)
		return OP_OK
	F.forceMove(get_turf(src))
	rel_take(src, nameof(filter))
	user.put_in_hands(F)
	to_chat(user, span_notice("You take \the [F] out of \the [src]."))
	return OP_OK

/// A filter: capacity in units, the product it keeps back per unit passed, and what it takes (class strengths).
/obj/item/chem_filter
	name = "filter"
	desc = "A filter for a funnel."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "pillA"
	w_class = ITEMSIZE_TINY
	/// How much it can take before it is full: units of contaminant and of product kept.
	var/capacity = 30
	/// Units of product kept back per unit of product passed, while it still works.
	var/retention = FILTER_RETENTION_PAPER
	/// Capacity used so far.
	var/used = 0

/// The share of capacity left (1 fresh, 0 full): how well it works.
/obj/item/chem_filter/proc/freshness()
	return clamp(1 - used / max(capacity, 0.01), 0, 1)

/// tag => strength (0..1) of this filter against it, fresh.
/obj/item/chem_filter/proc/tag_strengths()
	return list()

/// The strength (0..1) of a filter with these tag strengths against one contaminant: its strongest tag. Tags of a contaminant: its structure's, `solid` when it is one.
/proc/chem_filter_strength_against(list/strengths, datum/reagent/R)
	. = 0
	for(var/tag in chem_tags_of(R))
		. = max(., strengths[tag] || 0)

/obj/item/chem_filter/examine(mob/user)
	. = ..()
	if(freshness() <= 0)
		. += span_warning("It is clogged solid.")
	else
		. += span_notice("It is about [round(freshness() * 100)]% fresh.")

/// Runs `mixture` (a basin holder, a pour on its way into `where`) through the filter: contaminants it catches come out, a little product stays, the capacity is used.
/obj/item/chem_filter/proc/filter_mixture(datum/reagents/mixture, atom/where)
	var/fresh = freshness()
	if(fresh <= 0)
		if(GLOB.chem_trace)
			log_world("CHEM: [src] is full and passed [round(mixture.total_volume, 0.001)]u into [where] unfiltered")
		return
	var/list/strengths = tag_strengths()
	var/room = capacity - used
	var/total = mixture.total_volume
	var/caught = 0
	var/list/caught_text = list()
	for(var/datum/reagent/R as anything in mixture.reagent_list.Copy())
		if(!istype(R, /datum/reagent/contaminant))
			continue
		var/strength = chem_filter_strength_against(strengths, R)
		if(!strength)
			continue
		var/datum/reagent/contaminant/C = R
		var/above_floor = max(R.volume - C.filter_floor * total, 0)
		var/taken = min(R.volume * strength * fresh, above_floor, room - caught)
		if(taken <= 0)
			continue
		caught += taken
		caught_text += "[R.id] [round(taken, 0.001)]"
		mixture.remove_reagent(R.id, taken, safety = 1)
	// A little of the product stays in the filter.
	var/product = mixture.total_volume - mixture.contaminant_volume()
	var/kept = min(product * retention, room - caught)
	if(kept > 0)
		var/share = kept / product
		for(var/datum/reagent/R as anything in mixture.reagent_list.Copy())
			if(!istype(R, /datum/reagent/contaminant))
				mixture.remove_reagent(R.id, R.volume * share, safety = 1)
	used += caught + max(kept, 0)
	if(GLOB.chem_trace)
		log_world("CHEM: [src] caught [round(caught, 0.001)]u ([jointext(caught_text, ", ") || "nothing"]) and kept back [round(max(kept, 0), 0.001)]u of product from a pour into [where]; [round(freshness() * 100)]% fresh")

/// What a paper or charcoal filter takes: tag => strength (0..1) while fresh. The book reads it by type.
/proc/chem_filter_strengths(filter_type)
	if(ispath(filter_type, /obj/item/chem_filter/paper))
		return list(CHEM_TAG_SOLID = FILTER_STRENGTH_MAX)
	if(ispath(filter_type, /obj/item/chem_filter/charcoal))
		return list(CHEM_TAG_NONPOLAR = FILTER_STRENGTH_MAX, CHEM_TAG_ORGANIC = FILTER_STRENGTH_MAX * 0.85)
	return list()

/// The contaminants (reagent id => strength) a filter with these tag strengths takes while fresh: what the book prints.
/proc/chem_filter_catches(list/strengths)
	var/list/caught = list()
	for(var/id in contaminant_ids())
		var/datum/reagent/contaminant/C = contaminant_def(id)
		var/strength = chem_filter_strength_against(strengths, C)
		if(strength > 0)
			caught[id] = strength
	return caught

/// Paper: catches the particulate.
/obj/item/chem_filter/paper
	name = "paper filter"
	desc = "A fluted paper filter. It catches particulate and nothing that is dissolved."
	capacity = 30
	retention = FILTER_RETENTION_PAPER

/obj/item/chem_filter/paper/tag_strengths()
	return chem_filter_strengths(type)

/// Charcoal: catches oils and organic residue.
/obj/item/chem_filter/charcoal
	name = "charcoal filter"
	desc = "A paper filter packed with activated charcoal. It catches oils and organic residue."
	icon_state = "pillA"
	capacity = 60
	retention = FILTER_RETENTION_CHARCOAL

/obj/item/chem_filter/charcoal/tag_strengths()
	return chem_filter_strengths(type)

/// A sorbent filter, made of a sheet of an engineered material: what it takes follows the material's sorption, catalytic and antimicrobial stats.
/obj/item/chem_filter/sorbent
	name = "sorbent filter"
	desc = "An ion-exchange filter lined with an engineered material. What it takes out of a pour depends on the material."
	capacity = 40
	retention = FILTER_RETENTION_SORBENT
	/// The registered name of the material it is made of.
	var/material_name = MAT_STEEL

CAPABILITIES(/obj/item/chem_filter/sorbent)
	param(nameof(material_name), pos = 1)
	setup(PROC_REF(line_with_material))

/// Named for its material; its capacity grows with its sorption.
/obj/item/chem_filter/sorbent/proc/line_with_material()
	var/datum/material/M = get_material_by_name(material_name)
	if(!M)
		return
	name = "[M.display_name] sorbent filter"
	capacity = 40 + 60 * sorption()

/// The material's sorption (0..1): its sorbent trait over 100.
/obj/item/chem_filter/sorbent/proc/sorption()
	var/datum/material/M = get_material_by_name(material_name)
	return M ? clamp(M.trait(MT_SORBENT) / 100, 0, 1) : 0

/// The material's catalytic activity (0..1).
/obj/item/chem_filter/sorbent/proc/catalysis()
	var/datum/material/M = get_material_by_name(material_name)
	return M ? clamp(M.trait(MT_CATALYTIC) / 100, 0, 1) : 0

/// The material's antimicrobial activity (0..1).
/obj/item/chem_filter/sorbent/proc/antimicrobial()
	var/datum/material/M = get_material_by_name(material_name)
	return M ? clamp(M.trait(MT_ANTIMICROBIAL) / 100, 0, 1) : 0

/obj/item/chem_filter/sorbent/tag_strengths()
	var/sorbed = sorption() * FILTER_STRENGTH_MAX
	var/catalysed = catalysis() * FILTER_STRENGTH_MAX
	return list(
		CHEM_TAG_IONIC = sorbed,
		CHEM_TAG_METALLIC = sorbed,
		CHEM_TAG_NONPOLAR = sorbed,
		CHEM_TAG_SULFUROUS = max(sorbed, catalysed),
		CHEM_TAG_OXIDISER = catalysed,
		CHEM_TAG_BIOLOGICAL = antimicrobial() * FILTER_STRENGTH_MAX,
	)

// A paper filter and a sheet of a material make a sorbent filter: the paper lines the sheet. The material is the sheet's; the stats are the batch's.
CAPABILITIES(/obj/item/chem_filter/paper)
	op("line_with_sheet", item(/obj/item/stack/material), label("Line the filter with a sheet"), then(PROC_REF(lined_with_sheet)))

/obj/item/chem_filter/paper/proc/lined_with_sheet(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/sheet = A.held
	if(!sheet.material || !sheet.use(1))
		return OP_OK
	var/obj/item/chem_filter/sorbent/made = new(get_turf(src), sheet.material.name)
	to_chat(user, span_notice("You line \the [src] with the sheet and make \a [made]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] made [made] ([made.material_name]): sorption [round(made.sorption(), 0.01)], catalysis [round(made.catalysis(), 0.01)], antimicrobial [round(made.antimicrobial(), 0.01)], capacity [round(made.capacity, 0.1)]")
	spent(src)
	user.put_in_hands(made)
	return OP_OK
