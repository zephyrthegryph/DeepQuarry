// Requirements (doc/rewrite/dx_conventions.md, "Operations").
//
// A /datum/req is a flyweight: one shared, immutable datum per distinct declaration, built by the
// constructors below (req(), req_set(), ...) and interned, so two types that declare the same
// requirement share it. It answers two questions about an operation context (/datum/op_ctx):
//   test(ctx)   null when it holds, else the reason: a /datum/msg type (the "reason key"). A reason
//               that needs detail (a proc's own refusal text) puts it in ctx.detail.
//   reads(ctx)  the (datum, key) pairs the answer depends on, list(list(datum, key), ...): a pending
//               operation cancels early when one of them is published (op_reads_changed()).
// Requirements never write anything.
//
//	needs = list(req_set(CAP_PANEL_OPEN), req_access(), any_of(req(/obj/item/screwdriver), req_part(/obj/item/stock_parts/cell)))

// ---- reasons ----

/// The reason of req(..., silent = TRUE): no text, so the refused actor is told nothing.
MSG_DEF_SELF(req_silent, "")
MSG_DEF_SELF(req_refused, "%DETAIL%")
MSG_DEF_SELF(req_hand_full, "You need an empty hand for that.")
MSG_DEF_SELF(req_no_provider, "You have nothing to do that with.")
MSG_DEF_SELF(req_no_route, "You can't do that that way.")
MSG_DEF_SELF(req_out_of_reach, "You can't reach it.")
MSG_DEF_SELF(req_not_capable, "You can't do that right now.")
MSG_DEF_SELF(req_wrong_item, "That isn't the right thing to use.")
MSG_DEF_SELF(req_wrong_state, "It isn't in the right state for that.")
MSG_DEF_SELF(req_no_access, "Access denied.")
MSG_DEF_SELF(req_wire_cut, "A wire it needs is cut.")
MSG_DEF_SELF(req_no_part, "It is missing a part.")
MSG_DEF_SELF(req_forbidden, "Not while things are as they are.")
MSG_DEF_SELF(req_sealed, "Something in the way stops you.")
MSG_DEF_SELF(req_cancelled, "You stop.")

/// The player-facing text of reason `reason_type`, with ctx.detail filled where the template asks.
/proc/req_reason_text(reason_type, datum/op_ctx/ctx)
	if(!reason_type)
		return null
	var/datum/msg/def = msg_def(reason_type)
	var/text = def.self
	if(!findtext(text, "%DETAIL%"))
		return text
	if(ctx?.detail)
		return replacetext(text, "%DETAIL%", ctx.detail)
	return "You can't do that."

// ---- the flyweight ----

/datum/req
	/// The reason this requirement fails with (a /datum/msg type), unless test() returns another.
	var/reason = /datum/msg/req_failed
	/// OP_ACTOR / OP_TARGET / OP_HELD / OP_PROVIDER: whose state this reads.
	var/of = OP_TARGET

/// null when the requirement holds for ctx, else a /datum/msg reason type.
/datum/req/proc/test(datum/op_ctx/ctx)
	return null

/// The (datum, key) pairs test() depends on: list(list(datum, key), ...), or null.
/datum/req/proc/reads(datum/op_ctx/ctx)
	return null

/// The datum this requirement examines for ctx.
/datum/req/proc/subject(datum/op_ctx/ctx)
	switch(of)
		if(OP_ACTOR)
			return ctx.actor
		if(OP_HELD)
			return ctx.held
		if(OP_PROVIDER)
			return ctx.provider_atom()
	return ctx.target

/// The requirements a composite holds (for walking); null for a leaf.
/datum/req/proc/children()
	return null

/// signature -> the shared requirement.
GLOBAL_LIST_EMPTY(reqs_interned)

/// The shared requirement equal to R (same type and settings), registering R if new.
/proc/req_intern(datum/req/R)
	var/signature = datum_signature(R)
	var/datum/req/known = GLOB.reqs_interned[signature]
	if(known)
		return known
	GLOB.reqs_interned[signature] = R
	return R

