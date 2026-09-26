// Storage items (doc/rewrite/containment.md section 8, roadmap C4).
//
// A storage item is a holder with one internal slot (/datum/om/relation/slot/storage).
// Everything goes in and out through the containment ledger (C1):
//
//   S.insert_refusal(W, user)            why W can't go in, or null
//   S.insert_item(W, user, silent)       put W in (from a hand, the floor, another holder)
//   S.remove_from_storage(W, dest, user) take W out to dest (null: the floor)
//   S.gather_all(turf, user)             quick-gather everything on a tile
//   S.drop_contents(user)                quick-empty onto the floor
//
// Capacity is the slot's: the ledger keeps the storage-cost units used
// (max_storage_space is the limit) and storage_slots caps the count, so no
// check re-adds the contents. What a storage takes is its hold constraint
// (P3, CONSTRAINT_HOLD on the slot).
//
// The HUD (/datum/storage_hud) is made when someone opens the storage and
// deleted when the last viewer closes it, so a storage nobody is looking into
// has no screen objects.
//
// For use_to_pickup and allow_quick_gather, see /obj/item/attackby() (items.dm).

/obj/item/storage
	name = "storage"
	icon = 'icons/obj/storage.dmi'
	item_icons = list(
		slot_l_hand_str = 'icons/mob/items/lefthand_storage.dmi',
		slot_r_hand_str = 'icons/mob/items/righthand_storage.dmi',
		)
	w_class = ITEMSIZE_NORMAL
	show_messages = 1
	MATERIAL_BULK(MAT_FIBERS, 50)
	latent_contents = TRUE

	/// Mobs looking into this storage.
	var/list/is_seeing
	/// The open HUD, shared by everyone in is_seeing. Null when nobody looks.
	var/tmp/datum/storage_hud/hud

	/// Capacity in storage-cost units (get_storage_cost()).
	var/max_storage_space = ITEMSIZE_COST_SMALL * 4
	/// Most things this holds, or null for no count limit. Also picks the
	/// boxed HUD layout over the volume bar.
	var/storage_slots = null

	var/use_to_pickup	//Set this to make it possible to use this item in an inverse way, so you can have the item in your hand and click items on the floor to pick them up.
	var/display_contents_with_number	//Set this to make the storage item group contents of the same type and display them as a number.
	var/allow_quick_empty	//Set this variable to allow the object to have the 'empty' verb, which dumps all the contents on the floor.
	var/allow_quick_gather	//Set this variable to allow the object to have the 'toggle mode' verb, which quickly collects all items from a tile.
	var/collection_mode = 1;  //0 = pick one at a time, 1 = pick all on tile
	var/use_sound = "rustle"	//sound played when used. null for no sound.
	var/list/starts_with //Things to spawn on the box on spawn
	var/empty //Mapper override to spawn an empty version of a container that usually has stuff
	/// If you can use this storage while in a pocket
	var/pocketable = FALSE
	/// Used for attack_self chain
	var/special_handling = FALSE

// ---- The slot ----

/// A storage item's interior. Internal, so it takes C2's default damage and
/// heat shares. Contents are deleted with the storage, as before.
/datum/om/relation/slot/storage
	holder = /obj/item/storage
	slot_id = CONTAINER_SLOT_STORAGE
	name = "storage"
	exposure = SLOT_EXPOSURE_INTERNAL
	capacity_model = SLOT_CAPACITY_UNITS
	holder_constraint = CONSTRAINT_HOLD
	drop_policy = SLOT_DROP_DELETE

/datum/om/relation/slot/storage/capacity_for(obj/item/storage/holder)
	return holder.max_storage_space

/datum/om/relation/slot/storage/cost(obj/item/storage/holder, atom/movable/thing)
	if(isitem(thing))
		var/obj/item/I = thing
		return I.get_storage_cost()
	return ITEMSIZE_COST_NO_CONTAINER

/// Things counted against storage_slots: the real ones plus latent entries
/// (C5 overrides latent_count()).
/datum/om/relation/slot/storage/proc/count_used(obj/item/storage/holder)
	var/datum/ledger/L = dq_ledger(holder)
	var/list/things = L?.slots[slot_id]
	return length(things) + latent_count(holder)

/// Latent entries in this slot, for the count limit. None until C5.
/datum/om/relation/slot/storage/proc/latent_count(obj/item/storage/holder)
	return holder.latent_count(CONTAINER_SLOT_STORAGE)

