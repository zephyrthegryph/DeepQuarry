// Someone should really merge secure closets and crates into this, which Bay has done already.
/obj/structure/closet
	name = "closet"
	/// Made closed in play (not by the map), it takes in the loose items on its turf (closet_after_init()).
	var/collects_in_play = TRUE
	desc = "It's a basic storage unit."
	icon = 'icons/obj/closets/bases/closet.dmi'
	icon_state = "base"
	density = TRUE
	w_class = ITEMSIZE_HUGE
	layer = UNDER_JUNK_LAYER
	blocks_emissive = EMISSIVE_BLOCK_GENERIC
	flags = REMOTEVIEW_ON_ENTER
	latent_contents = TRUE

	/// The door is open. Written through set_opened(); a map says a closet starts open with `opened = 1`.
	var/opened = 0
	/// Whether the closet takes a tool to seal it shut (a welder; a coffin is screwed, a grave has no lid to seal): see `sealable`.
	var/sealable = TRUE
	var/wall_mounted = 0 //never solid (You can always pass over it)
	max_integrity = 100
	/// Sheet metal and an air gap (containment paths, C2).
	insulation = 0.5

	var/breakout_time = 2 //2 minutes by default
	var/breakout_sound = SFX_EFFECTS_GRILLEHIT	//Sound that plays while breaking out

	var/storage_capacity = 2 * MOB_MEDIUM //This is so that someone can't pack hundreds of items in a locker/crate
							  //then open it in a populated area to crash clients.
	var/storage_cost = 40	//How much space this closet takes up if it's stuffed in another closet

	var/open_sound = SFX_EFFECTS_CLOSET_OPEN
	var/close_sound = SFX_EFFECTS_CLOSET_CLOSE

	var/store_misc = 1		//Chameleon item check
	var/store_items = 1		//Will the closet store items?
	var/store_mobs = 1		//Will the closet store mobs?
	var/max_closets = 0		//Number of other closets allowed on tile before it won't close.

	var/list/starts_with // List of type = count (or just type for 1)

	var/datum/decl/closet_appearance/closet_appearance = /datum/decl/closet_appearance // The /datum/decl that defines what decals we end up with, that makes our look unique

	/// Currently animating the door transform
	var/is_animating_door = FALSE
	/// Our visual object for the closet door, if we're animating
	var/obj/effect/overlay/closet_door/door_obj
	var/vore_sound = SFX_EFFECTS_METALSCRAPE2

TRACKED(/obj/structure/closet, opened)

MSG_DEF_SELF(closet/wont_budge, "It won't budge!")
MSG_DEF_SELF(closet/bolts_unreachable, "You can't reach the anchoring bolts when the door is closed!")
MSG_DEF_SELF(closet/cant_put_down, "You can't put that down there.")
MSG_DEF_SELF(closet/too_small, "The locker is too small to stuff anyone into!")
MSG_DEF_SELF(closet/no_targets, "No eligible targets found.")
MSG_DEF_SELF(closet/cant_break_out, "You can't push the door open from in here.")
MSG_DEF(closet/cut_apart, "You cut %T% apart with %I%.", "%U% cuts %T% apart with %I%.")
MSG_DEF(closet/emptied_basket, "You empty %I% into %T%.", "%U% empties %I% into %T%.")
MSG_DEF(closet/break_begin, "You lean on the back of %T% and start pushing the door open.", "%T% begins to shake violently!")