/// A requirement or a list of them (nested lists flatten), as a flat list of /datum/req.
/proc/req_list(spec)
	. = list()
	if(isnull(spec))
		return
	if(istype(spec, /datum/req))
		. += spec
		return
	if(islist(spec))
		for(var/entry in spec)
			. += req_list(entry)

// ---- req(type) ----

/// The subject is of `type` (a path or a list of paths).
/datum/req/of_type
	reason = /datum/msg/req_wrong_item
	var/types

/datum/req/of_type/test(datum/op_ctx/ctx)
	var/datum/D = subject(ctx)
	if(!D)
		return reason
	for(var/path in (islist(types) ? types : list(types)))
		if(istype(D, path))
			return null
	return reason

/// The subject (the held item by default) is of `type` (a path, or a list of paths).
/proc/legacy_req(type, of = OP_HELD)
	RETURN_TYPE(/datum/req)
	var/datum/req/of_type/R = new
	R.types = type
	R.of = of
	return req_intern(R)

// ---- req_empty_hand ----

/// The actor holds nothing.
/datum/req/empty_hand
	reason = /datum/msg/req_hand_full

/datum/req/empty_hand/test(datum/op_ctx/ctx)
	return ctx.held ? reason : null

/proc/req_empty_hand()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/empty_hand)

// ---- req_self_held ----

/// The target is the held item itself: a self-use (attack_self, the Z key, GESTURE_SELF). Offered by an item's
/// self-use ops, so a click on the item (held is something else, or nothing) never means them, though both answer ACT_USE.
/datum/req/self_held
	reason = /datum/msg/req_wrong_item

/datum/req/self_held/test(datum/op_ctx/ctx)
	return (ctx.held && ctx.held == ctx.target) ? null : reason

/proc/req_self_held()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/self_held)

// ---- req_set / req_clear ----

/// The subject has every bit of `bits` set in its cap_state.
/datum/req/state_set
	reason = /datum/msg/req_wrong_state
	var/bits = NONE

