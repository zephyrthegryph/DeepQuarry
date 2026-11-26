// What a glass container takes besides its contents (code/content/reagents/purification/): a funnel on its mouth (with a filter in the funnel everything poured in
// goes through it, code/content/reagents/purification/filters.dm), solids in the glass (small items that dissolve in the liquid or, left whole, work as the solid
// catalyst of the processes that run on one: code/content/reagents/purification/solids.dm) and a clip-on electrode pair.

/obj/item/reagent_containers/glass
	/// The funnel on the mouth of the container, or null.
	var/obj/item/chem_funnel/funnel
	/// The small items lying in the container (at most CHEM_SOLIDS_MAX): each dissolves when the liquid can dissolve it; one that does not and is made of a catalytic
	/// material widens the ideal temperature band of every recipe run in it (code/content/reagents/purification/solids.dm).
	var/list/obj/item/solids
	/// How far each solid that is dissolving has got (a record per solid; one that is not dissolving has none).
	var/list/datum/solid_progress/dissolutions
	/// When the solids were last stepped (CLOCK_WORLD): the dissolving counts the time since, whoever asks.
	var/dissolve_at = 0
	/// The clip-on electrode pair dipping into the liquid, or null: what an electrolysis needs besides a hot plate that is on.
	var/obj/item/chem_electrode/electrode

MSG_DEF_SELF(glass/electrode_fitted, "There is an electrode pair on it already.")
MSG_DEF_SELF(glass/no_electrode, "There is no electrode pair on it.")
MSG_DEF_SELF(glass/funnel_fitted, "There is a funnel in it already.")
MSG_DEF_SELF(glass/no_funnel, "There is no funnel on it.")

/// What a glass container takes: a funnel on the mouth, small solids in it and an electrode pair, and gives them back.
CAPABILITY_DEF(glass_purification, CAP_GLASS_PURIFICATION, key = NONE)

/datum/capability/def/glass_purification/entries()
	return list(
		op("attach_funnel", item(/obj/item/chem_funnel), label("Fit the funnel"), \
			needs(req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_free))), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_attached))),
		op("remove_funnel", menu(), when(req_actor_kind(/mob/living)), label("Remove the funnel"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_fitted), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_removed))),
		op("attach_electrode", item(/obj/item/chem_electrode), label("Clip the electrodes on"), \
			needs(req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, electrode_free))), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, electrode_attached))),
		op("remove_electrode", menu(), when(req_actor_kind(/mob/living)), label("Take the electrodes off"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, electrode_fitted), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, electrode_removed))),
		// Last of the item ops (the lowest tier of the band) and gated to what no other op of the glass takes: a funnel, an electrode pair and a container are never dropped in.
		op("add_solid", item(/obj/item), stance(I_HELP), priority(OP_PRIORITY_DEFAULT), when(TYPE_PROC_REF(/obj/item/reagent_containers/glass, solid_fits)), label("Drop it in"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, solid_added))),
		op("remove_solids", menu(), when(req_actor_kind(/mob/living)), label("Take out the solids"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, solids_lying), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, solids_removed))))

// ---- the funnel ----

/// A funnel can go on.
/obj/item/reagent_containers/glass/proc/funnel_free(datum/act/op/A)
	return funnel ? MSG(glass/funnel_fitted) : null

/// There is a funnel to take off.
/obj/item/reagent_containers/glass/proc/funnel_fitted(datum/act/op/A)
	return funnel ? null : /datum/msg/req_failed

/// The filter in the funnel on the mouth, or null: what everything poured in passes through.
/obj/item/reagent_containers/glass/proc/funnel_filter()
	RETURN_TYPE(/obj/item/chem_filter)
	return funnel?.filter

/obj/item/reagent_containers/glass/proc/funnel_attached(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_funnel/F = A.held
	if(!move_into(src, nameof(src.funnel), F, user))
		return OP_OK
	to_chat(user, span_notice("You fit \the [F] into the mouth of \the [src]."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] fitted [F] ([F.filter ? F.filter.name : "no filter"]) on [src]")
	return OP_OK

/obj/item/reagent_containers/glass/proc/funnel_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_funnel/F = funnel
	if(!F)
		return OP_OK
	F.forceMove(get_turf(src))
	rel_take(src, nameof(funnel))
	user.put_in_hands(F)
	to_chat(user, span_notice("You take \the [F] off \the [src]."))
	return OP_OK

// ---- the electrode pair ----

/// An electrode pair can clip on.
/obj/item/reagent_containers/glass/proc/electrode_free(datum/act/op/A)
	return electrode ? MSG(glass/electrode_fitted) : null

/// There is an electrode pair to take off.
/obj/item/reagent_containers/glass/proc/electrode_fitted(datum/act/op/A)
	return electrode ? null : /datum/msg/req_failed

/obj/item/reagent_containers/glass/proc/electrode_attached(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_electrode/E = A.held
	if(!move_into(src, nameof(src.electrode), E, user))
		return OP_OK
	to_chat(user, span_notice("You clip \the [E] onto \the [src]; the leads dip into the liquid. An electrolysis needs it on a hot plate that is on."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] clipped [E] on [src]")
	reagents?.handle_reactions() // an electrolysis may go now, if the plate is on
	return OP_OK

/obj/item/reagent_containers/glass/proc/electrode_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/chem_electrode/E = electrode
	if(!E)
		return OP_OK
	E.forceMove(get_turf(src))
	rel_take(src, nameof(electrode))
	user.put_in_hands(E)
	to_chat(user, span_notice("You unclip \the [E] from \the [src]."))
	return OP_OK

/// A clip-on electrode pair: two leads on a clip that dip into a glass container. Stood on a hot plate that is on, the plate's current runs through the liquid
/// (the electrolysis process: code/content/reagents/blocks/processes.dm).
/obj/item/chem_electrode
	name = "electrode pair"
	desc = "Two graphite leads on a spring clip. Clip it onto a beaker, stand the beaker on a hot plate that is on, and the current runs through the liquid."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "dropper0"
	w_class = ITEMSIZE_SMALL
