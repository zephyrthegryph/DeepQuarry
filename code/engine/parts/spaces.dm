// Physical spaces and doors (doc/rewrite/final_api.html, section 8 "Spaces and doors"; section 11 "The library").
//
// A holder has nested SPACES joined by DOORS. Every slot, op and part that is "inside" names its space (at(SPACE_X) on an op or a graph,
// at = SPACE_X on a slot); reaching it needs a path from the actor's side through open doors. One mechanism answers every "is the cover open?"
// question: the reach gate's walk up the containment ledger, the implicit requirement of an op placed at a space, Explain Interaction.
//
//   space(SPACE_X, inside =, door =, applies_to =, latched_while =, because =, from_stage =, missing =)
//        a space of the holder. inside: the space it sits in (null: the holder's outside). door: what closes it: a capability (CAP_COVER,
//        CAP_PANEL: the capability answers door_open()), a capability key (COVER_OPEN) or a holder var (nameof(opened)), true when open.
//        applies_to: the authorities the door stops (AUTH_PHYSICAL: a hand and telekinesis; a remote-access reach passes).
//        latched_while/because: the door cannot open while the condition holds (latch() below). from_stage/missing: the space exists only
//        from that construction stage on; before it, a path into it is refused with `missing`. closed: the reason a closed door gives (default:
//        the door capability's, "Its cover is closed.", or "It is closed." for a var).
//   latch(SPACE_X, condition, because)       the space's door cannot open while the condition holds (the APC's cover lock over a charged cell).
//   protrudes(SPACE_X, condition, because)   something in the space keeps its door from closing while the condition holds. As a part of a
//                                            stage() (protrudes(because = ...), no condition) it holds while the graph is at that stage (the
//                                            APC's loose board), in the graph's space unless it names one.
//   req_closed(SPACE_X)                      a requirement that the space's door is shut ("Close the cover first."): what works the outside of a
//                                            machine (an ID lock, an emag) while its insides are open.
//   req_space_empty(SPACE_X)                 nothing sits in a slot of the space or of a space inside it ("Remove the power cell first.").
//   size_is(min, max)                        a held item's w_class is in range, with generated reasons (too large, too small): a slot's fits =.
//   cell_bay(slot_var, at, accepts, starts, fits)   a one-item slot over a holder var, in space `at`.
//   telekinesis()                            a provider: AFF_MANIPULATE at TK_RANGE with line_of_sight. Spaces still gate it.
//
// The silent-or-refuse rule lives in resolution (code/engine/parts/resolve.dm): a candidate whose path is blocked is set aside, so another
// candidate answering the same input wins; when none does, the blocked one runs and Require refuses with the blocking door's reason.
// A door capability (cover(), panel()) checks its own latches and protrusions: its open op needs req_door_free(its cap id).

/// Today's TK_MAXRANGE, in tiles (section 8).
#define TK_RANGE TK_MAXRANGE

MSG_DEF_SELF(cover/closed, "Its cover is closed.")
MSG_DEF_SELF(cover/still_on, "Its cover is still on.")
MSG_DEF_SELF(cover/removed, "Its cover has been removed.")
MSG_DEF_SELF(space/closed, "It is closed.")
MSG_DEF_SELF(space/close_first, "Close it first.")
MSG_DEF_SELF(space/missing, "There is nowhere to put that yet.")
MSG_DEF_SELF(bay/full, "There is already something in there.")

// ---- doors ----

/// A capability that can be a space's door answers whether it is open now. The default is not a door: nothing is closed.
/datum/capability/proc/door_open(datum/holder)
	return TRUE

/// The reason shown while this door keeps its space closed.
/datum/capability/proc/door_closed_reason()
	return /datum/msg/space/closed

/// The reason shown when this door must be shut first.
/datum/capability/proc/door_close_first_reason()
	return /datum/msg/space/close_first

/// The state keys door_open() reads on `holder`.
/datum/capability/proc/door_keys(datum/holder)
	return list()