/datum/req/state_set/test(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	if(!istype(A) || (A.cap_state & bits) != bits)
		return reason
	return null

/datum/req/state_set/reads(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	return A ? list(list(A, OP_KEY_CAP_STATE)) : null

/// The subject has none of `bits` set.
/datum/req/state_clear
	reason = /datum/msg/req_wrong_state
	var/bits = NONE

/datum/req/state_clear/test(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	if(!istype(A) || (A.cap_state & bits))
		return reason
	return null

/datum/req/state_clear/reads(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	return A ? list(list(A, OP_KEY_CAP_STATE)) : null

/// Every CAP_* bit in `bits` is set on the target (the panel is open).
/proc/req_set(bits, of = OP_TARGET)
	RETURN_TYPE(/datum/req)
	var/datum/req/state_set/R = new
	R.bits = bits
	R.of = of
	return req_intern(R)

/// None of the CAP_* bits in `bits` is set on the target (not locked).
/proc/req_clear(bits, of = OP_TARGET)
	RETURN_TYPE(/datum/req)
	var/datum/req/state_clear/R = new
	R.bits = bits
	R.of = of
	return req_intern(R)

// ---- req_access ----

/// The actor has access to the target (an /obj's allowed()); anything that isn't an /obj has none to check.
/datum/req/access
	reason = /datum/msg/req_no_access
	of = OP_TARGET

/datum/req/access/test(datum/op_ctx/ctx)
	var/obj/O = ctx.target
	if(!istype(O) || !ctx.actor)
		return null
	if(ctx.route == ROUTE_AUTHORITY)
		return null
	return O.allowed(ctx.actor) ? null : reason

/proc/req_access()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/access)

// ---- req_part ----

/// The target holds a component of `type` (a stock part, a board, a cell).
/datum/req/part
	reason = /datum/msg/req_no_part
	var/part_type

/datum/req/part/test(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	if(!istype(A))
		return reason
	for(var/atom/movable/M in contents_of(A))
		if(istype(M, part_type))
			return null
	return reason

/proc/req_part(type)
	RETURN_TYPE(/datum/req)
	var/datum/req/part/R = new
	R.part_type = type
	return req_intern(R)

// ---- req_proc ----

/// A holder proc, (mob/user, obj/item/held) -> TRUE or a refusal text (a cap `needs` check), or a
/// global chk_* proc (mob/user, atom/holder, obj/item/held). `reads` names what it depends on, as
/// a list of keys on the target. `else_say`: the reason when the proc answers FALSE (as a capability's else_say).
/datum/req/proc_check
	reason = /datum/msg/req_refused
	var/proc_ref
	var/list/read_keys
	var/else_say

/datum/req/proc_check/test(datum/op_ctx/ctx)
	var/why = cap_needs_reason(ctx.target, ctx.actor, ctx.held, proc_ref, else_say)
	if(!why)
		return null
	ctx.detail = istext(why) ? why : null
	return reason

/datum/req/proc_check/reads(datum/op_ctx/ctx)
	if(!length(read_keys) || !ctx.target)
		return null
	. = list()
	for(var/key in read_keys)
		. += list(list(ctx.target, key))

/// A holder or chk_* proc as a requirement. reads: keys of the target the proc depends on. else_say: what a FALSE answer
/// says (a proc that answers text says that instead).
/proc/req_proc(proc_ref, list/reads, else_say)
	var/datum/req/proc_check/R = new
	R.proc_ref = proc_ref
	R.read_keys = reads
	R.else_say = else_say
	return req_intern(R)

// ---- composites ----

/datum/req/all
	var/list/parts

/datum/req/all/test(datum/op_ctx/ctx)
	for(var/datum/req/R as anything in parts)
		var/why = R.test(ctx)
		if(why)
			return why
	return null

/datum/req/all/reads(datum/op_ctx/ctx)
	return req_reads_of(parts, ctx)

/datum/req/all/children()
	return parts

/datum/req/any
	var/list/parts

/datum/req/any/test(datum/op_ctx/ctx)
	var/first
	for(var/datum/req/R as anything in parts)
		var/why = R.test(ctx)
		if(!why)
			return null
		first ||= why
	return first || /datum/msg/req_failed

/datum/req/any/reads(datum/op_ctx/ctx)
	return req_reads_of(parts, ctx)

/datum/req/any/children()
	return parts

/// Holds while none of its parts does.
/datum/req/none
	reason = /datum/msg/req_forbidden
	var/list/parts

/datum/req/none/test(datum/op_ctx/ctx)
	for(var/datum/req/R as anything in parts)
		if(!R.test(ctx))
			return reason
	return null

/datum/req/none/reads(datum/op_ctx/ctx)
	return req_reads_of(parts, ctx)

/datum/req/none/children()
	return parts

/// The concatenated reads of every requirement in `parts`.
/proc/req_reads_of(list/parts, datum/op_ctx/ctx)
	. = list()
	for(var/datum/req/R as anything in parts)
		var/list/mine = R.reads(ctx)
		if(mine)
			. += mine

/// Holds when every part does. Takes requirements or lists of them.
/proc/legacy_all_of(...)
	RETURN_TYPE(/datum/req)
	var/datum/req/all/R = new
	R.parts = req_list(args)
	return req_intern(R)

/// Holds when any part does; the first reason otherwise.
/proc/legacy_any_of(...)
	RETURN_TYPE(/datum/req)
	var/datum/req/any/R = new
	R.parts = req_list(args)
	return req_intern(R)

/// Holds while no part does.
/proc/none_of(...)
	RETURN_TYPE(/datum/req)
	var/datum/req/none/R = new
	R.parts = req_list(args)
	return req_intern(R)

/// The requirements the old gating arguments mean (behind / blocked_by / locked_by): what a
/// preset's reads are built from. Null when there are none.
/proc/req_from_gating(behind = NONE, blocked_by = NONE, locked_by = NONE)
	var/list/out = list()
	if(behind)
		out += req_set(behind)
	if(blocked_by)
		out += req_clear(blocked_by)
	if(locked_by)
		out += req_clear(locked_by)
	return length(out) ? out : null

// ---- shared machine contracts ----

MSG_DEF_SELF(req_not_working, "It isn't working.")
MSG_DEF_SELF(req_subverted, "It doesn't respond.")
MSG_DEF_SELF(req_no_claws, "You can't tear into that.")

/// The target works: not broken and, for a machine, not under maintenance (unsecured electronics).
/datum/req/working
	reason = /datum/msg/req_not_working

/datum/req/working/test(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	if(!istype(A))
		return reason
	if(istype(A, /obj/machinery))
		var/obj/machinery/M = A
		return (M.broken_now() || M.under_maintenance()) ? reason : null
	return is_broken(A) ? reason : null

/// The target works (req_working()): shared by every op that needs a working machine.
/proc/req_working()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/working)

/// Nobody has subverted the target: not emagged, not taken over (the holder's is_subverted()).
/datum/req/not_subverted
	reason = /datum/msg/req_subverted

/datum/req/not_subverted/test(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	return istype(A) && A.is_subverted() ? reason : null

/datum/req/not_subverted/reads(datum/op_ctx/ctx)
	var/atom/A = subject(ctx)
	return A ? list(list(A, OP_KEY_CAP_STATE)) : null

/proc/legacy_req_not_subverted()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/not_subverted)

/// Whether someone has subverted this atom (req_not_subverted()): emagged by default; a holder that can be
/// taken over another way (an AI hack) adds it.
/atom/proc/is_subverted()
	return is_emagged(src)

/// `inner` holds, asked only over the routes in `routes` (a ROUTE_* mask): a cover that blocks hands
/// (ROUTE_PHYSICAL) but not a silicon's interface.
/datum/req/on_route
	var/routes = NONE
	var/datum/req/inner

/datum/req/on_route/test(datum/op_ctx/ctx)
	if(!(ctx.route & routes))
		return null
	return inner.test(ctx)

/datum/req/on_route/reads(datum/op_ctx/ctx)
	return (ctx.route & routes) ? inner.reads(ctx) : null

/datum/req/on_route/children()
	return list(inner)

/proc/req_on_route(routes, datum/req/inner)
	RETURN_TYPE(/datum/req)
	var/datum/req/on_route/R = new
	R.routes = routes
	// ALLOW(ownership): flyweight or pooled framework bookkeeping: the framework is the accessor, not a holder of a relation
	R.inner = inner
	return req_intern(R)

/// The actor has claws that tear machines open (a species that can_shred()).
/datum/req/claws
	reason = /datum/msg/req_no_claws
	of = OP_ACTOR

/datum/req/claws/test(datum/op_ctx/ctx)
	var/mob/living/carbon/human/H = subject(ctx)
	return istype(H) && H.species?.can_shred(H, FALSE, 14) ? null : reason

/proc/req_claws()
	RETURN_TYPE(/datum/req)
	return req_intern(new /datum/req/claws)

MSG_DEF_SELF(req_wrong_stance, "Not like that.")

/// The actor's input is in one of `stances` (I_HELP, I_DISARM, I_GRAB, I_HURT): an op declared for some stances
/// (cap_op(stance = list(...))) offers this, so another stance falls through to the next op. The input layer's reading of
/// the stance (mob/input_stance()), as the resolver's stance clauses read it.
/datum/req/stance
	reason = /datum/msg/req_wrong_stance
	of = OP_ACTOR
	var/list/stances

/datum/req/stance/test(datum/op_ctx/ctx)
	var/mob/M = ctx.actor
	return (istype(M) && (M.input_stance() in stances)) ? null : reason

/// A stance (I_*) or a list of them.
/proc/req_stance(stances)
	RETURN_TYPE(/datum/req)
	var/datum/req/stance/R = new
	R.stances = islist(stances) ? stances : list(stances)
	return req_intern(R)

/// Something on the subject listens for notices of `notice_type` (an op that only publishes one means
/// nothing where nobody hears it).
/datum/req/heard
	var/notice_type

/datum/req/heard/test(datum/op_ctx/ctx)
	var/datum/D = subject(ctx)
	return D && WANTS(D, notice_type) ? null : reason

/proc/req_heard(notice_type)
	RETURN_TYPE(/datum/req)
	var/datum/req/heard/R = new
	R.notice_type = notice_type
	return req_intern(R)