// A closet is a door over an interior (the ledger slot below). The door is `opened`, the weld (a coffin's screws) is the library's weld_shut(), the bolts
// the library's anchor(), the lock a secure closet's lock(). What the door does (open(), close(), the sounds and the animation, what it takes in when it
// shuts and spills when it opens) stays the closet's own procs: the ops below only start it. A hand toggles the door; set down on an open one, a held thing
// lands on its tile; an open one is cut apart with a welder; somebody shut in a sealed one breaks out after breakout_time minutes (a player-facing wait,
// started by the Resist verb through container_resist()).
CAPABILITIES(/obj/structure/closet)
	damageable()
	blast_contents(shield = 1) // a closet shields its contents a step
	after_init(0, then(PROC_REF(closet_after_init)))
	space(SPACE_INTERIOR, door = nameof(opened))
	owns_one(nameof(door_obj), /obj/effect/overlay/closet_door)
	anchor()
	extend("anchor.toggle", wait(2 SECONDS), needs(req_is(nameof(opened), because = MSG(closet/bolts_unreachable))))
	weld_shut(offered = PROC_REF(can_seal))
	extend("weld_shut.toggle", wait(2 SECONDS), needs(req_is(nameof(opened), FALSE, because = MSG(closet/wont_budge))))
	op("door", inputs(hand(), menu()), answers(INTENT_USE), label("Toggle Open"), when(req(PROC_REF(bare_hand_or_menu))),
		needs(req(PROC_REF(door_ready), because = MSG(closet/wont_budge))), then(PROC_REF(door_toggled)))
	op("cut_apart", tool(TOOL_WELDER), label("Cut apart"), at(SPACE_INTERIOR), priority(above("weld_shut.toggle")), wait(0), costs(RES_FUEL, 0),
		needs(req(PROC_REF(welder_lit), because = MSG(weld/needs_lit))), then(PROC_REF(cut_apart)), says(MSG(closet/cut_apart)))
	op("empty_basket", item(/obj/item/storage/laundry_basket), label("Empty into"), at(SPACE_INTERIOR), priority(OP_PRIORITY_PART),
		then(PROC_REF(basket_emptied)), says(MSG(closet/emptied_basket)))
	op("stuff_grab", item(/obj/item/grab), label("Stuff inside"), at(SPACE_INTERIOR), priority(OP_PRIORITY_PART),
		needs(req(PROC_REF(grab_fits), because = PROC_REF(grab_refusal))), then(PROC_REF(stuff_grabbed)))
	op("set_down", item(/obj/item), label("Put down"), at(SPACE_INTERIOR), priority(OP_PRIORITY_DEFAULT),
		needs(req(PROC_REF(can_set_down), because = MSG(closet/cant_put_down))), then(PROC_REF(set_down)))
	op("stuff", item(/atom/movable), gesture(GESTURE_DRAG), label("Stuff inside"), at(SPACE_INTERIOR), then(PROC_REF(stuff_dragged)))
	op("break_out", ai(), label("Break out"), wait(PROC_REF(breakout_wait), keeps = TARGET_PRESENT | ALIVE),
		needs(req_capable(), req(PROC_REF(can_break_out), because = MSG(closet/cant_break_out))),
		begins(MSG(closet/break_begin)), then(PROC_REF(broke_out)), logs(LOG_GAME))
	op("devour", menu(), label("Devour Occupants"), when(req(PROC_REF(actor_shut_in))),
		needs(req(PROC_REF(has_prey), because = MSG(closet/no_targets))),
		asks(/datum/prompt/choice/prey),
		then(PROC_REF(devoured)))

/obj/structure/closet/Initialize(mapload)
	add_trait(src, TRAIT_ALT_CLICK_BLOCKER, ROUNDSTART_TRAIT)
	. = ..()

/// Declares what it starts with and takes in the loose items on its turf, once the map around it exists.
/obj/structure/closet/proc/closet_after_init(datum/act/timer/A)
	// starts_with is the generator: only types that can't be latent are made
	// now; the rest stay declared until something needs them (C5).
	dq_latent_declare(src)

	// A closed closet takes in the loose items on its turf; a body bag unfolded in play (collects_in_play FALSE) leaves the floor alone.
	if(!opened && (collects_in_play || A?.mapload))
		if(isliving(loc)) return
		var/list/loose = list()
		for(var/obj/item/I in turf_contents_of_type(loc, /obj/item))
			if(I.density || I.anchored) continue
			loose += I
		// adjust locker size to hold everything with 5 units of free store room.
		// Summed without the ledger, so an untouched closet never builds one.
		var/content_size = 0
		for(var/atom/movable/AM as anything in contents + loose) // ALLOW(latent): the generator's latent entries are summed below
			content_size += storage_cost_of(AM)
		var/list/generator = latent_declared ? starts_with : null
		for(var/path in generator)
			if(dq_latent_eligible(path))
				content_size += storage_cost_of_type(path) * dq_latent_spawn_count(generator[path])
		if(content_size > storage_capacity-5)
			storage_capacity = content_size + 5
		for(var/obj/item/I as anything in loose)
			move_into(src, null, I)

	if(ispath(closet_appearance))
		closet_appearance = GLOB.closet_appearances[closet_appearance]
		if(istype(closet_appearance))
			icon = closet_appearance.icon
			color = null
	update_icon()