/// Is `door` (a capability id, a capability key id or a holder var) of `holder` open?
/proc/door_is_open(atom/holder, door)
	if(isnull(door))
		return TRUE
	if(istext(door))
		return (door in holder.vars) && !!holder.vars[door]
	var/datum/capability/def = cap_of(holder, door)
	if(def)
		return def.door_open(holder)
	return !!op_key_value(holder, door)

/// The reason a closed `door` gives.
/proc/door_reason_of(atom/holder, door)
	if(isnum(door))
		var/datum/capability/def = cap_of(holder, door)
		if(def)
			return def.door_closed_reason()
	return /datum/msg/space/closed

/// The reason "shut it first" of `door`.
/proc/door_shut_reason_of(atom/holder, door)
	if(isnum(door))
		var/datum/capability/def = cap_of(holder, door)
		if(def)
			return def.door_close_first_reason()
	return /datum/msg/space/close_first

/// A short name of a door, for Explain Interaction.
/proc/door_name(atom/holder, door)
	if(istext(door))
		return door
	if(isnum(door))
		var/datum/capability/def = cap_of(holder, door)
		if(def)
			return "[def.cap_id == CAP_COVER ? "cover" : (def.cap_id == CAP_PANEL ? "panel" : "[def.type]")]"
	return "[door]"

/// The (entity, key) reads of `door` on `holder`.
/proc/door_read_keys(atom/holder, door)
	. = list()
	if(isnull(door))
		return
	var/list/keys = list()
	if(istext(door))
		keys += door
	else
		var/datum/capability/def = cap_of(holder, door)
		keys += def ? def.door_keys(holder) : list(door)
	for(var/key in keys)
		for(var/read_key in change_read_keys(holder, key))
			. += list(list(holder, read_key))

// ---- space ----

CAPABILITY_TYPE(space, CAP_SPACE, /datum/capability/lib/space, key = id, id = null, inside = null, door = null, applies_to = AUTH_PHYSICAL, latched_while = null, because = null, from_stage = null, missing = null, closed = null)

/datum/capability/lib/space/entries()
	. = list(entry_make(ENTRY_SPACE, null, list("id" = id, "inside" = inside, "door" = door, "applies_to" = applies_to, "from_stage" = from_stage, "missing" = missing, "closed" = closed)))
	if(!isnull(latched_while))
		. += latch(id, latched_while, because)

/// latch(SPACE_X, condition, because): the space's door cannot open while the condition holds.
/proc/latch(space_id, condition, because = null)
	return entry_make(ENTRY_LATCH, null, list("space" = space_id, "cond" = condition, "because" = because))

/// protrudes(SPACE_X, condition, because): something in the space keeps its door from closing while the condition holds. Inside a stage() it
/// takes no condition (the stage is the condition) and its space defaults to the graph's.
/proc/protrudes(space_id = null, condition = null, because = null)
	return entry_make(ENTRY_PROTRUSION, null, list("space" = space_id, "cond" = condition, "because" = because))

/// The space entry `id` of `holder`, as its args list, or null.
/proc/space_def(atom/holder, id)
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_SPACE))
		var/datum/entry/E = C.item
		if(E.args["id"] == id)
			return E.args
	return null

/// The chain of spaces from `id` out to the holder's outside: list(id, its parent, ...). An undeclared space is its own chain.
/proc/space_chain(atom/holder, id)
	. = list()
	var/guard = 0
	while(!isnull(id) && guard++ < 16)
		. += id
		var/list/def = space_def(holder, id)
		id = def ? def["inside"] : null

/// The space of `holder` that `inside` sits in (a var slot or a containment-ledger slot placed at a space), or null.
/atom/proc/space_holding(atom/inside)
	for(var/datum/centry/C as anything in compiled_entries(table_of(src), ENTRY_SPACE_SLOT))
		var/datum/entry/E = C.item
		if(vars[E.args["var"]] == inside)
			return E.args["space"]
	if(!ismovable(inside))
		return null
	var/datum/om/relation/slot/def = dq_path_slot_of(src, inside) // a ledger slot placed at a space (its `at`)
	return def?.at