/datum/om/relation/slot/storage/refusal(obj/item/storage/holder, atom/movable/thing, mob/actor)
	if(!isitem(thing))
		return "that can't go in a container"
	var/obj/item/W = thing
	if(actor && actor.isEquipped(W) && !actor.canUnEquip(W))
		return "you can't let go of \the [W]"
	if(holder.storage_slots != null && count_used(holder) >= holder.storage_slots)
		return "\the [holder] is full"
	. = ..()
	if(.)
		return .
	if(W.w_class >= holder.w_class && istype(W, /obj/item/storage))
		return "it's a container as big as \the [holder]"
	if(HAS_TRAIT(W, TRAIT_NODROP))
		return "\the [W] is stuck to your hand"
	return null

// ---- Latent contents (C5) ----
// Legacy storage code walks contents directly, so the storage materializes
// its latent contents before any of it runs: when used, opened, searched,
// picked up, worn or examined.

/obj/item/storage/latent_generator()
	return empty ? null : starts_with

/obj/item/storage/latent_generator_clear()
	starts_with = null

/// Latent only for plain spawns: a variant needs apply_variant(), so it is made now.
/obj/item/storage/latent_spawn_ok(path, value)
	return !(islist(value) && length(value) >= 2 && istext(value[2]))

/// Makes the latent contents real before legacy code reads contents.
/obj/item/storage/proc/make_contents_real()
	if(has_latent())
		latent_materialize_all()

// ---- Lifecycle ----

/obj/item/storage/Initialize(mapload)
	. = ..()

	if(allow_quick_empty)
		verbs += /obj/item/storage/verb/quick_empty
	else
		verbs -= /obj/item/storage/verb/quick_empty

	if(allow_quick_gather)
		verbs += /obj/item/storage/verb/toggle_gathering_mode
	else
		verbs -= /obj/item/storage/verb/toggle_gathering_mode

	if(LAZYLEN(starts_with) && !empty)
		// starts_with values are list(count, variant). See code/datums/variants/spawn_with_variant.dm.
		// Latent-safe types without a variant stay declared until the storage
		// is used (C5); the rest are made now.
		dq_latent_declare(src)
		update_icon()
	else
		starts_with = null

	calibrate_size()

/obj/item/storage/Destroy()
	close_all()
	for(var/mob/M as anything in is_seeing?.Copy())
		hide_from(M)
	QDEL_NULL(hud)

	if(ismob(loc))
		var/mob/M = loc
		M.remove_from_mob(src)

	. = ..()

/obj/item/storage/pickup(mob/user)
	make_contents_real()
	return ..()

/obj/item/storage/equipped(mob/user, slot)
	make_contents_real()
	return ..()

/obj/item/storage/examine(mob/user, infix, suffix)
	make_contents_real()
	return ..()

/obj/item/storage/emp_act(severity, recursive)
	make_contents_real()
	return ..()

/// Spawned and mapped contents may not fit the type's capacity: grow it to
/// fit. Runs once at Initialize, over what was made inside (real or, for a
/// declared generator, its would-be cost).
/obj/item/storage/proc/calibrate_size()
	var/total_storage_space = 0
	for(var/obj/item/I in contents) // latent-ok: declared contents counted below
		total_storage_space += I.get_storage_cost()
	var/list/generator = latent_declared ? starts_with : null
	for(var/path in generator)
		if(dq_latent_eligible(path) && latent_spawn_ok(path, generator[path]))
			total_storage_space += dq_type_storage_cost(path) * dq_latent_spawn_count(generator[path])
	if(total_storage_space)
		max_storage_space = max(total_storage_space, max_storage_space)

// ---- Insertion ----

/// What storage takes (constraints, rules.md section 3): pocket-sized things
/// unless a type says otherwise. Types override this; see HOLD_ONLY and HOLD_MAX_SIZE.
/obj/item/storage/hold_constraint()
	return list(HOLD_MAX_SIZE(ITEMSIZE_SMALL))

/// Why `W` can't go in right now, or null if it can. One ledger check: the
/// slot's acceptance and hold constraint, the count and space limits, and
/// whether `W` can leave where it is. `user` is the mover (may be null).
/obj/item/storage/proc/insert_refusal(obj/item/W, mob/user)
	make_contents_real()
	return dq_ledger_refusal(W, src, CONTAINER_SLOT_STORAGE, user)

/// Tell `user` why `W` didn't go in.
/obj/item/storage/proc/refuse_insert(obj/item/W, mob/user, reason)
	if(!user || !reason || istype(W, /obj/item/hand_labeler))
		return
	to_chat(user, span_notice("\The [W] won't go in \the [src]: [reason]."))