// ---- Containment (C1): one interior slot. The base Destroy() spills it.
// C2: the interior is internal (it shares the room's air, so not sealed);
// heat reaches it through the closet's insulation, and only rounds and stabs
// that get through the sheet metal, and seeping acid, reach its contents. ----

/datum/om/relation/slot/closet_interior
	holder = /obj/structure/closet
	slot_id = CONTAINER_SLOT_INTERIOR
	name = "interior"
	capacity_model = SLOT_CAPACITY_UNITS
	accepts = /datum/predicate/slot_closet_interior
	drop_policy = SLOT_DROP_SPILL
	exposure = SLOT_EXPOSURE_INTERNAL
	damage_transmission = list(0, 0, 0.25, 0, 0, 0, 0.25, 0, 0, 0, 0, 0)

/datum/om/relation/slot/closet_interior/capacity_for(obj/structure/closet/holder)
	return holder.storage_capacity

/datum/om/relation/slot/closet_interior/cost(obj/structure/closet/holder, atom/movable/thing)
	return holder.storage_cost_of(thing)

/datum/predicate/slot_closet_interior
	name = "closet interior"
	spec = list(REQ_BECAUSE(REQ_ON(PRED_TARGET, /atom/movable/proc/slot_loose, null), "it is fastened down"))

/obj/structure/closet/latent_generator()
	return starts_with

/obj/structure/closet/latent_generator_clear()
	starts_with = null

/datum/om/relation/slot/closet_interior/entry_cost(obj/structure/closet/holder, path)
	return holder.storage_cost_of_type(path)

/// What a thing of `path` would take up, from type data (latent entries).
/obj/structure/closet/proc/storage_cost_of_type(path)
	if(ispath(path, /obj/item))
		var/obj/item/typed = path
		return CEILING(initial(typed.w_class) / 2, 1)
	if(ispath(path, /obj/structure/closet))
		var/obj/structure/closet/typed_closet = path
		return initial(typed_closet.storage_cost)
	return 1

/// What `thing` takes up inside this closet, in storage_capacity units.
/obj/structure/closet/proc/storage_cost_of(atom/movable/thing)
	if(isitem(thing))
		var/obj/item/I = thing
		return CEILING(I.w_class / 2, 1)
	if(isliving(thing))
		var/mob/living/L = thing
		return L.mob_size
	if(istype(thing, /obj/structure/closet))
		var/obj/structure/closet/C = thing
		return C.storage_cost
	return 1

/// Slot acceptance (P2 proc clause): whether this can be put away loose.
/atom/movable/proc/slot_loose(mob/actor, atom/target, obj/item/held)
	return !anchored

/mob/living/slot_loose(mob/actor, atom/target, obj/item/held)
	return !anchored && !src?.buckled_to() && !LAZYLEN(pinned)

//Cham Projector Exception: the dummy is anchored but hides in closets.
/obj/effect/dummy/chameleon/slot_loose(mob/actor, atom/target, obj/item/held)
	return TRUE


/obj/structure/closet/examine(mob/user)
	. = ..()
	if(Adjacent(user) || isobserver(user))
		var/content_size = slot_used(CONTAINER_SLOT_INTERIOR)
		if(!content_size)
			. += "It is empty."
		else if(storage_capacity > content_size*4)
			. += "It is barely filled."
		else if(storage_capacity > content_size*2)
			. += "It is less than half full."
		else if(storage_capacity > content_size)
			. += "There is still some free space."
		else
			. += "It is full."

	if(!opened && isobserver(user))
		var/list/latent = latent_names()
		. += "It contains: [counting_english_list(user.client, contents)][length(latent) ? "; [english_list(latent)]" : ""]"