/// The hops of the path from the actor's side to space `id`: list(list(space, inward)), the spaces whose boundary the path crosses. The actor
/// outside the holder starts at its outside; an actor inside a space of the holder (shut in a locker) starts there and walks out first.
/proc/space_path(atom/holder, id, mob/actor)
	var/list/to_target = space_chain(holder, id)
	var/list/from_actor = list()
	if(actor && actor.loc == holder)
		from_actor = space_chain(holder, holder.space_holding(actor))
	var/list/common = to_target & from_actor
	. = list()
	for(var/s in from_actor)
		if(s in common)
			break
		. += list(list(s, FALSE))
	var/list/inward = list()
	for(var/s in to_target)
		if(s in common)
			break
		inward.Insert(1, list(list(s, TRUE)))
	. += inward

/// Why the path from `actor` to space `id` of the holder is blocked for `authority`, or null: the first space on the path that is not built yet
/// (its `missing`), or whose door is closed to that authority (the door's reason).
/atom/proc/space_reason(id, authority, mob/actor = null)
	if(isnull(id))
		return null
	authority = authority || AUTH_PHYSICAL
	for(var/list/hop as anything in space_path(src, id, actor))
		var/list/def = space_def(src, hop[1])
		if(!def)
			continue
		if(!isnull(def["from_stage"]) && !built(src, def["from_stage"]))
			return def["missing"] || /datum/msg/space/missing
		if(!(authority & def["applies_to"]) || isnull(def["door"]))
			continue
		if(!door_is_open(src, def["door"]))
			return def["closed"] || door_reason_of(src, def["door"])
	return null

/// The state reads the path to space `id` depends on, for read_keys(): every door on the chain and the construction graph.
/atom/proc/space_read_keys(id)
	. = list()
	for(var/s in space_chain(src, id))
		var/list/def = space_def(src, s)
		if(!def)
			continue
		. += door_read_keys(src, def["door"])
		if(!isnull(def["from_stage"]))
			. += list(list(src, "graph:[CAP_CONSTRUCTION]"))

/// The reason a thing inside this container is not reachable from `actor` now (a closed door on the way), or null.
/atom/proc/space_blocked(atom/inside, authority, mob/actor = null)
	var/id = space_holding(inside)
	return isnull(id) ? null : space_reason(id, authority, actor)

/// One line per hop of the path to space `id`, for Explain Interaction: "hatch (door cover: closed)".
/proc/space_path_text(atom/holder, id, mob/actor, authority)
	var/list/hops = list()
	for(var/list/hop as anything in space_path(holder, id, actor))
		var/list/def = space_def(holder, hop[1])
		var/text = "[hop[2] ? "into" : "out of"] [hop[1]]"
		if(def)
			if(!isnull(def["from_stage"]) && !built(holder, def["from_stage"]))
				text += " (not built until [stage_key(def["from_stage"])]: [reason_text(def["missing"] || /datum/msg/space/missing)])"
			else if(!isnull(def["door"]))
				var/open = door_is_open(holder, def["door"])
				text += " (door [door_name(holder, def["door"])]: [open ? "open" : "closed"][!(authority & def["applies_to"]) ? ", not for this authority" : ""])"
		hops += text
	return length(hops) ? "outside -> [jointext(hops, " -> ")]" : "outside"

// ---- latches and protrusions ----

