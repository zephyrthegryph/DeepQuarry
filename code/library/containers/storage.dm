// storage(...) (doc/rewrite/final_api.html, section 11 "Containers and slots"; section 16): a holder that keeps items in its storage slot and the
// ops that put things in, open it and empty it.
//
//   CAPABILITIES(/obj/item/storage,
//       storage(space = nameof(/obj/item/storage::max_storage_space), slots = nameof(/obj/item/storage::storage_slots), max_size = ITEMSIZE_SMALL))
//   CAPABILITIES(/obj/item/storage/belt/utility, configure(storage(accepts = list(/obj/item/tool/crowbar, ...), max_size = ITEMSIZE_NORMAL)))
//
// What a storage takes is a fact of its type, so `accepts`, `refuses` and `max_size` are written in its declaration; the sizes (`space`, `slots`) and
// the switches are the name of a var of the holder that says them (`space = nameof(max_storage_space)`): a type keeps those on its own var lines,
// defaults and all, and a subtype or a map changes them there. A single instance narrows what it takes with storage_restrict() (an exact-fit kit).
//
//   space      capacity in storage-cost units (get_storage_cost() of each item)
//   slots      most things it holds, or null for no count limit (also picks the boxed window over the volume bar)
//   accepts    types it takes (null: anything that fits by size; an empty list takes nothing)
//   refuses    types it never takes
//   max_size   the largest w_class it takes (null: any)
//   empties    the use in hand and the menu entry "Empty Contents" dump everything on the floor
//   gather_toggle  the menu entry "Switch Gathering Method" (quick gather: the whole tile, or one item)
//   special    the use in hand is the type's own (it never empties)
//   pocketable it can be used while it sits in a pocket (an empty hand on a pocketed one otherwise takes it to the hand)
//   quiet      types of held item whose refusal is not said (a tool that does something else to the storage: a hand labeler)
//
// The contents live in the storage slot of the containment ledger (CONTAINER_SLOT_STORAGE): the slot's refusal and capacity are this capability's
// rules, so move_into(), slot_transfer() and every code path that puts an item in apply them. Ops (all keyed "storage.<name>"):
//
//   put_in          a held item clicked on the storage, when it fits
//   refuse          the same click when it does not fit: the reason is said, and the click goes on (passes()) to the held item's own use of its target
//   gather          a held pickup bag clicked on a storage: gathers its tile (or takes it in), and then the click goes on to put_in: the bag may go into it
//   open            an empty hand on a storage that is carried: opens it (a pocketed one comes to the hand)
//   toggle_open     an alt-click: opens or closes it
//   empty_out       the held storage used in hand (quick-empty types): dumps everything on the floor
//   empty           the menu entry "Empty Contents"
//   gather_mode     the menu entry "Switch Gathering Method"
//   climb_in        a small mob dragged onto the storage by itself (a micro, a mouse) climbs in as a held creature
//
// Picking the storage up closes the windows of whoever was looking inside (/obj/item/storage/pickup()); taking an item out is the item's own
// pickup (remove_from_storage()).

MSG_DEF_SELF(storage/not_empty, "There is something in it.")

CAPABILITY_TYPE(storage, CAP_STORAGE, /datum/capability/lib/storage, key = NONE, space = null, slots = null, accepts = null, refuses = null, max_size = null, empties = null, gather_toggle = null, special = null, pocketable = null, quiet = null)

/datum/capability/lib/storage

/datum/capability/lib/storage/entries()
	return list(
		op("gather", item(/obj/item/storage), when(CAP_PROC(gathers_here)), label("Gather"), \
			then(CAP_PROC(gather_here)), passes()),
		op("put_in", item(/obj/item), when(CAP_PROC(takes_it)), label("Put in"), \
			needs(req(CAP_PROC(fits), because = CAP_PROC(unfit_reason))), \
			then(CAP_PROC(put_in_item))),
		op("refuse", item(/obj/item), priority(OP_PRIORITY_DEFAULT), when(CAP_PROC(refuses_it)), label("Put in"), \
			then(CAP_PROC(say_refusal)), passes()),
		op("open", hand(), when(CAP_PROC(opens_by_hand)), label("Open"), then(CAP_PROC(open_or_unpocket))),
		op("toggle_open", hand(), answers(INTENT_TOGGLE), label("Open"), then(CAP_PROC(toggle_window))),
		op("empty_out", in_hand(), priority(OP_PRIORITY_PART), when(CAP_PROC(empties_in_hand)), label("Empty out"), then(CAP_PROC(empty_it))),
		op("empty", menu(), when(CAP_PROC(empties_by_menu)), label("Empty contents"), then(CAP_PROC(empty_it))),
		op("gather_mode", menu(), when(CAP_PROC(switches_gathering)), label("Switch gathering method"), needs(carried()), then(CAP_PROC(switch_gathering))), 		op("climb_in", item(/mob/living), gesture(GESTURE_DRAG), by(0), when(CAP_PROC(small_self_drag)), label("Climb in"), then(CAP_PROC(climb_in))))