/obj/structure/closet/CanPass(atom/movable/mover, turf/target)
	if(wall_mounted)
		return TRUE
	return ..()

/obj/structure/closet/proc/can_open()
	if(weld_shut_welded(src, null))
		return 0
	return 1

/obj/structure/closet/proc/can_close()
	var/closet_count = 0
	for(var/obj/structure/closet/closet in get_turf(src))
		if(closet != src)
			if(!closet.anchored)
				closet_count ++
	if(closet_count > max_closets)
		return 0
	return 1

/obj/structure/closet/proc/dump_contents()
	slot_empty(CONTAINER_SLOT_INTERIOR, loc)

/obj/structure/closet/proc/open(mob/user)
	if(opened)
		return 0

	if(!can_open())
		return 0

	dump_contents()

	set_opened(TRUE)
	playsound(src, open_sound, 50, 1, -3)
	if(initial(density))
		set_density(!density)
	animate_door()
	return 1

/obj/structure/closet/proc/close()
	if(!opened)
		return 0
	if(!can_close())
		return 0

	// The ledger enforces storage_capacity: whatever doesn't fit stays out.
	if(store_misc)
		store_misc()
	if(store_items)
		store_items()
	if(store_mobs)
		store_mobs()
	if(max_closets)
		store_closets()

	set_opened(FALSE)

	playsound(src, close_sound, 50, 1, -3)
	if(initial(density))
		set_density(!density)
	animate_door(TRUE)
	PUBLISH_LEGACY(src, /datum/notice/closet_closed)
	return 1

// Each store_* proc moves what it finds on the turf into the interior slot and
// returns how many went in. The slot refuses anchored or BUCKLED(src) things and
// anything that would overflow storage_capacity.

//Cham Projector Exception
/obj/structure/closet/proc/store_misc()
	. = 0
	for(var/obj/effect/dummy/chameleon/AD in turf_contents_of_type(loc, /obj/effect/dummy/chameleon))
		if(move_into(src, null, AD))
			.++

/obj/structure/closet/proc/store_items()
	. = 0
	for(var/obj/item/I in turf_contents_of_type(loc, /obj/item))
		if(move_into(src, null, I))
			.++

/obj/structure/closet/proc/store_mobs()
	. = 0
	for(var/mob/living/M in turf_contents_of_type(loc, /mob/living))
		if(move_into(src, null, M))
			.++

/obj/structure/closet/proc/store_closets()
	. = 0
	for(var/obj/structure/closet/C in turf_contents_of_type(loc, /obj/structure/closet))
		if(C == src)	//Don't store ourself
			continue
		if(C.max_closets)	//Prevents recursive storage
			continue
		if(move_into(src, null, C))
			.++

/obj/structure/closet/proc/toggle(mob/user as mob)
	if(is_animating_door)
		return
	if(!(opened ? close() : open(user)))
		to_chat(user, span_notice("It won't budge!"))
		return

// ---- the ops: what they read and what they do ----

/// The door can move now: it is not mid-swing, and the closet lets it (an open one can be shut, a shut one opened).
/obj/structure/closet/proc/door_ready(datum/act/A)
	return !is_animating_door && (opened ? can_close() : can_open()) // ALLOW(reads): what a door lets through is asked of the closet's own procs at the click; the menu entry is advisory

/// An empty hand works the door (a held thing has its own ops), and so does the menu's pick whatever is held.
/obj/structure/closet/proc/bare_hand_or_menu(datum/act/op/A)
	return isnull(A.held) || A.origin != ORIGIN_CLICK

/// A hand or the menu's pick works the door.
/obj/structure/closet/proc/door_toggled(datum/act/op/A)
	add_fingerprint(A.actor)
	toggle(A.actor)
	return OP_OK