/// Checks, then puts `W` in: out of `user`'s hands or inventory, off the floor
/// or out of another holder. Returns TRUE if it went in. Refusals are not
/// reported here (see try_insert()). `prevent_warning` skips the visible
/// message, for putting many things in at once.
/obj/item/storage/proc/insert_item(obj/item/W, mob/user, prevent_warning = FALSE)
	if(insert_refusal(W, user))
		return FALSE
	if(user)
		if(!stall_insertion(W, user)) // Can sleep, for slow storage
			return FALSE
		if(insert_refusal(W, user)) // Things change while stalling
			return FALSE

	var/mob/wearer = ismob(W.loc) ? W.loc : null
	if(wearer)
		// Still mob inventory (C3): let the mob clear its slot, then move.
		// Nothing sleeps between the check above and this move.
		wearer.remove_from_mob(W, src)
		if(W.loc != src)
			return FALSE
		W.dropped(wearer)
	else if(!W.move_into(src, CONTAINER_SLOT_STORAGE, user))
		return FALSE

	W.on_enter_storage(src)
	if(user)
		add_fingerprint(user)
		if(use_sound)
			playsound(src, use_sound, 50, 0, -5)
		if(!prevent_warning)
			for(var/mob/M in viewers(user, null))
				if(M == user)
					to_chat(user, span_notice("You put \the [W] into [src]."))
				else if(get_dist(M, user) <= 1) //If someone is standing close enough, they can tell what it is...
					M.show_message(span_notice("\The [user] puts [W] into [src]."))
				else if(W.w_class >= 3) //Otherwise they can only see large or normal items from a distance...
					M.show_message(span_notice("\The [user] puts [W] into [src]."))
	update_icon()
	return TRUE

/// insert_item() that tells `user` why when it's refused.
/obj/item/storage/proc/try_insert(obj/item/W, mob/user, prevent_warning = FALSE)
	var/refusal = insert_refusal(W, user)
	if(refusal)
		refuse_insert(W, user, refusal)
		return FALSE
	return insert_item(W, user, prevent_warning)

/// Called before insertion completes, allowing you to delay or cancel it. Only
/// for moves with a user.
/obj/item/storage/proc/stall_insertion(obj/item/W, mob/user)
	return TRUE

// ---- Removal ----

/// Takes `W` out to `new_location` (null: the floor under this). Returns TRUE
/// if it came out. `user` is whoever takes it (may be null).
/obj/item/storage/proc/remove_from_storage(obj/item/W, atom/new_location, mob/user)
	make_contents_real()
	if(!istype(W) || W.loc != src)
		return FALSE

	if(user && !stall_removal(W, user)) // Can sleep, for slow storage
		return FALSE
	if(W.loc != src)
		return FALSE

	var/atom/destination = new_location || get_turf(src)
	if(!destination)
		return FALSE
	if(new_location && ismob(loc))
		W.dropped(user || loc)
	if(ismob(destination))
		W.hud_layerise()
	else
		W.reset_plane_and_layer()
	if(!slot_remove(W, destination, user))
		return FALSE

	if(W.maptext)
		W.maptext = ""
	W.on_exit_storage(src)
	update_icon()
	return TRUE

/// Called before removal completes, allowing you to delay or cancel it. Only
/// for moves with a user.
/obj/item/storage/proc/stall_removal(obj/item/W, mob/user)
	return TRUE

/// Every item in here, in the order the HUD shows them.
/obj/item/storage/proc/stored_items()
	. = list()
	for(var/obj/item/I in slot_contents(CONTAINER_SLOT_STORAGE))
		. += I

/// Keep the HUD in step with every move in or out, however it happened.
/obj/item/storage/on_slot_changed(slot_id, atom/movable/thing, inserted)
	if(hud)
		refresh_hud()

// ---- Gather and empty ----

/obj/item/storage/proc/gather_all(turf/T, mob/user)
	make_contents_real()
	var/list/rejections = list()
	var/success = 0
	var/failure = 0

	for(var/obj/item/I in T)
		if(I.type in rejections) // To limit bag spamming: any given type only complains once
			continue
		var/refusal = insert_refusal(I, user)
		if(refusal)
			refuse_insert(I, user, refusal)
			rejections += I.type
			failure = 1
			continue
		if(insert_item(I, user, TRUE))
			success = 1
	if(success && !failure)
		to_chat(user, span_notice("You put everything in [src]."))
	else if(success)
		to_chat(user, span_notice("You put some things in [src]."))
	else
		to_chat(user, span_notice("You fail to pick anything up with \the [src]."))

/obj/item/storage/verb/toggle_gathering_mode()
	set name = "Switch Gathering Method"
	set category = "Object"

	collection_mode = !collection_mode
	switch (collection_mode)
		if(1)
			to_chat(usr, "[src] now picks up all items on a tile at once.")
		if(0)
			to_chat(usr, "[src] now picks up one item at a time.")

/obj/item/storage/verb/quick_empty()
	set name = "Empty Contents"
	set category = "Object"
	set src in view(1)

	try_quick_empty(usr)