/// Why the door of space `id` cannot move now, or null: shut, a latch whose condition holds; open, a protrusion that holds.
/proc/space_door_hold_reason(datum/act/op/A, id)
	var/atom/holder = A.holder
	var/list/def = space_def(holder, id)
	if(!def)
		return null
	var/datum/type_table/T = table_of(holder)
	if(door_is_open(holder, def["door"]))
		for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_PROTRUSION))
			var/datum/entry/E = C.item
			if(E.args["space"] == id && op_cond(A, E.args["cond"]))
				return space_hold_because(A, E.args["because"])
		for(var/cap_id in list(CAP_CONSTRUCTION, CAP_DEPLOYMENT))
			var/datum/capability/construction/graph_def = cap_of(holder, cap_id)
			var/datum/state_graph/G = graph_def?.graph
			if(!G)
				continue
			for(var/datum/graph_edge/edge as anything in graph_edges_into(G, graph_current(holder, cap_id)))
				if(edge.protrudes && (edge.protrudes["space"] || G.space) == id)
					return space_hold_because(A, edge.protrudes["because"])
		return null
	for(var/datum/centry/C as anything in compiled_entries(T, ENTRY_LATCH))
		var/datum/entry/E = C.item
		if(E.args["space"] == id && op_cond(A, E.args["cond"]))
			return space_hold_because(A, E.args["because"])
	return null

/// A because of a latch or protrusion: a message type, text, or a handler (PROC_REF) answering one.
/proc/space_hold_because(datum/act/op/A, because)
	if(istext(because) && !ispath(because))
		var/answer = op_call(A, because)
		if(answer)
			return answer
	return because || /datum/msg/req_failed

/// req_door_free(DOOR): the door (a capability id) is not held: each space it closes has no latch holding it shut and no protrusion holding
/// it open. What cover() and panel() put on their own open ops, so no type writes a needs() for it.
/proc/req_door_free(door)
	return part_make(/datum/entry/part/req/door_free, list("door" = door))

/datum/entry/part/req/door_free
	part_name = "req_door_free"

/datum/entry/part/req/door_free/holds(datum/act/op/A)
	return isnull(door_free_reason(A))

/datum/entry/part/req/door_free/refusal(datum/act/op/A)
	return door_free_reason(A) || default_reason

/datum/entry/part/req/door_free/proc/door_free_reason(datum/act/op/A)
	var/atom/holder = A.holder
	if(!istype(holder))
		return null
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_SPACE))
		var/datum/entry/E = C.item
		if(E.args["door"] == src.args["door"])
			var/why = space_door_hold_reason(A, E.args["id"])
			if(why)
				return why
	return null

/datum/entry/part/req/door_free/read_keys(datum/act/op/A)
	var/atom/holder = A.holder
	. = istype(holder) ? door_read_keys(holder, src.args["door"]) : list()
	if(istype(holder))
		. += list(list(holder, "graph:[CAP_CONSTRUCTION]"))

/// req_closed(SPACE_X): the door of the space is shut, else the door's "close it first" reason.
/proc/req_closed(space_id)
	return part_make(/datum/entry/part/req/space_closed, list("space" = space_id))

/datum/entry/part/req/space_closed
	part_name = "req_closed"
	default_reason = /datum/msg/space/close_first

/datum/entry/part/req/space_closed/holds(datum/act/op/A)
	var/atom/holder = A.holder
	var/list/def = istype(holder) ? space_def(holder, src.args["space"]) : null
	return !def || isnull(def["door"]) || !door_is_open(holder, def["door"])

/datum/entry/part/req/space_closed/refusal(datum/act/op/A)
	var/atom/holder = A.holder
	var/list/def = istype(holder) ? space_def(holder, src.args["space"]) : null
	return def ? door_shut_reason_of(holder, def["door"]) : default_reason

/datum/entry/part/req/space_closed/read_keys(datum/act/op/A)
	var/atom/holder = A.holder
	var/list/def = istype(holder) ? space_def(holder, src.args["space"]) : null
	return def ? door_read_keys(holder, def["door"]) : list()

/// req_space_open(SPACE_X): the path to the space is open for the act's authority. A condition and a requirement; an op placed at(SPACE_X)
/// gets it implicitly (Require), so content rarely names it.
/datum/entry/part/req/space_open
	part_name = "req_space_open"
	default_reason = /datum/msg/space/closed