/// A shut closet that has something to seal it with can be sealed.
/obj/structure/closet/proc/can_seal(datum/act/A)
	return sealable && !opened

/// The welder is lit.
/obj/structure/closet/proc/welder_lit(datum/act/op/A)
	var/obj/item/weldingtool/welder = A.held?.get_welder()
	return !welder || welder.isOn()

/// An open closet is cut apart into a sheet of steel (what it held is already on its tile).
/obj/structure/closet/proc/cut_apart(datum/act/op/A)
	playsound(src, A.held.usesound, 50)
	replace_with(src, /obj/item/stack/material/steel)
	return OP_OK

/// A laundry basket with something in it is emptied onto the tile of an open closet; an empty one is put down like anything else.
/obj/structure/closet/proc/basket_emptied(datum/act/op/A)
	var/obj/item/storage/laundry_basket/LB = A.held
	if(!length(LB.slot_contents()))
		return can_set_down(A) ? set_down(A) : OP_OK
	var/turf/T = get_turf(src)
	for(var/obj/item/I in LB.slot_contents())
		LB.remove_from_storage(I, T)
	return OP_OK

/// The held item is in the actor's own hands (not a module mounted on a cyborg), and the actor is no cyborg: only those let go of things at a closet.
/obj/structure/closet/proc/can_set_down(datum/act/op/A)
	return !isrobot(A.actor) && A.held.loc == A.actor // ALLOW(reads): where the held item is read when it is put down; the click asks again