/// Quick-empty onto the floor, if `user` can.
/obj/item/storage/proc/try_quick_empty(mob/user)
	// Only humans and robots can dump contents
	if(!(ishuman(user) || isrobot(user)))
		return FALSE
	// Hard to do when you're KO'd
	if(user.incapacitated())
		return FALSE
	if(!Adjacent(user))
		return FALSE
	// No turf dumping if user is in a belly
	if(isbelly(user.loc))
		return FALSE
	drop_contents(user)
	return TRUE

/// Everything out onto the floor under this.
/obj/item/storage/proc/drop_contents(mob/user)
	make_contents_real()
	if(user)
		hide_from(user)
	var/turf/T = get_turf(src)
	for(var/obj/item/I as anything in stored_items())
		remove_from_storage(I, T, user)

//Useful for spilling the contents of containers all over the floor
/obj/item/storage/proc/spill(dist = 2, turf/T = null)
	make_contents_real()
	if (!istype(T))//If its not on the floor this might cause issues
		T = get_turf(src)
	for(var/obj/item/I as anything in stored_items())
		remove_from_storage(I, T)
		I.tumble(2)

/obj/item/storage/proc/return_inv()
	make_contents_real()
	var/list/L = list()
	L += src.contents
	for(var/obj/item/storage/S in src)
		L += S.return_inv()
	for(var/obj/item/gift/G in src)
		L += G.gift
		if (istype(G.gift, /obj/item/storage))
			L += G.gift:return_inv()
	return L

// ---- Interaction ----

/obj/item/storage/MouseDrop(obj/over_object as obj)
	make_contents_real()
	if(!canremove)
		return

	if (isliving(usr) || isobserver(usr))
		var/mob/user = usr

		if(istype(user.loc,/obj/mecha)) // stops inventory actions in a mech. why?
			return

		if(over_object == user && Adjacent(user)) // this must come before the screen objects only block
			open(user)
			return

		if(!(istype(over_object, /atom/movable/screen)))
			return ..()

		//makes sure that the storage is equipped, so that we can't drag it into our hand from miles away.
		if(!(loc == user) || (loc && loc.loc == user))
			return

		if(user.restrained() || user.stat || user.is_paralyzed() || user.incapacitated(INCAPACITATION_KNOCKOUT))
			return

		switch(over_object.name)
			if("r_hand")
				user.unEquip(src)
				user.put_in_r_hand(src)
			if("l_hand")
				user.unEquip(src)
				user.put_in_l_hand(src)
		add_fingerprint(user)

/obj/item/storage/click_alt(mob/user)
	make_contents_real()
	if(user in is_seeing)
		src.close(user)
	else if(isliving(user) && Adjacent(user))
		src.open(user)
	else
		return ..()

//This proc is called when you want to place an item into the storage item.
/obj/item/storage/attackby(obj/item/W as obj, mob/user as mob)
	make_contents_real()
	..()

	if(isrobot(user))
		return //Robots can't interact with storage items.

	if(istype(W, /obj/item/lightreplacer))
		var/obj/item/lightreplacer/LP = W
		var/amt_inserted = 0
		for(var/obj/item/light/L in stored_items())
			if(L.status == 0 && LP.uses < LP.max_uses)
				LP.add_uses(1)
				amt_inserted++
				qdel(L)
		if(amt_inserted)
			to_chat(user, "You inserted [amt_inserted] light\s into \the [LP.name]. You have [LP.uses] light\s remaining.")
			return

	var/refusal = insert_refusal(W, user)
	if(refusal)
		refuse_insert(W, user, refusal)
		return

	if(istype(W, /obj/item/tray))
		var/obj/item/tray/T = W
		if(T.calc_carry() > 0)
			if(prob(85))
				to_chat(user, span_warning("The tray won't fit in [src]."))
				return
			else
				user.drop_from_inventory(W, get_turf(user))
				to_chat(user, span_warning("God damn it!"))

	W.add_fingerprint(user)
	return insert_item(W, user)

/obj/item/storage/attack_hand(mob/user as mob)
	make_contents_real()
	if(ishuman(user) && !pocketable)
		var/mob/living/carbon/human/H = user
		if(H.get_equipped_item(SLOT_ID_POCKET_L) == src && !H.get_active_hand())	//Prevents opening if it's in a pocket.
			H.put_in_hands(src)
			return
		if(H.get_equipped_item(SLOT_ID_POCKET_R) == src && !H.get_active_hand())
			H.put_in_hands(src)
			return

	if (src.loc == user)
		src.open(user)
	else
		..()
		for(var/mob/M in range(1))
			if (M.s_active == src)
				src.close(M)
	src.add_fingerprint(user)
	return

