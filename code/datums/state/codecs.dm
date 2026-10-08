// Concrete chemistry and board codecs retain their domain implementations.
// ---------------------------------------------------------------------------
// reagents: the /datum/reagents holder, as its capacity and its reagents.
// ---------------------------------------------------------------------------
/datum/state_codec/reagents

/datum/state_codec/reagents/encode(datum/owner, var_name, value, datum/state_context/ctx)
	var/datum/reagents/holder = value
	if(isnull(holder))
		return null
	if(!istype(holder))
		ctx.refuse("[owner.type].[var_name] holds [holder], not a reagent holder")
		return null
	var/list/reagents = list()
	for(var/datum/reagent/R as anything in holder.reagent_list)
		var/data = isnull(R.data) ? null : ctx.encode_value(R.data, "[owner.type].[var_name] [R.id] data")
		reagents += list(list(R.id, R.volume, data))
	return list("max" = holder.maximum_volume, "list" = reagents)

/datum/state_codec/reagents/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	var/atom/A = owner
	if(!istype(A))
		ctx.refuse("the reagents codec needs an atom, got [owner.type]")
		return
	if(isnull(encoded))
		QDEL_NULL(A.reagents)
		return
	if(!A.reagents)
		A.create_reagents(encoded["max"])
	var/datum/reagents/holder = A.reagents
	holder.clear_reagents()
	holder.maximum_volume = encoded["max"]
	for(var/list/entry as anything in encoded["list"])
		// safety = TRUE: the saved mix was stable, so adding it back must not react.
		holder.add_reagent(entry[1], entry[2], ctx.decode_value(entry[3]), TRUE)

// ---------------------------------------------------------------------------
// frame_type: /obj/item/circuitboard/board_type (roadmap C6, containment.md
// section 5). Usually a /datum/frame/frame_types instance owned only by this
// board (an `owned` nested blob), but some boards set it to a plain string
// ("other") instead -- circuitboard.dm's own comment: "Some boards use text
// instead of an instance". frame_types itself needs no codec of its own: its
// vars (name, frame_size, frame_class, a circuit type path, frame_style,
// x_offset, y_offset, an icon_override resource) are all plain values the
// generic encoder already handles.
// ---------------------------------------------------------------------------
/datum/state_codec/frame_type

/datum/state_codec/frame_type/encode(datum/owner, var_name, value, datum/state_context/ctx)
	if(isnull(value))
		return null
	if(!isdatum(value))
		return ctx.encode_value(value, "[owner.type].[var_name]")
	if(isatom(value))
		ctx.refuse("[owner.type].[var_name] is a frame_type codec but holds an atom")
		return null
	var/list/nested = ctx.serialize_datum(value, NONE)
	if(!nested)
		return null
	return list(STATE_WRAP_OWNED = nested)

/datum/state_codec/frame_type/decode(datum/owner, var_name, encoded, datum/state_context/ctx)
	if(isnull(encoded))
		owner.vars[var_name] = null // ALLOW(api): state serializer codecs
		return
	if(!islist(encoded))
		owner.vars[var_name] = encoded // ALLOW(api): state serializer codecs
		return
	var/list/nested = encoded[STATE_WRAP_OWNED]
	owner.vars[var_name] = ctx.materialize_datum(nested) // ALLOW(api): state serializer codecs