/proc/req_space_open(space_id)
	return part_make(/datum/entry/part/req/space_open, list("space" = space_id))

/datum/entry/part/req/space_open/holds(datum/act/op/A)
	var/atom/holder = A.holder
	return !istype(holder) || isnull(holder.space_reason(src.args["space"], A.authority || AUTH_PHYSICAL, A.actor))

/datum/entry/part/req/space_open/refusal(datum/act/op/A)
	var/atom/holder = A.holder
	return (istype(holder) && holder.space_reason(src.args["space"], A.authority || AUTH_PHYSICAL, A.actor)) || default_reason

/datum/entry/part/req/space_open/read_keys(datum/act/op/A)
	var/atom/holder = A.holder
	return istype(holder) ? holder.space_read_keys(src.args["space"]) : list()

/// req_space_empty(SPACE_X): no slot of the space, or of a space inside it, holds anything. The reason names what is there.
/proc/req_space_empty(space_id)
	return part_make(/datum/entry/part/req/space_empty, list("space" = space_id))

/datum/entry/part/req/space_empty
	part_name = "req_space_empty"

/datum/entry/part/req/space_empty/holds(datum/act/op/A)
	return isnull(space_occupant(A.holder, src.args["space"]))

/datum/entry/part/req/space_empty/refusal(datum/act/op/A)
	var/atom/movable/thing = space_occupant(A.holder, src.args["space"])
	return thing ? "Remove \the [thing] first." : default_reason

/datum/entry/part/req/space_empty/read_keys(datum/act/op/A)
	. = list()
	var/atom/holder = A.holder
	if(!istype(holder))
		return
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_SPACE_SLOT))
		var/datum/entry/E = C.item
		for(var/key in change_read_keys(holder, E.args["var"]))
			. += list(list(holder, key))

/// The first thing in a var slot of space `id` of `holder` or of a space inside it, or null.
/proc/space_occupant(atom/holder, id)
	if(!istype(holder))
		return null
	for(var/datum/centry/C as anything in compiled_entries(table_of(holder), ENTRY_SPACE_SLOT))
		var/datum/entry/E = C.item
		if(!(id in space_chain(holder, E.args["space"])))
			continue
		var/atom/movable/thing = holder.vars[E.args["var"]]
		if(istype(thing))
			return thing
	return null

// ---- slot acceptance ----

MSG_DEF_SELF(slot/too_large, "That is too large to fit.")
MSG_DEF_SELF(slot/too_small, "That is too small to fit.")

/// size_is(min, max): the held item's w_class is between min and max (max defaults to min). Refused with "too large" or "too small".
/proc/size_is(min_size, max_size = null)
	return part_make(/datum/entry/part/req/size_is, list("min" = min_size, "max" = isnull(max_size) ? min_size : max_size))

/datum/entry/part/req/size_is
	part_name = "size_is"

/datum/entry/part/req/size_is/holds(datum/act/op/A)
	var/obj/item/held = A.held
	return !istype(held) || (held.w_class >= src.args["min"] && held.w_class <= src.args["max"])

/datum/entry/part/req/size_is/refusal(datum/act/op/A)
	var/obj/item/held = A.held
	return (istype(held) && held.w_class < src.args["min"]) ? /datum/msg/slot/too_small : /datum/msg/slot/too_large

// ---- cell bay ----

CAPABILITY_TYPE(cell_bay, CAP_CELL_BAY, /datum/capability/lib/cell_bay, key = slot_var, slot_var = null, at = null, accepts = /obj/item/cell, starts = null, starts_args = null, fits = null)

