//Chain link fences
//Sprites ported from /VG/

#define CUT_TIME 10 SECONDS
#define CLIMB_TIME 5 SECONDS

#define NO_HOLE 0 //section is intact
#define MEDIUM_HOLE 1 //medium hole in the section - can climb through
#define LARGE_HOLE 2 //large hole in the section - can walk through
#define MAX_HOLE_SIZE LARGE_HOLE

/obj/structure/fence
	name = "fence"
	desc = "A chain link fence. Not as effective as a wall, but generally it keeps people out."
	density = TRUE
	anchored = TRUE

	icon = 'icons/obj/fence.dmi'
	icon_state = "straight"

	var/cuttable = TRUE
	var/hole_size= NO_HOLE
	var/invulnerable = FALSE
	var/electric = FALSE

/obj/structure/fence/Initialize(mapload)
	update_cut_status()
	return ..()

CAPABILITIES(/obj/structure/fence)
	on_notice(/datum/notice/bumped, then(PROC_REF(bumped_into)))
	climb(gate = PROC_REF(needs_a_climbable_hole))
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	op("touch", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/// A fence is climbed through a medium hole: an intact one is too tight to, and a large one is walked through.
/obj/structure/fence/proc/needs_a_climbable_hole(mob/living/climber)
	switch(hole_size)
		if(NO_HOLE)
			return "There is no hole in \the [src] to climb through."
		if(LARGE_HOLE)
			return "The hole in \the [src] is big enough to walk through."
	return null

/obj/structure/fence/examine(mob/user)
	. = ..()

	switch(hole_size)
		if(MEDIUM_HOLE)
			. += "There is a large hole in it."
		if(LARGE_HOLE)
			. += "It has been completely cut through."

/obj/structure/fence/get_description_interaction()
	var/list/results = list()
	if(cuttable && !invulnerable && hole_size < MAX_HOLE_SIZE)
		results += "[desc_panel_image("wirecutters")]to [hole_size > NO_HOLE ? "expand the":"cut a"] hole into the fence, allowing passage."
	return results

/obj/structure/fence/end
	icon_state = "end"
	cuttable = FALSE

/obj/structure/fence/corner
	icon_state = "corner"
	cuttable = FALSE

/obj/structure/fence/post
	icon_state = "post"
	cuttable = FALSE

/obj/structure/fence/cut/medium
	icon_state = "straight_cut2"
	hole_size = MEDIUM_HOLE

/obj/structure/fence/cut/large
	icon_state = "straight_cut3"
	hole_size = LARGE_HOLE

// Projectiles can pass through fences.
/obj/structure/fence/CanPass(atom/movable/mover, turf/target)
	if(istype(mover, /obj/item/projectile))
		return TRUE
	return ..()

/// Old attack_hand: an electrified fence shocks whoever touches it.
/obj/structure/fence/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(electric && isliving(user) && !user.is_incorporeal())
		electrocute(user)
	return OP_OK

/// Old attackby: an electrified fence shocks through whatever conducts.
/obj/structure/fence/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(electric && isliving(user) && !user.is_incorporeal() && !(W.flags & NOCONDUCT))
		electrocute(user)
	return OP_OK

/obj/structure/fence/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(electric && isliving(user) && !user.is_incorporeal() && !(W.flags & NOCONDUCT) && electrocute(user))
		return OP_OK
	if(!cuttable)
		to_chat(user, span_warning("This section of the fence can't be cut."))
		return OP_OK
	if(invulnerable)
		to_chat(user, span_warning("This fence is too strong to cut through."))
		return OP_OK
	var/current_stage = hole_size
	if(current_stage >= MAX_HOLE_SIZE)
		to_chat(user, span_notice("This fence has too much cut out of it already."))
		return OP_OK
	act_message(user, src, MSG_SELF(span_danger("You start cutting through %T% with %I%.")), \
		MSG_OTHERS(span_danger("%U% starts cutting through %T% with %I%.")), \
		item = W)
	use_tool(user, W, src, delay = CUT_TIME, quality = TOOL_WIRECUTTER, volume = 50, receiver = src, on_done = PROC_REF(wirecutter_act_tool_done), done_args = list(user, current_stage))
	return OP_OK

/obj/structure/fence/proc/wirecutter_act_tool_done(mob/user, current_stage)
	if(!(current_stage == hole_size))
		return
	switch(++hole_size)
		if(MEDIUM_HOLE)
			act_message(user, src, others = span_notice("%U% cuts into %T% some more."))
			to_chat(user, span_notice("You could probably fit yourself through that hole now. Although climbing through would be much faster if you made it even bigger."))
		if(LARGE_HOLE)
			act_message(user, src, others = span_notice("%U% completely cuts through %T%."))
			to_chat(user, span_notice("The hole in \the [src] is now big enough to walk through."))
	update_cut_status()

/// Something walked into it (the bump action's notice).
/obj/structure/fence/proc/bumped_into(datum/act/A)
	var/datum/notice/bumped/N = A
	var/atom/movable/AM = N.bumper
	if(electric && isliving(AM))
		var/mob/living/L = AM
		if(!L.is_incorporeal())
			electrocute(L)

/obj/structure/fence/proc/update_cut_status()
	if(!cuttable)
		return
	set_density(TRUE)

	switch(hole_size)
		if(NO_HOLE)
			icon_state = initial(icon_state)
		if(MEDIUM_HOLE)
			icon_state = "straight_cut2"
		if(LARGE_HOLE)
			icon_state = "straight_cut3"
			set_density(FALSE)

//FENCE DOORS

/obj/structure/fence/door
	silicon_use = ROBOT_USE_HAND_ADJACENT // cyborgs open it from next to it; the AI can't
	name = "fence door"
	desc = "Not very useful without a real lock."
	icon_state = "door_closed"
	cuttable = FALSE
	var/open = FALSE
	var/locked = FALSE
	var/lock_id = null	//does the door have an associated key?
	var/lock_type = "simple"	//string matched to "pick_type" on /obj/item/lockpick
	var/can_pick = TRUE	//can it be picked/bypassed?
	var/lock_difficulty = 1	//multiplier to picking/bypassing time
	var/keysound = SFX_ITEMS_TOOLBELT_EQUIP

// the fence door is never electrified: its own Use replaces the fence's
CAPABILITIES(/obj/structure/fence/door)
	without("touch")
	without("item")
	op("door_hand", hand(), label("Use"), then(PROC_REF(interaction_door_hand)))
	op("door_item", item(/obj/item), label("Use"), then(PROC_REF(interaction_door_item)))

/obj/structure/fence/door/Initialize(mapload)
	update_door_status()
	return ..()

/obj/structure/fence/door/opened
	icon_state = "door_opened"
	open = TRUE
	density = TRUE

/obj/structure/fence/door/locked
	desc = "It looks like it has a strong padlock attached."
	locked = TRUE

/// Old attack_hand: open/close the door.
/obj/structure/fence/door/proc/interaction_door_hand(datum/act/op/A)
	door_used(A.actor)
	return OP_OK

/obj/structure/fence/door/proc/door_used(mob/user)
	if(can_open(user))
		toggle(user)
	else
		to_chat(user, span_warning("\The [src] is [!open ? "locked" : "stuck open"]."))

/// Old attackby: lock/unlock with the matching key, pick the lock, or fall back to toggling.
/obj/structure/fence/door/proc/interaction_door_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	user.setClickCooldown(DEFAULT_ATTACK_COOLDOWN)
	if(istype(W,/obj/item/simple_key))
		var/obj/item/simple_key/key = W
		if(open)
			to_chat(user,span_notice("\The [src] must be closed in order for you to lock it."))
		else if(key.key_id != src.lock_id)
			to_chat(user,span_warning("The [key] doesn't fit \the [src]'s lock!"))
		else if(key.key_id == src.lock_id)
			act_message(user, src, others = span_notice("%U% [key.keyverb] %I% and [locked ? "unlocks" : "locks"] %T%."), item = key)
			locked = !locked
			playsound(src, keysound,100, 1)
		return OP_OK

	else if(istype(W,/obj/item/lockpick))
		var/obj/item/lockpick/L = W
		if(!locked)
			to_chat(user, span_notice("\The [src] isn't locked."))
			return OP_OK
		else if(lock_type != L.pick_type) //make sure our types match
			to_chat(user, span_warning("\The [L] can't pick \the [src]. Another tool might work?"))
			return OP_OK
		else if(!can_pick)
			to_chat(user, span_warning("\The [src] can't be [L.pick_verb]ed."))
			return OP_OK
		else
			to_chat(user, span_notice("You start to [L.pick_verb] the lock on \the [src]..."))
			playsound(src, keysound,100, 1)
			task_timed(user, L.pick_time * lock_difficulty, target = src, receiver = src, on_done = PROC_REF(attackby_timed_done), done_args = list(user))
		return OP_OK

	else
		door_used(user)
	return OP_OK

/obj/structure/fence/door/proc/attackby_timed_done(mob/user)
	to_chat(user, span_notice("Success!"))
	locked = FALSE

/obj/structure/fence/door/allow_pai_interaction(mob/living/silicon/pai/user, proximity_flag)
	return proximity_flag

/obj/structure/fence/door/proc/toggle(mob/user)
	switch(open)
		if(FALSE)
			act_message(user, src, others = span_notice("%U% opens %T%."))
			open = TRUE
		if(TRUE)
			act_message(user, src, others = span_notice("%U% closes %T%."))
			open = FALSE

	update_door_status()
	play_sfx(src, SFX_MACHINES_CLICK, 2)

/obj/structure/fence/door/proc/update_door_status()
	switch(open)
		if(FALSE)
			set_density(TRUE)
			icon_state = "door_closed"
		if(TRUE)
			set_density(FALSE)
			icon_state = "door_opened"

/obj/structure/fence/door/proc/can_open(mob/user)
	if(locked)
		return FALSE
	return TRUE

/obj/structure/fence/wood
	cuttable = FALSE
	name = "fence"
	desc = "A wooden fence. Not as effective as a wall, but generally it keeps people out."
	density = TRUE
	anchored = TRUE

	icon = 'icons/obj/fence.dmi'
	icon_state = "wood_straight"

/obj/structure/fence/wood/end
	icon_state = "wood_end"

/obj/structure/fence/wood/corner
	icon_state = "wood_corner"

/obj/structure/fence/hedge
	cuttable = FALSE
	name = "hedge"
	desc = "A large hedge. Not as effective as a wall, but generally it keeps people out."
	density = TRUE
	anchored = TRUE
	opacity = 1

	icon = 'icons/obj/fence.dmi'
	icon_state = "hedge_straight"

/obj/structure/fence/hedge/end
	icon_state = "hedge_end"

/obj/structure/fence/hedge/corner
	icon_state = "hedge_corner"

#undef CUT_TIME
#undef CLIMB_TIME

#undef NO_HOLE
#undef MEDIUM_HOLE
#undef LARGE_HOLE
#undef MAX_HOLE_SIZE

/obj/structure/fence/get_mechanics_info(list/additional_information)
	return ..(list("Projectiles can freely pass fences.") + additional_information)
