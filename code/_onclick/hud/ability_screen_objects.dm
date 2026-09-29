/atom/movable/screen/movable/ability_master
	name = "Abilities"
	icon = 'icons/mob/screen_spells.dmi'
	icon_state = "grey_spell_ready"
	var/list/atom/movable/screen/ability/ability_objects
	var/showing = 0 // If we're 'open' or not.

	var/open_state = "master_open"		// What the button looks like when it's 'open', showing the other buttons.
	var/closed_state = "master_closed"	// Button when it's 'closed', hiding everything else.

	screen_loc = ui_spell_master // TODO: Rename

	var/mob/my_mob	// The mob that possesses this hud object.

/atom/movable/screen/movable/ability_master/Initialize(mapload)
	. = ..()
	if(ismob(loc))
		rel_set(src, "my_mob", loc)
		update_abilities(0, loc)
		overlays.Add(closed_state)
	else
		message_admins("ERROR: ability_master's New() was not given an owner argument.  This is a bug.")


// the mob's ability_master var points back at us; a master deleted on its own clears it.

/atom/movable/screen/movable/ability_master/MouseDrop()
	if(showing)
		return

	return ..()

/atom/movable/screen/movable/ability_master/Click()
	if(!length(ability_objects)) // If we're empty for some reason.
		return

	toggle_open()

/atom/movable/screen/movable/ability_master/proc/toggle_open(forced_state = 0)
	if(showing && (forced_state != 2)) // We are closing the ability master, hide the abilities.
		for(var/atom/movable/screen/ability/O in ability_objects)
			if(my_mob() && my_mob().client)
				my_mob().client.screen -= O
		showing = 0
		overlays.len = 0
		overlays.Add(closed_state)
	else if(forced_state != 1) // We're opening it, show the icons. OR, if forced_state == 2, we're forcing it to open it.
		open_ability_master()
		update_abilities(1)
		showing = 1
		overlays.len = 0
		overlays.Add(open_state)
	update_icon()

/atom/movable/screen/movable/ability_master/proc/open_ability_master()
	var/list/screen_loc_xy = splittext(screen_loc,",")

	//Create list of X offsets
	var/list/screen_loc_X = splittext(screen_loc_xy[1],":")
	var/x_position = decode_screen_X(screen_loc_X[1])
	var/x_pix = screen_loc_X[2]

	//Create list of Y offsets
	var/list/screen_loc_Y = splittext(screen_loc_xy[2],":")
	var/y_position = decode_screen_Y(screen_loc_Y[1])
	var/y_pix = screen_loc_Y[2]

	for(var/i = 1; i <= length(ability_objects); i++)
		var/atom/movable/screen/ability/A = LAZYACCESS(ability_objects, i)
		var/xpos = x_position + (x_position < 8 ? 1 : -1)*(i%7)
		var/ypos = y_position + (y_position < 8 ? round(i/7) : -round(i/7))
		A.screen_loc = "[encode_screen_X(xpos)]:[x_pix],[encode_screen_Y(ypos)]:[y_pix]"
		if(my_mob() && my_mob().client)
			my_mob().client.screen += A
			my_mob().client.screen |= src

/atom/movable/screen/movable/ability_master/proc/update_abilities(forced = 0, mob/user)
	update_icon()
	if(user && user.client)
		if(!(src in user.client.screen))
			user.client.screen += src
	var/i = 1
	for(var/atom/movable/screen/ability/ability in ability_objects)
		ability.update_icon(forced)
		ability.index = i
		ability.maptext = "[ability.index]" // Slot number
		i++

/atom/movable/screen/movable/ability_master/update_icon()
	if(length(ability_objects))
		invisibility = INVISIBILITY_NONE
	else
		invisibility = INVISIBILITY_ABSTRACT

/atom/movable/screen/movable/ability_master/proc/add_ability(name_given)
	if(!name_given) return


	var/atom/movable/screen/ability/new_button = new /atom/movable/screen/ability
	rel_set(new_button, "ability_master", src)


	new_button.name = name_given
	new_button.ability_icon_state = name_given
	new_button.update_icon(1)
	own_add(src, "ability_objects", new_button)
	if(my_mob().client)
		toggle_open(2) //forces the icons to refresh on screen

