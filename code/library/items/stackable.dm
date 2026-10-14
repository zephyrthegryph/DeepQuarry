// stackable(max_amount) (doc/rewrite/final_api.html, section 9 RES_STACK; section 16.14): an item that is a count of units of one kind (sheets, coils).
//
//   CAPABILITIES(/obj/item/sheets, stackable(max_amount = 50))
//
// The units are the item's `amount` var (a /obj/item/stack's own, or any item with one). Ops, keyed "stackable.<name>":
//   merge   the held stack onto another stack of the same type: the units that fit move (RES_STACK, reserved on the held stack, added to the target by the
//           effect, committed after it), so a full target refuses and nothing is half moved
//   split   the menu: asks how many, and the held-in-place stack gives that many to a new stack in the actor's hands (or at their feet)
// The stack(T, n) binding with put_in(slot), which splits off exactly n units and moves the split (the commit then spends nothing further), is the
// engine's (code/engine/parts/run.dm); stack_units() and stack_split() are the same primitives for code outside an op.

CAPABILITY_TYPE(stackable, CAP_STACKABLE, /datum/capability/lib/stackable, key = NONE, max_amount = 50)

MSG_DEF_SELF(stackable/full, "That stack is full.")
MSG_DEF_SELF(stackable/bad_split, "You can't split off that many.")
MSG_DEF(stackable/merge, "You add to the stack of %T%.", "%U% adds to a stack.")
MSG_DEF(stackable/split, "You split %I% into two stacks.", "%U% splits a stack.")

/datum/capability/lib/stackable/entries()
	return list(
		op("merge", at_target(/obj/item), when(CAP_PROC(same_kind)), label("Merge stacks"),
			needs(req(CAP_PROC(target_has_room))),
			costs(RES_STACK, CAP_PROC(merge_amount)), then(CAP_PROC(add_to_target)), says(MSG(stackable/merge))),
		op("split", menu(), label("Split stack"),
			asks(/datum/prompt/number, fields = list("question" = "How many to split off?")), then(CAP_PROC(do_split)), says(MSG(stackable/split))),
		examine_line(CAP_PROC(count_text)))

/// The units of a stack item (its `amount`): 0 when it is no stack.
/proc/stack_units(obj/item/I)
	var/amount = op_var(I, "amount")
	return isnum(amount) ? amount : 0

/// The most units a stack item holds: its own max_amount var, else null (unbounded).
/proc/stack_limit(obj/item/I)
	var/limit = op_var(I, "max_amount")
	return isnum(limit) ? limit : null

/// Splits `n` units off `I` into a new item (the original keeps the rest). null when `I` has fewer than n units; `I` itself when n is all of them.
/proc/stack_split(obj/item/I, n)
	RETURN_TYPE(/obj/item)
	return op_split_units(I, n)

/// Adds `n` units to a stack item.
/proc/stack_add_units(obj/item/I, n)
	if(istype(I, /obj/item/stack))
		var/obj/item/stack/S = I
		S.add(n)
		return
	I.vars["amount"] = stack_units(I) + n // ALLOW(api): units of a stack item move through this one helper: the library's own bookkeeping

/datum/capability/lib/stackable/proc/same_kind(datum/act/op/A)
	var/obj/item/held = A.holder
	return !isnull(A.target) && A.target != held && A.target.type == held.type

/// How many units the target can still take (its limit, else the capability's).
/datum/capability/lib/stackable/proc/room_of(obj/item/target)
	var/limit = stack_limit(target) || max_amount
	return max(0, limit - stack_units(target))

/datum/capability/lib/stackable/proc/target_has_room(datum/act/op/A)
	return (room_of(A.target) > 0) ? null : MSG(stackable/full)

/// The units one merge moves: what the held stack has, up to what fits.
/datum/capability/lib/stackable/proc/merge_amount(datum/act/op/A)
	return min(stack_units(A.holder), room_of(A.target))

/datum/capability/lib/stackable/proc/add_to_target(datum/act/op/A)
	var/n = merge_amount(A)
	if(n <= 0)
		return OP_REFUSED
	stack_add_units(A.target, n)
	return OP_OK

/// split: the answered count goes to a new stack in the actor's hands, or on their tile.
/datum/capability/lib/stackable/proc/do_split(datum/act/op/A)
	var/obj/item/stack_item = A.holder
	var/datum/prompt/R = A.answer
	var/n = isnull(R) ? null : round(text2num("[R.value]"))
	var/have = stack_units(stack_item)
	if(!isnum(n) || n < 1 || n >= have)
		A.reason = /datum/msg/stackable/bad_split
		return OP_REFUSED
	var/obj/item/piece = stack_split(stack_item, n)
	if(!piece)
		return OP_FAILED
	var/mob/user = A.actor
	if(!(user && user.put_in_hands(piece)))
		piece.forceMove(get_turf(stack_item))
	return OP_OK

/datum/capability/lib/stackable/proc/count_text(datum/act/op/A)
	var/obj/item/stack_item = A.holder
	return "There are [stack_units(stack_item)] in the stack."
