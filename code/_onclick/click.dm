/*
	Click code cleanup
	~Sayu
*/

// 1 decisecond click delay (above and beyond mob/next_move)
/mob/var/next_click = 0

// /atom/Click, DblClick, MouseWheel, MouseDrop and /mob/proc/ClickOn live with the
// input router (code/modules/keybindings/router.dm); per-actor click handling is in
// the capability adapters (code/modules/keybindings/adapters.dm).

/mob/proc/setClickCooldown(timeout)
	next_click = max(world.time + timeout, next_click)

/mob/proc/checkClickCooldown()
	if(next_click > world.time && !CONFIG_GET(flag/no_click_cooldown))
		return FALSE
	return TRUE

// Default behavior: ignore double clicks, the second click that makes the doubleclick call already calls for a normal click
/mob/proc/DblClickOn(atom/A, params)
	return

/*
	Translates into attack_hand, etc.

	Note: proximity_flag here is used to distinguish between normal usage (flag=1),
	and usage when clicking on things telekinetically (flag=0).  This proc will
	not be called at ranged except with telekinesis.

	proximity_flag is not currently passed to attack_hand, and is instead used
	in human click code to allow glove touches only at melee range.
*/
/mob/proc/UnarmedAttack(atom/A, proximity_flag)
	return

/mob/living/UnarmedAttack(atom/A, proximity_flag)

	if(is_incorporeal())
		return 0

	if(!SSticker)
		to_chat(src, "You cannot attack people before the game has started.")
		return 0

	if(stat)
		return 0

	// prevent picking up items while being in them
	if(istype(A, /obj/item) && A == loc)
		return 0

	return 1

/*
	Ranged unarmed attack:

	This currently is just a default for all mobs, involving
	laser eyes and telekinesis.  You could easily add exceptions
	for things like ranged glove touches, spitting alien acid/neurotoxin,
	animals lunging, etc.
*/
/mob/proc/RangedAttack(atom/A, params)
	if(!mutation_count()) return
	if((has_mutation(LASER_EYES)) && IS_HARMING(src))
		LaserEyes(A) // moved into a proc below
	else if(has_telegrip())
		var/datum/input_adapter/telekinesis/telekinesis = INPUT_ADAPTER(telekinesis)
		telekinesis.use(src, A, null, params)
/*
	Restrained ClickOn

	Used when you are handcuffed and click things.
	Not currently used by anything but could easily be.
*/
/mob/proc/RestrainedClickOn(atom/A)
	return

/*
	Middle click
	Only used for swapping hands
*/
/mob/proc/MiddleClickOn(atom/A)
	swap_hand()
	return

/*
	Shift click
	For most mobs, examine.
	This is overridden in ai.dm
*/
/mob/proc/ShiftClickOn(atom/A)
	A.ShiftClick(src)
	return

/atom/proc/ShiftClick(mob/user)
	if(user.client && !user.is_remote_viewing())
		user.examinate(src)
	return

/mob/proc/TurfAdjacent(turf/tile)
	return tile.Adjacent(src)

/mob/proc/ShiftMiddleClickOn(atom/A)
	src.pointed(A)
	return

/*
	Misc helpers

	Laser Eyes: as the name implies, handles this since nothing else does currently
	face_atom: turns the mob towards what you clicked on
*/
/mob/proc/LaserEyes(atom/A, params)
	return

/mob/living/LaserEyes(atom/A, params)
	setClickCooldown(4)
	var/turf/T = get_turf(src)

	var/obj/item/projectile/beam/laser_vision/LE = new (T)
	LE.icon = 'icons/effects/genetics.dmi'
	LE.icon_state = "eyelasers"
	playsound(src, 'sound/weapons/taser2.ogg', 75, 1)
	LE.firer = src
	LE.preparePixelProjectile(A, src, params)
	LE.fire()

/mob/living/carbon/human/LaserEyes(atom/A, params)
	if(nutrition>0)
		..()
		nutrition = max(nutrition - rand(1,5),0)
		refresh_hud()
	else
		to_chat(src, span_warning("You're out of energy!  You need food!"))

// Simple helper to face what you clicked on, in case it should be needed in more than one place
/mob/proc/face_atom(atom/atom_to_face)
	if(buckled || stat != CONSCIOUS || !atom_to_face || !x || !y || !atom_to_face.x || !atom_to_face.y)
		return
	var/dx = atom_to_face.x - x
	var/dy = atom_to_face.y - y
	if(!dx && !dy) // Wall items are graphically shifted but on the floor
		if(atom_to_face.pixel_y > 16)
			set_dir(NORTH)
		else if(atom_to_face.pixel_y < -16)
			set_dir(SOUTH)
		else if(atom_to_face.pixel_x > 16)
			set_dir(EAST)
		else if(atom_to_face.pixel_x < -16)
			set_dir(WEST)
		return

	if(abs(dx) < abs(dy))
		if(dy > 0)
			set_dir(NORTH)
		else
			set_dir(SOUTH)
	else
		if(dx > 0)
			set_dir(EAST)
		else
			set_dir(WEST)

/atom/movable/screen/click_catcher
	name = "" // Empty string names don't show up in context menu clicks
	icon = 'icons/mob/screen_gen.dmi'
	icon_state = "click_catcher"
	plane = CLICKCATCHER_PLANE
	layer = LAYER_HUD_UNDER
	mouse_opacity = 2
	screen_loc = "SOUTHWEST to NORTHEAST"

/atom/movable/screen/click_catcher/Initialize(mapload, ...)
	. = ..()
	verbs.Cut()

/atom/movable/screen/click_catcher/Click(location, control, params)
	var/list/P = params2list(params)
	switch(GLOB.input_router.classify(P, GLOB.input_router.click_catcher_table()))
		if(INPUT_ACTION_SWAP_HANDS)
			if(istype(usr, /mob/living/carbon))
				var/mob/living/carbon/C = usr
				C.swap_hand()
				return 1
	var/turf/T = get_turf(usr)
	if(T)
		T = screen_loc2turf(P[SCREEN_LOC], T)
		if(T)
			if(GLOB.input_router.classify(P, GLOB.input_router.shift_table()) == INPUT_ACTION_INSPECT)
				usr.face_atom(T)
				return 1
			T.Click(location, control, params)
	return 1

/// MouseWheelOn
/mob/proc/MouseWheelOn(atom/A, delta_x, delta_y, params)

/mob/proc/check_click_intercept(params,A)
	//Client level intercept
	if(client?.click_intercept)
		if(call(client.click_intercept, "InterceptClickOn")(src, params, A))
			return TRUE

	//Mob level intercept
	if(click_intercept)
		if(call(click_intercept, "InterceptClickOn")(src, params, A))
			return TRUE

	return FALSE
