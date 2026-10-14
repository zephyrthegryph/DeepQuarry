// wiper(...) (doc/rewrite/final_api.html, section 11; section 16.5): a cloth that soaks up liquid and wipes things with it. On top of reagent_container(); what
// wiping does to the thing (atom/on_rag_wipe()) and what the cloth does to itself (its name, its fire) is the holder type's own.
//
//   CAPABILITIES(/obj/item/reagent_containers/glass/rag,
//       reagent_container(volume = nameof(volume), needle = TRUE, settable = FALSE, shows_contents = FALSE),
//       wiper(soaks_from = list(...), burning = nameof(rag_lit)))
//
// `soaks_from` is the types a click soaks it from; `burning` the holder var that says it is alight (a burning cloth wipes and wrings nothing).
//
// Ops (all "wiper.<name>"):
//   soak       a click on a tank, a bucket: it takes as much as it holds
//   wring_into a click on an open container: it is wrung out into it, five deciseconds a unit
//   wipe       a click on anything else that is not a person: three seconds, then atom/on_rag_wipe(); a dry cloth refuses
//
// Wiping a person is the holder type's (a cloth may smother or set alight); `wipe_person` is the op for it, with its effect the type's own.

CAPABILITY_TYPE(wiper, CAP_WIPER, /datum/capability/lib/wiper, key = NONE, soaks_from = null, burning = null, wipe_time = 30)

MSG_DEF_SELF(wiper/already_soaked, "It is already soaked.")
MSG_DEF_SELF(wiper/dry, "It is dry!")
MSG_DEF(wiper/begin_wipe, "You start to wipe %T% with %I%.", "%U% starts to wipe %T% with %I%.")
MSG_DEF(wiper/soaked, "You soak %I% using %T%.", "%U% soaks %I% using %T%.")
MSG_DEF(wiper/wrung, "You finish wringing out %I% over %T%.", "%U% wrings out %I% over %T%.")
MSG_DEF(wiper/begin_wring, "You begin to wring out %I% over %T%.", "%U% begins to wring out %I% over %T%.")
MSG_DEF(wiper/wiped, "You finish wiping %T%!", "%U% finishes wiping %T%!")

/datum/capability/lib/wiper/entries()
	var/list/soaks = list()
	for(var/type in soaks_from)
		soaks += list(at_target(type))
	return list(
		length(soaks) ? op("soak", inputs(arglist(soaks)), when(CAP_PROC(is_dry_of_flame)), priority(OP_PRIORITY_PART + 2), label("Soak it"),
			needs(req_reagent_room(of = ON_HOLDER, because = MSG(wiper/already_soaked))), then(CAP_PROC(soaked)), says(MSG(wiper/soaked))) : null,
		op("wring_into", at_target(), when(CAP_PROC(target_is_wrung_into)), priority(OP_PRIORITY_PART + 1), label("Wring it out"),
			begins(MSG(wiper/begin_wring)), wait(CAP_PROC(wring_time)), then(CAP_PROC(wrung)), says(MSG(wiper/wrung))),
		op("wipe", at_target(), when(CAP_PROC(target_is_wiped)), priority(OP_PRIORITY_PART), label("Wipe it"),
			needs(req_reagents(1, because = MSG(wiper/dry))), begins(MSG(wiper/begin_wipe)), wait(CAP_PROC(wipe_wait)), then(CAP_PROC(wiped)), says(MSG(wiper/wiped))))

/// The cloth is not alight (a burning one wipes and wrings nothing and soaks nothing).
/datum/capability/lib/wiper/proc/is_dry_of_flame(datum/act/op/A)
	var/atom/holder = A.holder
	return isnull(burning) || !holder.vars[burning]

/// The clicked thing is an open container that is not what the one wringing carries.
/datum/capability/lib/wiper/proc/target_is_wrung_into(datum/act/op/A)
	var/atom/target = A.target
	var/mob/user = A.actor
	var/atom/holder = A.holder
	return is_dry_of_flame(A) && !isnull(target?.reagents) && target.is_open_container() && !(target in user) && !!holder.reagents?.total_volume

/// Anything that is not a person and not what is wrung into.
/datum/capability/lib/wiper/proc/target_is_wiped(datum/act/op/A)
	var/atom/target = A.target
	if(!is_dry_of_flame(A) || isnull(target) || ismob(target))
		return FALSE
	return !(target.reagents && target.is_open_container() && !(target in A.actor))

/datum/capability/lib/wiper/proc/wring_time(datum/act/op/A)
	var/atom/holder = A.holder
	return holder.reagents.total_volume * 5

/datum/capability/lib/wiper/proc/wipe_wait(datum/act/op/A)
	return wipe_time

/// It takes what it can hold from the tank or bucket.
/datum/capability/lib/wiper/proc/soaked(datum/act/op/A)
	var/atom/holder = A.holder
	var/atom/source = A.target
	if(!source.reagents?.trans_to_obj(holder, holder.reagents.maximum_volume))
		return OP_REFUSED
	return OP_OK

/// Wrung out into the container.
/datum/capability/lib/wiper/proc/wrung(datum/act/op/A)
	var/atom/holder = A.holder
	if(!holder.reagents.total_volume)
		return OP_REFUSED
	holder.reagents.trans_to(A.target, holder.reagents.total_volume)
	return OP_OK

/// What it wiped is told so.
/datum/capability/lib/wiper/proc/wiped(datum/act/op/A)
	var/atom/target = A.target
	target.on_rag_wipe(A.holder)
	return OP_OK