/// A power cell slot over a holder var (`slot_var`, nameof(cell)), in space `at` when given: cell_bay.<var>.insert (a cell in hand goes in, when
/// it `fits`: size_is(ITEMSIZE_NORMAL)) and cell_bay.<var>.take (an empty hand takes it out). Both are placed at(at), so the path decides: a
/// closed door sets them aside for whatever else the click means, and refuses with its reason when nothing else does. The cell shows through
/// an open cover (a look layer), examine says what it holds, and cell_charge_percent() reads its charge through the bay. `starts` (any starts =
/// form of section 6, with starts_args) fills the bay when the holder initializes.
/datum/capability/lib/cell_bay
	holder_hooks = HOLDER_HOOK_INIT

MSG_DEF_SELF(cell_bay/missing, "The power cell is missing.")

/datum/capability/lib/cell_bay/entries()
	var/list/entries = list()
	var/list/at_space = list()
	var/visible = slot_var
	if(!isnull(at))
		entries += entry_make(ENTRY_SPACE_SLOT, null, list("var" = slot_var, "space" = at))
		at_space += global.at(at)
		// every space a cell bay sits in today is behind a cover: the cell shows while the cover is open and on
		visible = cond_all(slot_var, COVER_OPEN, cond_not(COVER_REMOVED))
	entries += op("insert", item(accepts), put_in(slot_var), at_space, fits ? needs(fits) : null)
	entries += op("take", hand(), ungated(), when(slot_var), take_out(slot_var), at_space)
	entries += look_layer(LOOK_CELL, when = visible)
	entries += examine_line(CAP_PROC(examine_cell), reads = list(slot_var))
	return entries

/// The charge meter (or the missing cell, when the bay can be seen into).
/datum/capability/lib/cell_bay/proc/examine_cell(datum/act/A)
	var/obj/item/cell/C = A.holder.vars[slot_var]
	if(!istype(C))
		var/atom/holder = A.holder
		return (!isnull(at) && istype(holder) && isnull(holder.space_reason(at, AUTH_PHYSICAL))) ? "The power cell is missing." : null
	return "The charge meter reads [round(C.percent())]%."

/// The bay starts with a thing when its holder initializes: any starts = form (starts_make(): a type, nameof(var) of a holder var holding one,
/// pick_one(), when(cond, T), PROC_REF(x)) with starts_args. A var a mapper already filled keeps what it holds.
/datum/capability/lib/cell_bay/on_holder_init(datum/act/eval/A)
	var/atom/holder = A.holder
	if(isnull(starts) || !istype(holder) || !isnull(holder.vars[slot_var]))
		return
	for(var/atom/movable/thing in starts_make(holder, starts, starts_args, holder))
		if(isnull(holder.vars[slot_var]))
			varslot_set(holder, slot_var, thing)
		else
			qdel(thing) // ALLOW(lifecycle): a one-item bay keeps the first thing a list-valued starts made; the rest were never placed

/datum/capability/lib/cell_bay/output_reads(hook)
	return list(slot_var)

/// The charge of A's cell bay in percent: 0 with no cell (never null).
/proc/cell_charge_percent(atom/A)
	READS_FROM()
	var/datum/type_table/T = table_of(A)
	for(var/key in T.caps)
		var/datum/capability/lib/cell_bay/bay = T.caps[key]
		if(istype(bay) && bay.cap_id == CAP_CELL_BAY)
			var/obj/item/cell/cell = A.vars[bay.slot_var]
			return istype(cell) ? cell.percent() : 0
	return 0

// ---- slots over a holder var ----

/// Is `slot_id` a one-item slot over a var of the holder (a cell_bay()), rather than a slot of the containment ledger?
/proc/op_var_slot(atom/holder, slot_id)
	if(!istext(slot_id) || !(slot_id in holder.vars))
		return FALSE
	for(var/datum/om/relation/slot/def as anything in dq_slot_defs_for(holder))
		if(def.slot_id == slot_id)
			return FALSE
	return TRUE