// ---- a micro climbing in ----

MSG_DEF_SELF(storage/too_big_to_climb, "You don't fit in there.")

/// The dragged mob is the actor itself, small enough for a bag (a player at a quarter of normal size or less, a mouse at normal size or less), free to move,
/// and not wearing the storage. What it takes beyond that (room, what the storage accepts) is asked when it climbs.
/datum/capability/lib/storage/proc/small_self_drag(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!istype(user) || A.held != user)
		return FALSE
	if(user.buckled_to() || get_holder_of_type(A.holder, /mob/living/carbon/human) == user)
		return FALSE
	if(ishuman(user))
		return user.get_effective_size(TRUE) <= 0.25
	if(ismouse(user))
		return user.get_effective_size(TRUE) <= 1
	return FALSE

/// A stand-in for a creature in a bag, made to ask whether the bag would take one of that size (a holder cannot be made without its mob).
/obj/item/size_probe
	name = "creature"

/// The mob is scooped into a holder the size of its kind, which goes into the storage, if the storage would take one.
/datum/capability/lib/storage/proc/climb_in(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/storage/bag = A.holder
	bag.make_contents_real()
	var/obj/item/size_probe/probe = new
	probe.w_class = ismouse(user) ? ITEMSIZE_TINY : ITEMSIZE_SMALL
	var/refused = bag.insert_refusal(probe, user)
	qdel(probe) // ALLOW(lifecycle): a probe made to measure the fit is dropped at once, it never held anything
	if(refused)
		A.reason = /datum/msg/storage/too_big_to_climb
		return OP_REFUSED
	var/obj/item/holder/H = new user.holder_type(get_turf(user), user)
	if(!bag.insert_item(H, null, TRUE))
		A.reason = /datum/msg/storage/too_big_to_climb
		return OP_REFUSED
	to_chat(user, span_notice("You climb into 	he [bag]."))
	return OP_OK

// ---- conditions about the contents ----

/// How many things the holder's storage holds, declared or real.
/proc/storage_total(atom/holder)
	return length(holder.slot_contents(CONTAINER_SLOT_STORAGE)) + holder.latent_count(CONTAINER_SLOT_STORAGE)

/// req_storage_empty(): the participant's storage holds nothing (default: the holder's own).
/proc/req_storage_empty(because = null, of = ON_HOLDER)
	return part_make(/datum/entry/part/req/storage_empty, list("because" = because, "of" = of))

/datum/entry/part/req/storage_empty
	part_name = "req_storage_empty"
	default_reason = /datum/msg/storage/not_empty

/datum/entry/part/req/storage_empty/holds(datum/act/op/A)
	var/atom/holder = op_subject(A, src.args["of"])
	return istype(holder) && storage_total(holder) == 0

/datum/entry/part/req/storage_empty/read_keys(datum/act/op/A)
	var/atom/holder = op_subject(A, src.args["of"])
	return holder ? list(list(holder, STORAGE_CONTENTS_KEY)) : list()

// ---- settings ----

/// A setting: the value written in the declaration, or what the holder's var of that name says now; `fallback` when neither is a value.
/datum/capability/lib/storage/proc/setting(atom/holder, value, fallback)
	if(istext(value))
		value = holder.vars[value]
	return isnull(value) ? fallback : value

/// What one instance has been narrowed to (storage_restrict()): the activation's own data, never made by a read.
/datum/cap_data/storage
	var/list/accepts
	var/has_accepts = FALSE
	var/max_size
	var/has_max_size = FALSE

/datum/capability/lib/storage/cap_data_type()
	return /datum/cap_data/storage

/// The data of this holder's storage activation when it has any (a read never makes it: it may run inside a condition).
/datum/capability/lib/storage/proc/narrowed(atom/holder)
	var/datum/activation/act_state = cap_activation(holder, CAP_STORAGE, null, FALSE)
	return act_state?.data

/// Narrows one storage to `types` (null keeps what its type accepts) and `max_size` (null keeps its type's).
/proc/storage_restrict(atom/holder, list/types, max_size)
	var/datum/activation/act_state = cap_activation(holder, CAP_STORAGE, null, TRUE)
	var/datum/cap_data/storage/D = activation_data(act_state)
	if(!D)
		return
	if(!isnull(types))
		D.accepts = types.Copy()
		D.has_accepts = TRUE
	if(!isnull(max_size))
		D.max_size = max_size
		D.has_max_size = TRUE

/// The capacity of the holder's storage slot, in storage-cost units.
/datum/capability/lib/storage/proc/space_of(atom/holder)
	return setting(holder, space, 0)

/// Most things the holder holds, or null for no limit.
/datum/capability/lib/storage/proc/slots_of(atom/holder)
	return setting(holder, slots, null)

/// Things that count against the count limit: the real ones plus those still declared (latent contents).
/datum/capability/lib/storage/proc/count_in(atom/holder)
	return storage_total(holder)

// ---- the rules ----

/// Why `thing` can't go into the holder's storage, capacity aside (the slot checks space), or null. `actor` is whoever moves it (may be null).
/// Reads only: a requirement and a menu ask it too.
/datum/capability/lib/storage/proc/refusal(atom/holder, atom/movable/thing, mob/actor)
	if(!isitem(thing))
		return "that can't go in a container"
	var/obj/item/W = thing
	if(actor && actor.isEquipped(W) && !actor.canUnEquip(W))
		return "you can't let go of \the [W]"
	var/limit = slots_of(holder)
	if(!isnull(limit) && count_in(holder) >= limit)
		return "\the [holder] is full"
	var/datum/cap_data/storage/narrow = narrowed(holder)
	var/list/only = narrow?.has_accepts ? narrow.accepts : accepts
	if(!isnull(only) && !is_type_in_list(W, only))
		return "it doesn't take that"
	if(length(refuses) && is_type_in_list(W, refuses))
		return "it doesn't take that"
	var/biggest = narrow?.has_max_size ? narrow.max_size : max_size
	if(!isnull(biggest) && W.w_class > biggest)
		return "\the [W] is too big for \the [holder]"
	if(isitem(holder))
		var/obj/item/bag = holder
		if(W.w_class >= bag.w_class && istype(W, /obj/item/storage))
			return "it's a container as big as \the [holder]"
	if(has_trait(W, TRAIT_NODROP))
		return "\the [W] is stuck to your hand"
	return null

/// The whole answer the ledger would give: this capability's rules, then room, then the hooks on the slot. A reason, or null.
/datum/capability/lib/storage/proc/entry_refusal(atom/holder, atom/movable/thing, mob/actor)
	return dq_ledger_refusal(thing, holder, CONTAINER_SLOT_STORAGE, actor)

// ---- the slot ----

/// The slot of a storage item: internal, measured in storage-cost units, and deleted with the storage (contents go with it, as before). Its refusal and
/// capacity are the holder's storage() capability's.
/datum/relation_definition/slot/storage
	holder = /obj/item/storage
	slot_id = CONTAINER_SLOT_STORAGE
	name = "storage"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_UNITS
	drop_policy = SLOT_DROP_DELETE

/datum/relation_definition/slot/storage/capacity_for(atom/holder)
	var/datum/capability/lib/storage/C = cap_of(holder, CAP_STORAGE)
	return C ? C.space_of(holder) : 0

/datum/relation_definition/slot/storage/cost(atom/holder, atom/movable/thing)
	if(isitem(thing))
		var/obj/item/I = thing
		return I.get_storage_cost()
	return ITEMSIZE_COST_NO_CONTAINER

/datum/relation_definition/slot/storage/refusal(atom/holder, atom/movable/thing, mob/actor)
	var/datum/capability/lib/storage/C = cap_of(holder, CAP_STORAGE)
	if(!C)
		return "\the [holder] can't hold anything"
	return C.refusal(holder, thing, actor)

// ---- put in ----

/// A held item is a candidate for the storage: it is not the storage itself, and it is not a silicon's hand (a robot's grippers have their own).
/datum/capability/lib/storage/proc/offered(datum/act/op/A)
	var/obj/item/W = A.held
	return istype(W) && W != A.holder && !isrobot(A.actor)

/// The held item would go in.
/datum/capability/lib/storage/proc/takes_it(datum/act/op/A)
	return offered(A) && isnull(entry_refusal(A.holder, A.held, A.actor))

/// The held item would not go in.
/datum/capability/lib/storage/proc/refuses_it(datum/act/op/A)
	return offered(A) && !isnull(entry_refusal(A.holder, A.held, A.actor))

/datum/capability/lib/storage/proc/fits(datum/act/op/A)
	return isnull(entry_refusal(A.holder, A.held, A.actor))

/datum/capability/lib/storage/proc/unfit_reason(datum/act/op/A)
	return refusal_text(A.holder, A.held, entry_refusal(A.holder, A.held, A.actor))

/// "The pen won't go in the box: it doesn't take that."
/datum/capability/lib/storage/proc/refusal_text(atom/holder, obj/item/W, reason)
	return "\The [W] won't go in \the [holder]: [reason]."

/datum/capability/lib/storage/proc/put_in_item(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	var/obj/item/W = A.held
	var/mob/user = A.actor
	S.make_contents_real()
	if(W.storage_balks(S, user))
		return OP_REFUSED
	W.add_fingerprint(user)
	if(!S.insert_item(W, user))
		return OP_REFUSED
	return OP_OK

/// Says why the item did not go in. A hand labeler is not told: what it does next is the point of the click.
/datum/capability/lib/storage/proc/say_refusal(datum/act/op/A)
	var/obj/item/W = A.held
	var/list/silent = setting(A.holder, quiet, null)
	if(!is_type_in_list(W, silent))
		to_chat(A.actor, span_notice(refusal_text(A.holder, W, entry_refusal(A.holder, W, A.actor))))
	return OP_OK

// ---- gathering ----

/// A held storage that picks things up, clicked on a storage: it gathers (a bag in hand clicks the tile's contents into itself).
/datum/capability/lib/storage/proc/gathers_here(datum/act/op/A)
	var/obj/item/storage/bag = A.held
	return istype(bag) && bag != A.holder && !isrobot(A.actor) && bag.use_to_pickup

/datum/capability/lib/storage/proc/gather_here(datum/act/op/A)
	var/obj/item/storage/bag = A.held
	bag.try_collect(A.holder, A.actor)
	return OP_OK

// ---- opening ----

/// An empty hand on a storage that is on the person: it opens it, or takes it from a pocket.
/datum/capability/lib/storage/proc/opens_by_hand(datum/act/op/A)
	var/atom/holder = A.holder
	return isnull(A.held) && holder.loc == A.actor

/datum/capability/lib/storage/proc/open_or_unpocket(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	var/mob/user = A.actor
	S.make_contents_real()
	if(ishuman(user) && !setting(S, pocketable, FALSE))
		var/mob/living/carbon/human/H = user
		if((H.get_equipped_item(SLOT_ID_POCKET_L) == S || H.get_equipped_item(SLOT_ID_POCKET_R) == S) && !H.get_active_hand())
			H.put_in_hands(S)
			return OP_OK
	S.open(user)
	S.add_fingerprint(user)
	return OP_OK

/// An alt-click closes the storage for someone looking into it, else opens it for a person in reach.
/datum/capability/lib/storage/proc/toggle_window(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	return S.toggle_window(A.actor) ? OP_OK : OP_REFUSED

// ---- emptying and gathering by the verbs ----

/// The held storage is used in hand and it is one that dumps its contents.
/datum/capability/lib/storage/proc/empties_in_hand(datum/act/op/A)
	return setting(A.holder, empties, FALSE) && !setting(A.holder, special, FALSE)

/// The menu entry Empty Contents: the type dumps its contents.
/datum/capability/lib/storage/proc/empties_by_menu(datum/act/op/A)
	return !!setting(A.holder, empties, FALSE)

/datum/capability/lib/storage/proc/empty_it(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	S.make_contents_real()
	S.try_quick_empty(A.actor)
	return OP_OK

/// The menu entry Switch Gathering Method: the type picks things up by quick gather, and it is carried.
/datum/capability/lib/storage/proc/switches_gathering(datum/act/op/A)
	return !!setting(A.holder, gather_toggle, FALSE)

/datum/capability/lib/storage/proc/switch_gathering(datum/act/op/A)
	var/obj/item/storage/S = A.holder
	S.toggle_gathering(A.actor)
	return OP_OK