/atom/movable/screen/movable/ability_master/proc/remove_ability(atom/movable/screen/ability/ability)
	if(!ability)
		return
	own_take_member(src, "ability_objects", ability)
	qdel(ability)

	if(length(ability_objects))
		toggle_open(showing + 1)
	update_icon()

/atom/movable/screen/movable/ability_master/proc/remove_all_abilities()
	for(var/atom/movable/screen/ability/A in ability_objects)
		remove_ability(A)

/atom/movable/screen/movable/ability_master/proc/get_ability_by_name(name_to_search)
	for(var/atom/movable/screen/ability/A in ability_objects)
		if(A.name == name_to_search)
			return A
	return null

/atom/movable/screen/movable/ability_master/proc/get_ability_by_proc_ref(proc_ref)
	for(var/atom/movable/screen/ability/verb_based/V in ability_objects)
		if(V.verb_to_call == proc_ref)
			return V
	return null

/atom/movable/screen/movable/ability_master/proc/get_ability_by_instance(obj/instance/)
	for(var/atom/movable/screen/ability/obj_based/O in ability_objects)
		if(O.object() == instance)
			return O
	return null

/mob/Login()
	..()
	if(ability_master)
		ability_master.toggle_open(2) //Force it to open on login.

DECLARE_DEFAULT_CHILD(/mob, "ability_master", /atom/movable/screen/movable/ability_master)

///////////ACTUAL ABILITIES////////////
//This is what you click to do things//
///////////////////////////////////////
/atom/movable/screen/ability
	icon = 'icons/mob/screen_spells.dmi'
	icon_state = "grey_spell_base"
	maptext_x = 3
	var/background_base_state = "grey"
	var/ability_icon_state = null
	var/index = 0

	var/atom/movable/screen/movable/ability_master/ability_master


// an ability leaves its master's list (the master owns the list; the ability can go first).
/atom/movable/screen/ability/on_destroy(force)
	var/atom/movable/screen/movable/ability_master/master = master_of()
	if(master)
		own_take_member(master, "ability_objects", src)
		if(!length(master.ability_objects))
			master.update_icon()
	..()

/atom/movable/screen/ability/update_icon()



	cut_overlays()
	icon_state = "[background_base_state]_spell_base"

	overlays += ability_icon_state


/atom/movable/screen/ability/Click()
	if(!usr)
		return

	activate()

/atom/movable/screen/ability/MouseDrop(atom/A)
	if(!A || A == src)
		return
	if(istype(A, /atom/movable/screen/ability))
		var/atom/movable/screen/ability/ability = A
		if(ability.master_of() && ability.master_of() == src.master_of())
			LAZYINITLIST(master_of().ability_objects); master_of().ability_objects.Swap(src.index, ability.index)
			master_of().toggle_open(2) // To update the UI.

// Makes the ability be triggered.  The subclasses of this are responsible for carrying it out in whatever way it needs to.
/atom/movable/screen/ability/proc/activate()
	to_chat(world, "[src] had activate() called.")
	return

// This checks if the ability can be used.
/atom/movable/screen/ability/proc/can_activate()
	return 1

/client/verb/activate_ability(slot as num)
	set name = ".activate_ability"
//	set hidden = 1
	if(!mob)
		return // Paranoid.
	if(isnull(slot) || !isnum(slot))
		to_chat(src, span_warning(".activate_ability requires a number as input, corrisponding to the slot you wish to use."))
		return // Bad input.
	if(!mob.ability_master)
		return // No abilities.
	if(slot > length(mob.ability_master.ability_objects) || slot <= 0)
		return // Out of bounds.
	var/atom/movable/screen/ability/A = LAZYACCESS(mob.ability_master.ability_objects, slot)
	A.activate()

//////////Verb Abilities//////////
//Buttons to trigger verbs/procs//
//////////////////////////////////