/obj/item/storage/attack_self(mob/user)
	make_contents_real()
	. = ..(user)
	if(.)
		return TRUE
	if(special_handling)
		return FALSE
	if((user.get_active_hand() == src) || (isrobot(user)) && allow_quick_empty)
		if(src.verbs.Find(/obj/item/storage/verb/quick_empty))
			try_quick_empty(user)
			return TRUE

/obj/item/storage/AllowDrop()
	return TRUE

// Allows micros to drag themselves into storage items
/obj/item/storage/MouseDrop_T(mob/living/target, mob/living/user)
	make_contents_real()
	if(!istype(user)) return // If the user passed in isn't a living mob, exit
	if(target != user) return // If the user didn't drag themselves, exit
	if(user.incapacitated() || user.buckled) return // If user is incapacitated or buckled, exit
	if(get_holder_of_type(src, /mob/living/carbon/human) == user) return // No jumping into your own equipment
	if(ishuman(user) && user.get_effective_size(TRUE) > 0.25) return // Only micro characters
	if(ismouse(user) && user.get_effective_size(TRUE) > 1) return // Only normal sized mice or less

	// Create a dummy holder with user's size to test insertion
	var/obj/item/holder/D = new/obj/item/holder
	if(ismouse(user))
		D.w_class = ITEMSIZE_TINY // Mouse smol
	else if(ishuman(user))
		D.w_class = ITEMSIZE_SMALL // Players small
	else        // Other creatures not accepted at this time
		qdel(D) // If there's a better way to check the size of a
		return  // mob's holder and if it fits, replace this slab
	if(insert_refusal(D, user)) // If the dummy item doesn't fit, exit
		qdel(D)
		return
	qdel(D)

	// Scoop and insert target into storage
	var/obj/item/holder/H = new user.holder_type(get_turf(user), user)
	if(insert_item(H, null, TRUE))
		to_chat(user, span_notice("You climb into \the [src]."))
	return ..()

// ---- Legacy wrappers for mob inventory (C3 moves these callers onto slots) ----
// Only for: /mob/living/equip_to_storage (mob/living/inventory.dm, 3 calls),
// human/inventory.dm (the worn belt) and protean_rig.dm (the rig backpack).
// The mover is whoever holds the item, if anyone. Don't add callers.

/obj/item/storage/proc/can_be_inserted(obj/item/W, stop_messages = FALSE)
	var/mob/user = ismob(W?.loc) ? W.loc : null
	var/reason = insert_refusal(W, user)
	if(reason && !stop_messages)
		refuse_insert(W, user, reason)
	return !reason

/obj/item/storage/proc/handle_item_insertion(obj/item/W, prevent_warning = FALSE)
	return insert_item(W, ismob(W?.loc) ? W.loc : null, prevent_warning)

// ---- Opening and the HUD ----

/obj/item/storage/proc/open(mob/user)
	make_contents_real()
	if (use_sound)
		var/obj/belly/B = user.loc
		if(isliving(user) && (!isbelly(B) || !(B.mode_flags & DM_FLAG_MUFFLEITEMS)))
			playsound(src, src.use_sound, 50, 0, -5)
	if(user.s_active && user.s_active != src)
		user.s_active.close(user)
	show_to(user)

/obj/item/storage/proc/close(mob/user)
	hide_from(user)
	user.s_active = null

/obj/item/storage/proc/close_all()
	for(var/mob/M in can_see_contents())
		close(M)
		. = 1

/obj/item/storage/proc/can_see_contents()
	var/list/cansee = list()
	for(var/mob/M in is_seeing?.Copy())
		if(M.s_active == src && M.client)
			cansee |= M
		else
			hide_from(M)
	return cansee

/// Shows the HUD to `user`, making it if nobody else is looking. A viewer
/// without a client is tracked the same way (can_see_contents() drops it).
/obj/item/storage/proc/show_to(mob/user)
	make_contents_real()
	if(user.s_active != src)
		for(var/obj/item/I as anything in stored_items())
			if(I.on_found(user))
				return
	if(user.s_active && user.s_active != src)
		user.s_active.hide_from(user)

	if(!hud)
		hud = new /datum/storage_hud(src)
	LAZYDISTINCTADD(is_seeing, user)
	user.s_active = src
	var/client/C = user.client
	if(C)
		C.screen += hud.screen_atoms()
		C.screen += hud.shown

/// Takes the HUD off `user`'s screen. The last viewer out deletes it.
/obj/item/storage/proc/hide_from(mob/user)
	LAZYREMOVE(is_seeing, user)
	var/client/C = user.client
	if(C && hud)
		C.screen -= hud.screen_atoms()
		for(var/obj/item/I as anything in hud.shown)
			if(I.loc != user)
				C.screen -= I
	if(user.s_active == src)
		user.s_active = null
	if(!LAZYLEN(is_seeing))
		QDEL_NULL(hud)