/// A held thing is let go of onto the tile of an open closet.
/obj/structure/closet/proc/set_down(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.drop_item()
	if(W)
		W.do_drop_animation(user)
		W.forceMove(loc)
	return OP_OK

/// Whether `user` can stuff `O` into the open closet by dragging it here: the user acts, both are within reach, `O` is no HUD element and not fastened down,
/// and a closet is never stuffed into a closet.
/obj/structure/closet/proc/stuffable(mob/user, atom/movable/O)
	if(!istype(user) || !istype(O) || istype(O, /atom/movable/screen) || istype(O, /obj/structure/closet))
		return FALSE
	if(O.loc == user || O.anchored || user.contents.Find(src) || !isturf(user.loc))
		return FALSE
	if(user.restrained() || user.stat || user.has_status(STAT_WEAKENED) || user.has_status(STAT_STUNNED) || user.has_status(STAT_PARALYZED))
		return FALSE
	return Adjacent(user) && Adjacent(O) && user.Adjacent(O)

/// Puts `O` on the tile of the open closet (a mob walks in; a thing is pulled onto it).
/obj/structure/closet/proc/stuff_in(mob/user, atom/movable/O)
	step_towards(O, loc)
	if(user != O)
		user.show_viewers(span_danger("[user] stuffs [O] into [src]!"))
	add_fingerprint(user)

/// A thing dragged onto the open closet.
/obj/structure/closet/proc/stuff_dragged(datum/act/op/A)
	if(stuffable(A.actor, A.held))
		stuff_in(A.actor, A.held)
	return OP_OK

/// Whether a grab can stuff the one it holds in: closets take anyone (a locker too small, a crate, say otherwise).
/obj/structure/closet/proc/grab_fits(datum/act/op/A)
	return TRUE

/obj/structure/closet/proc/grab_refusal(datum/act/op/A)
	return /datum/msg/closet/too_small

/// What the lock of a secure locker or crate just did, in the library's words.
/obj/structure/closet/proc/lock_toggled_message(datum/act/A)
	return lock_locked(A.holder) ? /datum/msg/lock/locked : /datum/msg/lock/unlocked

/// A held grab stuffs the one it holds in, as if they were dragged onto the closet.
/obj/structure/closet/proc/stuff_grabbed(datum/act/op/A)
	var/obj/item/grab/G = A.held
	var/atom/movable/victim = G?.grab_target()
	if(victim && stuffable(A.actor, victim))
		stuff_in(A.actor, victim)
	return OP_OK

/obj/structure/closet
	silicon_use = ROBOT_USE_HAND_ADJACENT

/obj/structure/closet/relaymove(mob/user as mob)
	if(user.stat || !isturf(loc))
		return

	if(!open(user))
		to_chat(user, span_notice("It won't budge!"))

// tk grab then use on self
/obj/structure/closet/attack_self_tk(mob/user as mob)
	add_fingerprint(user)
	if(!toggle(user))
		to_chat(user, span_notice("It won't budge!"))

/// The closet is sealed shut (welded, or screwed down for a coffin): the template's picture.
/obj/structure/closet/proc/appearance_sealed()
	return is_welded(src)

APPEARANCE_TEMPLATE(/obj/structure/closet, "closed_unlocked{appearance_sealed?_welded:}")
DECLARE_APPEARANCE(/obj/structure/closet, "opened", list("1" = list(APPEARANCE_ICON_STATE = "open")))

/obj/structure/closet/attack_generic(mob/user, damage, attack_message = "destroys")
	if(damage < STRUCTURE_MIN_DAMAGE_THRESHOLD)
		return
	user.do_attack_animation(src)
	act_message(user, src, others = span_danger("%U% [attack_message] %T%!"))
	dump_contents()
	after(src, 0.1 SECONDS, TYPE_PROC_REF(/datum, om_qdel_self))
	return 1

/obj/structure/closet/proc/req_breakout()
	if(opened)
		return 0 //Door's open... wait, why are you in it's contents then?
	if(!weld_shut_welded(src, null))
		return 0 //closed but not sealed...
	return 1

/// The Resist verb of somebody shut in: the break-out op, once. A second push while one is under way is left alone.
/obj/structure/closet/container_resist(mob/living/escapee)
	if(op_pending_of(escapee) || !req_breakout())
		return

	escapee.setClickCooldown(100)
	perform_op(escapee, src, "break_out", origin = ORIGIN_SYSTEM)

/// How long the shove takes: breakout_time minutes.
/obj/structure/closet/proc/breakout_wait(datum/act/A)
	return breakout_time MINUTES

/// The actor is shut inside, and the closet holds them (still shut, and sealed or locked).
/obj/structure/closet/proc/can_break_out(datum/act/op/A)
	return A.actor?.loc == src && !!req_breakout() // ALLOW(reads): where the pusher is, and whether the closet still holds them, read again when the wait ends

/// The shove goes through: the closet is broken open.
/obj/structure/closet/proc/broke_out(datum/act/op/A)
	var/mob/living/escapee = A.actor
	to_chat(escapee, span_warning("You successfully break out!"))
	visible_message(span_danger("\The [escapee] successfully broke out of \the [src]!"))
	add_fingerprint(escapee)
	playsound(src, breakout_sound, 100, 1)
	break_open()
	animate_shake()
	return OP_OK

/obj/structure/closet/proc/break_open()
	set_welded(src, FALSE)
	update_icon()
	//Do this to prevent contents from being opened into nullspace (read: bluespace)
	if(istype(loc, /obj/structure/bigDelivery))
		var/obj/structure/bigDelivery/BD = loc
		BD.unwrap()
	open()

/obj/structure/closet/onDropInto(atom/movable/AM)
	return

/obj/structure/closet/AllowDrop()
	return TRUE

/obj/structure/closet/return_air_for_internal_lifeform(mob/living/L)
	if(loc)
		if(istype(loc, /obj/structure/closet))
			return (loc.return_air_for_internal_lifeform(L))
	return return_air()

// Reaching 0 integrity spills the closet's contents before it's destroyed.
/obj/structure/closet/atom_destruction(damage_flag)
	dump_contents()
	return ..()

/obj/structure/closet/proc/animate_door(closing = FALSE)
	if(!closet_appearance?.door_anim_time)
		update_icon()
		return
	if(!door_obj)
		rel_set(src, nameof(door_obj), new /obj/effect/overlay/closet_door)
	vis_contents |= door_obj
	door_obj.icon = icon
	door_obj.icon_state = "door_front"
	is_animating_door = TRUE
	if(!closing)
		update_icon()
	var/num_steps = closet_appearance.door_anim_time / world.tick_lag
	for(var/I in 0 to num_steps)
		var/angle = closet_appearance.door_anim_angle * (closing ? 1 - (I/num_steps) : (I/num_steps))
		var/matrix/M = get_door_transform(angle)
		var/door_state = angle >= 90 ? "door_back" : "door_front"
		var/door_layer = angle >= 90 ? FLOAT_LAYER : ABOVE_MOB_LAYER

		if(I == 0)
			door_obj.transform = M
			door_obj.icon_state = door_state
			door_obj.layer = door_layer
		else if(I == 1)
			animate(door_obj, transform = M, icon_state = door_state, layer = door_layer, time = world.tick_lag, flags = ANIMATION_END_NOW)
		else
			animate(transform = M, icon_state = door_state, layer = door_layer, time = world.tick_lag)
	after(src, closet_appearance.door_anim_time, PROC_REF(end_door_animation), key = "door_animation", with = list(closing), keeps_dead = TRUE)

/obj/structure/closet/proc/end_door_animation(closing = FALSE)
	is_animating_door = FALSE
	if(closing)
		// There's not really harm in leaving it on, but, one less atom to send to clients to render when lockers are closed
		vis_contents -= door_obj
		update_icon()

/obj/structure/closet/proc/get_door_transform(angle)
	var/matrix/M = matrix()
	if(!closet_appearance)
		return M
	M.Translate(-closet_appearance.door_hinge, 0)
	M.Multiply(matrix(cos(angle), 0, 0, -sin(angle) * closet_appearance.door_anim_squish, 1, 0))
	M.Translate(closet_appearance.door_hinge, 0)
	return M

/obj/structure/closet/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

//the menu entry to eat people in the same closet as yourself

/// The actor is a living thing shut in this closet.
/obj/structure/closet/proc/actor_shut_in(datum/act/op/A)
	return isliving(A.actor) && A.actor.loc == src // ALLOW(reads): who is shut in is read when the entry is offered and when it is picked

/// Each devourable one shut in with `user`, other than `user`, by the name the choice shows (two with one name are told apart with a number). Names to mobs.
/obj/structure/closet/proc/prey_by_name(mob/living/user)
	var/list/by_name = list()
	for(var/mob/living/L in contents) // ALLOW(latent,reads): mobs are never latent; who is shut in is read when the entry is offered and when it is picked
		// ALLOW(reads): who can be eaten is read when the entry is offered and when it is picked
		if(L == user || !L.devourable) //no eating yourself. 1984.
			continue
		var/label = "[L]"
		var/n = 2
		while(label in by_name)
			label = "[L] ([n++])"
		by_name[label] = L
	return by_name

/obj/structure/closet/proc/has_prey(datum/act/op/A)
	return length(prey_by_name(A.actor)) > 0

/// The choice a hidden devour offers: the ones shut in with the asker that can be eaten.
/datum/prompt/choice/prey
	question = "Please select a target."
	title = "Victim"

/datum/prompt/choice/prey/prepare(datum/act/A)
	var/datum/act/op/O = A
	var/obj/structure/closet/C = O?.holder
	choices = list()
	if(istype(C))
		for(var/label in C.prey_by_name(O.actor))
			choices += label

/// The chosen one is eaten, if both are still in.
/obj/structure/closet/proc/devoured(datum/act/op/A)
	var/mob/living/user = A.actor
	var/datum/prompt/R = A.answer
	var/mob/living/target = R ? prey_by_name(user)[R.value] : null
	if(!isliving(target)) //Safety.
		return OP_REFUSED
	if(get_dist(src, target) >= 1 || get_dist(src, user) >= 1) //in case they leave the locker
		return OP_REFUSED
	playsound(src, vore_sound, 25)
	user.begin_instant_nom(user, target, user, user.vore_selected)
	return OP_OK

/obj/structure/closet/bluespace/Initialize(mapload)
	. = ..()
	join_bluespace_network()

/// The icon is derived from closet_appearance in closet_after_init() (C5 parity).
/obj/structure/closet/state_exclude()
	return ..() + list("icon")