/atom/movable/screen/ability/verb_based
	var/verb_to_call = null
	var/object_used = null
	var/arguments_to_use = list()

/atom/movable/screen/ability/verb_based/activate()
	if(object_used && verb_to_call)
		call(object_used,verb_to_call)(arguments_to_use)

/atom/movable/screen/movable/ability_master/proc/add_verb_ability(object_given, verb_given, name_given, ability_icon_given, arguments)
	if(!object_given)
		message_admins("ERROR: add_verb_ability() was not given an object in its arguments.")
	if(!verb_given)
		message_admins("ERROR: add_verb_ability() was not given a verb/proc in its arguments.")
	if(get_ability_by_proc_ref(verb_given))
		return // Duplicate
	var/atom/movable/screen/ability/verb_based/A = new /atom/movable/screen/ability/verb_based()
	rel_set(A, "ability_master", src)
	A.object_used = object_given
	A.verb_to_call = verb_given
	A.ability_icon_state = ability_icon_given
	A.name = name_given
	if(arguments)
		A.arguments_to_use = arguments
	own_add(src, "ability_objects", A)
	if(my_mob().client)
		toggle_open(2) //forces the icons to refresh on screen

//Changeling Abilities
/atom/movable/screen/ability/verb_based/changeling
	icon_state = "ling_spell_base"
	background_base_state = "ling"

/atom/movable/screen/movable/ability_master/proc/add_ling_ability(object_given, verb_given, name_given, ability_icon_given, arguments)
	if(!object_given)
		message_admins("ERROR: add_ling_ability() was not given an object in its arguments.")
	if(!verb_given)
		message_admins("ERROR: add_ling_ability() was not given a verb/proc in its arguments.")
	if(get_ability_by_proc_ref(verb_given))
		return // Duplicate
	var/atom/movable/screen/ability/verb_based/changeling/A = new /atom/movable/screen/ability/verb_based/changeling()
	rel_set(A, "ability_master", src)
	A.object_used = object_given
	A.verb_to_call = verb_given
	A.ability_icon_state = ability_icon_given
	A.name = name_given
	if(arguments)
		A.arguments_to_use = arguments
	own_add(src, "ability_objects", A)
	if(my_mob().client)
		toggle_open(2) //forces the icons to refresh on screen

/////////Obj Abilities////////
//Buttons to trigger objects//
//////////////////////////////

/atom/movable/screen/ability/obj_based
	var/obj/object

/atom/movable/screen/ability/obj_based/activate()
	if(object())
		object().Click()

// Technomancer
/atom/movable/screen/ability/obj_based/technomancer
	icon_state = "wiz_spell_base"
	background_base_state = "wiz"

/atom/movable/screen/movable/ability_master/proc/add_technomancer_ability(obj/object_given, ability_icon_given)
	if(!object_given)
		message_admins("ERROR: add_technomancer_ability() was not given an object in its arguments.")
	if(get_ability_by_instance(object_given))
		return // Duplicate
	var/atom/movable/screen/ability/obj_based/technomancer/A = new /atom/movable/screen/ability/obj_based/technomancer()
	rel_set(A, "ability_master", src)
	rel_set(A, "object", object_given)
	A.ability_icon_state = ability_icon_given
	A.name = object_given.name
	own_add(src, "ability_objects", A)
	if(my_mob().client)
		toggle_open(2) //forces the icons to refresh on screen

/// LC-refs: the mob these abilities belong to -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/movable/ability_master/proc/my_mob() as /mob
	return my_mob

/// LC-refs: the object this ability clicks -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/ability/obj_based/proc/object() as /obj
	return object

/// LC-refs: the ability master listing this ability -- an OM handle (om_handle()), so it reads null once that is deleted.
/atom/movable/screen/ability/proc/master_of() as /atom/movable/screen/movable/ability_master
	return ability_master

REL_PAIR(/atom/movable/screen/movable/ability_master, my_mob, ability_master)
REL_PAIR(/mob, ability_master, my_mob)