/// Lays the HUD out again after a change, for everyone looking.
/obj/item/storage/proc/refresh_hud()
	if(!hud)
		return
	var/list/before = hud.screen_atoms() + hud.shown
	hud.layout()
	var/list/after = hud.screen_atoms() + hud.shown
	var/list/gone = before - after
	var/list/added = after - before
	for(var/mob/M as anything in is_seeing)
		var/client/C = M.client
		if(!C)
			continue
		for(var/atom/movable/A as anything in gone)
			if(A.loc != M)
				C.screen -= A
		C.screen += added

/// Legacy name for refresh_hud(), still called by the vore egg (C7).
/obj/item/storage/proc/orient2hud()
	refresh_hud()

/// The screen objects for one open storage. Made on the first open, deleted
/// when the last viewer closes it, and shared by everyone looking in.
/datum/storage_hud
	var/obj/item/storage/storage
	/// Boxed layout: the "block" background. Bar layout: start, continue, end.
	var/list/atom/movable/screen/storage/backdrop
	var/atom/movable/screen/close/closer
	/// One click catcher per shown item.
	var/list/atom/movable/storage_slot/catchers
	/// Items placed on screen (one per type with display_contents_with_number).
	var/list/obj/item/shown

GLOBAL_VAR_INIT(storage_hud_count, 0)

/datum/storage_hud/New(obj/item/storage/S)
	..()
	storage = S
	backdrop = list()
	catchers = list()
	shown = list()
	var/datum/weakref/master = WEAKREF(S)
	if(S.storage_slots)
		backdrop += new_backdrop(master, "block")
	else
		backdrop += new_backdrop(master, "storage_start")
		backdrop += new_backdrop(master, "storage_continue")
		backdrop += new_backdrop(master, "storage_end")
	closer = new /atom/movable/screen/close()
	closer.master_ref = master
	closer.icon_state = "storage_close"
	closer.hud_layerise()
	GLOB.storage_hud_count++
	layout()

/datum/storage_hud/Destroy()
	GLOB.storage_hud_count--
	QDEL_LIST(catchers)
	QDEL_LIST(backdrop)
	QDEL_NULL(closer)
	for(var/obj/item/I as anything in shown)
		I.maptext = ""
	shown = null
	storage = null
	return ..()

/datum/storage_hud/proc/new_backdrop(datum/weakref/master, state)
	var/atom/movable/screen/storage/B = new()
	B.name = "storage"
	B.master_ref = master
	B.icon_state = state
	return B

/// Every screen object to put on a viewer's screen (items are in `shown`).
/datum/storage_hud/proc/screen_atoms()
	. = backdrop + closer
	if(storage.storage_slots)
		. += catchers

/// Places the items and sizes the backdrop.
/datum/storage_hud/proc/layout()
	QDEL_LIST(catchers)
	catchers = list()
	var/list/items = storage.hud_order(storage.stored_items())
	var/list/counts
	if(storage.display_contents_with_number)
		counts = list()
		var/list/samples = list()
		for(var/obj/item/I as anything in items)
			var/key = storage.hud_group_key(I)
			if(isnull(counts[key]))
				samples += I
				counts[key] = 0
			counts[key] += storage.hud_group_amount(I)
		for(var/obj/item/I as anything in items - samples)
			I.screen_loc = null
		items = samples
	shown = items
	if(storage.storage_slots)
		boxes_layout(counts)
	else
		bar_layout()

/datum/storage_hud/proc/add_catcher(obj/item/I)
	var/atom/movable/storage_slot/SS = new(null, I)
	SS.screen_loc = I.screen_loc
	SS.mouse_opacity = MOUSE_OPACITY_OPAQUE
	catchers += SS
	return SS

/// Fixed-size storage (belts, boxes): a grid up to seven wide.
/datum/storage_hud/proc/boxes_layout(list/counts)
	var/rows = 0
	var/cols = min(7, storage.storage_slots) - 1
	if(length(shown) > 7)
		rows = round((length(shown) - 1) / 7) // 7 is the maximum allowed width.
	var/atom/movable/screen/storage/boxes = backdrop[1]
	boxes.screen_loc = "4:16,2:16 to [4+cols]:16,[2+rows]:16"
	var/cx = 4
	var/cy = 2 + rows
	for(var/obj/item/I as anything in shown)
		I.screen_loc = "[cx]:16,[cy]:16"
		if(counts)
			var/n = counts[storage.hud_group_key(I)]
			I.maptext = span_white("[n > 1 ? "[n]" : ""]")
		else
			I.maptext = ""
		I.hud_layerise()
		add_catcher(I)
		cx++
		if(cx > 4 + cols)
			cx = 4
			cy--
	closer.screen_loc = "[4+cols+1]:16,2:16"