/// Sets the var of a var-slot to `thing` (which is in the holder) or empties it.
/proc/varslot_set(atom/holder, var_name, atom/movable/thing)
	if(rel_kind(holder, var_name) == OWNK_OWN) // a declared owned var: the ownership accessors stamp it and dispose of what it displaces
		if(isnull(thing))
			rel_take(holder, var_name)
		else
			rel_set(holder, var_name, thing)
		return
	holder.vars[var_name] = thing // ALLOW(api): the one writer of a one-item slot over a var: the bay capability's own slot
	changed(holder, CHANGE_EXPLICIT, var_name)

/// Why `thing` cannot go into the var-slot, or null.
/proc/varslot_refusal(atom/holder, var_name, atom/movable/thing, mob/actor)
	if(!isnull(holder.vars[var_name]))
		return /datum/msg/bay/full
	return own_transfer_refusal(holder, thing, null, actor)

/// Puts `thing` into the var-slot of the holder. TRUE when it went in.
/proc/varslot_insert(atom/holder, var_name, atom/movable/thing, mob/actor)
	if(varslot_refusal(holder, var_name, thing, actor))
		return FALSE
	if(rel_kind(holder, var_name) == OWNK_OWN) // a declared owned var: the one transfer moves it in and adopts it
		return move_into(holder, var_name, thing, actor)
	if(!own_bring_in(holder, var_name, thing, null, actor, TRUE, null, FALSE)) // an undeclared var: placed, then the bay writes the var
		return FALSE
	varslot_set(holder, var_name, thing)
	return TRUE

/// Takes what the var-slot holds out: into the carrier that took it (a cyborg's gripper) or the actor's hand when it can take it, else onto the floor.
/// The thing, or null when the slot is empty.
/proc/varslot_take(atom/holder, var_name, mob/actor, obj/item/carrier = null)
	var/atom/movable/thing = holder.vars[var_name]
	if(!istype(thing))
		return null
	varslot_set(holder, var_name, null)
	var/obj/item/as_item = thing
	if(carrier && istype(as_item) && carrier.can_carry(as_item, actor) && carrier.carry(as_item, actor))
		return thing
	if(actor && istype(as_item) && actor.put_in_hands(as_item))
		return thing
	thing.forceMove(get_turf(actor || holder))
	return thing

// ---- telekinesis ----

CAPABILITY_DEF(telekinesis, CAP_TELEKINESIS, key = NONE)

/// A provider of AFF_MANIPULATE with a reach of TK_RANGE tiles and line_of_sight = TRUE: any hand op on a target it can see in range. No tool or
/// attack affordances; compartments and requirements still apply.
/datum/capability/def/telekinesis/entries()
	return list(provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE))

/// The key tk_refresh() publishes (the reads of the tk_ready() condition).
#define TK_KEY "telekinesis_ready"

/// Can this mob reach out with its mind now? A TK mutation, or powered kinesis gloves (has_telegrip()), and not through a remote view (the old adapter refused
/// that too: a remote viewer that could TK would act from two places). A condition: it reads and writes nothing.
/mob/proc/tk_ready(datum/act/A)
	return has_telegrip() && !is_remote_viewing()

/// The telekinesis provider of a mob while it is tk_ready(): the telekinesis() provider, held by a condition instead of a grant, so a mutation or the power of
/// a pair of gloves needs no bookkeeping (the condition is read when the provider set is read). AFF_TELEKINESIS marks it for the tk() binding; a hand op
/// needs only AFF_MANIPULATE, so it does any hand op on a target in range and in sight, used only when nothing nearer reaches. A mutation added or removed, or
/// a glove's power spent, calls tk_refresh().
/proc/telekinetic_reach()
	return when(TYPE_PROC_REF(/mob, tk_ready), provides(AFF_MANIPULATE | AFF_TELEKINESIS, reach = TK_RANGE, line_of_sight = TRUE), reads = list(TK_KEY))

/// The telekinesis state of this mob changed: its provider set did, and the menus cached on it are stale.
/mob/proc/tk_refresh()
	if(QDELETED(src))
		return
	provider_set_changed(src)
	publish_change(src, TK_KEY)
