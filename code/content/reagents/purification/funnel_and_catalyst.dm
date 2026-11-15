// What a glass container takes besides its contents (code/content/reagents/purification/): a funnel on its mouth (with a filter in the funnel everything poured in
// goes through it, code/content/reagents/purification/filters.dm) and a catalyst in the glass (a sheet of a material with catalytic activity: the solid catalyst
// of the processes that run on one, code/domains/world_model/reagents/blocks/routes.dm).

/obj/item/reagent_containers/glass
	/// The funnel on the mouth of the container, or null.
	var/obj/item/chem_funnel/funnel
	/// A sheet of catalytic material lying in the container, or null: its activity widens the ideal temperature band of every recipe run in it.
	var/obj/item/stack/material/catalyst

MSG_DEF_SELF(glass/funnel_fitted, "There is a funnel in it already.")
MSG_DEF_SELF(glass/no_funnel, "There is no funnel on it.")
MSG_DEF_SELF(glass/catalyst_present, "There is a catalyst in it already.")
MSG_DEF_SELF(glass/no_catalyst, "There is no catalyst in it.")

/// What a glass container takes: a funnel on the mouth and a catalyst sheet in it, and gives them back.
CAPABILITY_DEF(glass_purification, CAP_GLASS_PURIFICATION, key = NONE)

/datum/capability/def/glass_purification/entries()
	return list(
		op("attach_funnel", item(/obj/item/chem_funnel), label("Fit the funnel"), \
			needs(req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_free))), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_attached))),
		op("remove_funnel", menu(), when(req_actor_kind(/mob/living)), label("Remove the funnel"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_fitted), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, funnel_removed))),
		op("add_catalyst", item(/obj/item/stack/material), when(TYPE_PROC_REF(/obj/item/reagent_containers/glass, catalyst_fits)), label("Drop a sheet in as a catalyst"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, catalyst_added))),
		op("remove_catalyst", menu(), when(req_actor_kind(/mob/living)), label("Take out the catalyst"), \
			needs(req_capable(), req(TYPE_PROC_REF(/obj/item/reagent_containers/glass, catalyst_lying), silent = TRUE)), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, catalyst_removed))))

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

// ---- the catalyst ----

/// A sheet of a material that works as a catalyst can go in, and there is no catalyst yet.
/obj/item/reagent_containers/glass/proc/catalyst_fits(datum/act/op/A)
	var/obj/item/stack/material/sheet = A.held
	return istype(sheet) && !catalyst && sheet.material?.trait(MT_CATALYTIC) > 0

/// There is a catalyst to take out.
/obj/item/reagent_containers/glass/proc/catalyst_lying(datum/act/op/A)
	return catalyst ? null : /datum/msg/req_failed

/// The activity (0..100) of the catalyst in the glass: 0 with none.
/obj/item/reagent_containers/glass/proc/catalyst_activity()
	return catalyst?.material ? clamp(catalyst.material.trait(MT_CATALYTIC), 0, 100) : 0

/// The kind of the solid catalyst in the glass (CHEM_CATALYST_SOLID_ACID for a porous material, else CHEM_CATALYST_SOLID_METAL), or null with none.
/obj/item/reagent_containers/glass/proc/catalyst_kind()
	if(!catalyst?.material)
		return null
	return catalyst.material.sorbed_volume() >= CHEM_SOLID_ACID_POROSITY ? CHEM_CATALYST_SOLID_ACID : CHEM_CATALYST_SOLID_METAL

/obj/item/reagent_containers/glass/proc/catalyst_added(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/sheet = A.held
	var/obj/item/stack/material/part = sheet.split(1, TRUE)
	if(!part)
		return OP_OK
	if(!move_into(src, nameof(src.catalyst), part, user))
		part.forceMove(get_turf(src))
		return OP_OK
	to_chat(user, span_notice("You drop a sheet of [catalyst.material.display_name] into \the [src]; it will help the processes that run on a solid catalyst."))
	if(GLOB.chem_trace)
		log_world("CHEM: [user] put a [catalyst_kind()] catalyst of activity [catalyst_activity()] ([catalyst.material.name]) in [src]")
	reagents?.handle_reactions() // a route that runs on it may go now
	return OP_OK

/obj/item/reagent_containers/glass/proc/catalyst_removed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/stack/material/sheet = catalyst
	if(!sheet)
		return OP_OK
	sheet.forceMove(get_turf(src))
	rel_take(src, nameof(catalyst))
	user.put_in_hands(sheet)
	to_chat(user, span_notice("You fish \the [sheet] out of \the [src]."))
	return OP_OK