/// Volume storage (bags): a bar sized to max_storage_space, each item a
/// segment sized to its storage cost.
/datum/storage_hud/proc/bar_layout()
	SHOULD_NOT_SLEEP(TRUE)
	// Static prototypes, mutated per item: this proc must never sleep.
	var/static/mutable_appearance/stored_start
	var/static/mutable_appearance/stored_continue
	var/static/mutable_appearance/stored_end
	if(!stored_start)
		stored_start = mutable_appearance(icon = 'icons/mob/screen1.dmi', icon_state = "stored_start", layer = 0.1, plane = PLANE_PLAYER_HUD_ITEMS)
		stored_continue = mutable_appearance(icon = 'icons/mob/screen1.dmi', icon_state = "stored_continue", layer = 0.1, plane = PLANE_PLAYER_HUD_ITEMS)
		stored_end = mutable_appearance(icon = 'icons/mob/screen1.dmi', icon_state = "stored_end", layer = 0.1, plane = PLANE_PLAYER_HUD_ITEMS)

	// Smaller capacities get a shorter bar; halved so boxes of tiny things aren't cluttered.
	var/baseline_max_storage_space = INVENTORY_STANDARD_SPACE / 2
	var/storage_cap_width = 2 //length of sprite for start and end of the box representing total storage space
	var/stored_cap_width = 4 //length of sprite for start and end of the box representing the stored item
	var/max_space = max(1, storage.max_storage_space)
	var/storage_width = min(round(224 * max_space / baseline_max_storage_space, 1), 274)

	var/atom/movable/screen/storage/bar_start = backdrop[1]
	var/atom/movable/screen/storage/bar_continue = backdrop[2]
	var/atom/movable/screen/storage/bar_end = backdrop[3]
	bar_start.vis_contents.Cut()

	var/matrix/M = matrix()
	M.Scale((storage_width - storage_cap_width * 2 + 3) / 32, 1)
	bar_continue.transform = M

	bar_start.screen_loc = "4:16,2:16"
	bar_continue.screen_loc = "4:[storage_cap_width+(storage_width-storage_cap_width*2)/2+2],2:16"
	bar_end.screen_loc = "4:[19+storage_width-storage_cap_width],2:16"

	var/startpoint = 0
	var/endpoint = 1
	for(var/obj/item/I as anything in shown)
		startpoint = endpoint + 1
		endpoint += storage_width * I.get_storage_cost() / max_space

		var/matrix/M_start = matrix()
		var/matrix/M_continue = matrix()
		var/matrix/M_end = matrix()
		M_start.Translate(startpoint, 0)
		M_continue.Scale((endpoint - startpoint - stored_cap_width * 2) / 32, 1)
		M_continue.Translate(startpoint + stored_cap_width + (endpoint - startpoint - stored_cap_width * 2) / 2 - 16, 0)
		M_end.Translate(endpoint - stored_cap_width, 0)
		stored_start.transform = M_start
		stored_continue.transform = M_continue
		stored_end.transform = M_end

		I.screen_loc = "4:[round((startpoint+endpoint)/2)+2],2:16"
		I.maptext = ""
		I.hud_layerise()
		var/atom/movable/storage_slot/SS = add_catcher(I)
		SS.add_overlay(list(stored_start, stored_continue, stored_end))
		bar_start.vis_contents += SS

	closer.screen_loc = "4:[storage_width+19],2:16"

/// HUD order for `items` (a fresh list, safe to sort). Default: insertion order.
/obj/item/storage/proc/hud_order(list/items)
	return items

/// With display_contents_with_number: what groups items into one icon.
/obj/item/storage/proc/hud_group_key(obj/item/I)
	return I.type

/// With display_contents_with_number: how much one item adds to its group's number.
/obj/item/storage/proc/hud_group_amount(obj/item/I)
	return 1

/// Click catcher behind each stored item, so clicks on its backdrop reach the item.
/atom/movable/storage_slot
	name = "stored - "
	icon = 'icons/effects/effects.dmi'
	icon_state = "nothing"
	plane = PLANE_PLAYER_HUD_ITEMS
	layer = 0.1
	alpha = 200
	var/datum/weakref/held_item

/atom/movable/storage_slot/Initialize(mapload, obj/item/held_item)
	. = ..()
	ASSERT(held_item)
	name += held_item.name
	src.held_item = WEAKREF(held_item)

/atom/movable/storage_slot/Destroy()
	held_item = null
	. = ..()

/// Has to be this way. The fact that the overlays will be constantly mutated by other storage means we can't wait.
/atom/movable/storage_slot/add_overlay(list/somethings)
	ASSERT(islist(somethings))
	overlays = somethings

/atom/movable/storage_slot/Click()
	var/obj/item/I = held_item?.resolve()
	if(I)
		usr.ClickOn(I)
	return 1

// ---- Sizes ----

//Returns the storage depth of an atom. This is the number of storage items the atom is contained in before reaching toplevel (the area).
//Returns -1 if the atom was not found on container.
/atom/proc/storage_depth(atom/container)
	var/depth = 0
	var/atom/cur_atom = src

	while (cur_atom && !(cur_atom in container.contents))
		if (isarea(cur_atom))
			return INFINITY
		if (istype(cur_atom.loc, /obj/item/storage))
			depth++
		cur_atom = cur_atom.loc

	if (!cur_atom)
		return INFINITY	//inside something with a null loc.

	return depth

//Like storage depth, but returns the depth to the nearest turf
//Returns -1 if no top level turf (a loc was null somewhere, or a non-turf atom's loc was an area somehow).
/atom/proc/storage_depth_turf()
	var/depth = 0
	var/atom/cur_atom = src

	while (cur_atom && !isturf(cur_atom))
		if (isarea(cur_atom))
			return INFINITY
		if (istype(cur_atom.loc, /obj/item/storage))
			depth++
		cur_atom = cur_atom.loc

	if (!cur_atom)
		return INFINITY	//inside something with a null loc.

	return depth

// See inventory_sizes.dm for the defines.
/// get_storage_cost() of a pristine `path`, from type data (latent entries).
/proc/dq_type_storage_cost(path)
	var/static/list/cache = list()
	. = cache[path]
	if(isnull(.))
		var/obj/item/probe = new_unmaterialized(path, null)
		. = probe.get_storage_cost()
		qdel(probe)
		cache[path] = .

/obj/item/proc/get_storage_cost()
	if (storage_cost)
		return storage_cost
	else
		switch(w_class)
			if(ITEMSIZE_TINY)
				return ITEMSIZE_COST_TINY
			if(ITEMSIZE_SMALL)
				return ITEMSIZE_COST_SMALL
			if(ITEMSIZE_NORMAL)
				return ITEMSIZE_COST_NORMAL
			if(ITEMSIZE_LARGE)
				return ITEMSIZE_COST_LARGE
			if(ITEMSIZE_HUGE)
				return ITEMSIZE_COST_HUGE
			else
				return ITEMSIZE_COST_NO_CONTAINER

/obj/item/storage/proc/make_exact_fit()
	make_contents_real()
	// Runs at Initialize for fitted kits: read contents, don't make a ledger.
	var/list/items = list()
	for(var/obj/item/I in contents)
		items += I
	storage_slots = length(items)

	var/list/types = list()
	var/max_size = 0
	max_storage_space = 0
	for(var/obj/item/I as anything in items)
		types |= I.type
		max_size = max(I.w_class, max_size)
		max_storage_space += I.get_storage_cost()
	restrict_hold(types, max_size)

/*
 * Trinket Box - READDING SOON
 */
/obj/item/storage/trinketbox
	name = "trinket box"
	desc = "A box that can hold small trinkets, such as a ring."
	icon = 'icons/obj/items.dmi'
	icon_state = "trinketbox"
	var/open = 0
	storage_slots = 1
	var/open_state
	var/closed_state
	special_handling = TRUE

/obj/item/storage/trinketbox/hold_constraint()
	var/list/holds = list(
		/obj/item/clothing/accessory/ring,
		/obj/item/coin,
		/obj/item/clothing/accessory/medal
		)
	return list(HOLD_ONLY(holds), HOLD_MAX_SIZE(ITEMSIZE_SMALL))

/obj/item/storage/trinketbox/update_icon()
	cut_overlays()
	if(open)
		icon_state = open_state

		if(contents.len >= 1)
			var/contained_image = null
			if(istype(contents[1],  /obj/item/clothing/accessory/ring))
				contained_image = "ring_trinket"
			else if(istype(contents[1], /obj/item/coin))
				contained_image = "coin_trinket"
			else if(istype(contents[1], /obj/item/clothing/accessory/medal))
				contained_image = "medal_trinket"
			if(contained_image)
				add_overlay(contained_image)
	else
		icon_state = closed_state

/obj/item/storage/trinketbox/Initialize(mapload)
	if(!open_state)
		open_state = "[initial(icon_state)]_open"
	if(!closed_state)
		closed_state = "[initial(icon_state)]"
	. = ..()

/obj/item/storage/trinketbox/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	open = !open
	update_icon()

/obj/item/storage/trinketbox/examine(mob/user)
	. = ..()
	if(open && contents.len)
		var/display_item = contents[1]
		. += span_notice("\The [src] contains \the [display_item]!")
