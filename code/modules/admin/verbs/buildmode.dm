#define BUILDMODE_BASIC 	1
#define BUILDMODE_ADVANCED 	2
#define BUILDMODE_EDIT 		3
#define BUILDMODE_THROW 	4
#define BUILDMODE_ROOM 		5
#define BUILDMODE_LADDER 	6
#define BUILDMODE_CONTENTS 	7
#define BUILDMODE_LIGHTS 	8
#define BUILDMODE_AI 		9
#define BUILDMODE_DROP 		10

#define LAST_BUILDMODE		10

/proc/togglebuildmode(mob/M as mob in REGISTRY_MEMBERS(REGISTRY_PLAYERS))
	set name = "Toggle Build Mode"
	set category = VERB_CAT_SPECIAL_VERBS
	if(M.client)
		if(M.client.buildmode)
			log_admin("[key_name(M)] exited build mode.")
			M.client.buildmode = 0
			M.client.show_popup_menus = 1
			M.plane_holder.set_vis(VIS_BUILDMODE, FALSE)
			for(var/obj/effect/bmode/buildholder/H in REGISTRY_MEMBERS(REGISTRY_BUILDMODE_HOLDERS))
				if(H.cl() == M.client)
					spent(H, M)
		else
			log_admin("[key_name(M)] entered build mode.")
			M.client.buildmode = 1
			M.client.show_popup_menus = 0
			M.plane_holder.set_vis(VIS_BUILDMODE, TRUE)

			var/obj/effect/bmode/buildholder/H = new/obj/effect/bmode/buildholder()
			var/obj/effect/bmode/builddir/A = new/obj/effect/bmode/builddir(H)
			rel_set(A, nameof(A.master), H)
			var/obj/effect/bmode/buildhelp/B = new/obj/effect/bmode/buildhelp(H)
			rel_set(B, nameof(B.master), H)
			var/obj/effect/bmode/buildmode/C = new/obj/effect/bmode/buildmode(H)
			rel_set(C, nameof(C.master), H)
			var/obj/effect/bmode/buildquit/D = new/obj/effect/bmode/buildquit(H)
			rel_set(D, nameof(D.master), H)

			rel_set(H, nameof(H.builddir), A)
			rel_set(H, nameof(H.buildhelp), B)
			rel_set(H, nameof(H.buildmode), C)
			rel_set(H, nameof(H.buildquit), D)
			M.client.screen += A
			M.client.screen += B
			M.client.screen += C
			M.client.screen += D
			H.cl_ckey = M.client.ckey // clients are not datums: held by ckey

/obj/effect/bmode//Cleaning up the tree a bit
	density = TRUE
	anchored = TRUE
	layer = LAYER_HUD_BASE
	plane = PLANE_PLAYER_HUD
	dir = NORTH
	icon = 'icons/misc/buildmode.dmi'
	/// The build holder this button belongs to (a relation view; the holder owns us)
	var/tmp/obj/effect/bmode/buildholder/master

// Comes off its builder's screen: its holder's client.

/obj/effect/bmode/builddir
	icon_state = "build"
	screen_loc = "NORTH,WEST"

/obj/effect/bmode/builddir/Click()
	switch(dir)
		if(NORTH)
			set_dir(EAST)
		if(EAST)
			set_dir(SOUTH)
		if(SOUTH)
			set_dir(WEST)
		if(WEST)
			set_dir(NORTHWEST)
		if(NORTHWEST)
			set_dir(NORTH)
	return 1

/obj/effect/bmode/buildhelp
	icon = 'icons/misc/buildmode.dmi'
	icon_state = "buildhelp"
	screen_loc = "NORTH,WEST+1"

CAPABILITIES(/obj/effect/bmode/buildhelp)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/effect/bmode/buildhelp/proc/click_input(datum/act/input/A)
	return show_help_with_actor(A.actor)

/obj/effect/bmode/buildhelp/proc/show_help_with_actor(mob/user)
	switch(master().cl().buildmode)

		if(BUILDMODE_BASIC)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button        = Construct / Upgrade<br>\
							Right Mouse Button       = Deconstruct / Delete / Downgrade<br>\
							Left Mouse Button + ctrl = R-Window<br>\
							Left Mouse Button + alt  = Airlock<br><br>\
							Use the button in the upper left corner to<br>\
							change the direction of built objects.<br>\
							***********************************************************"))

		if(BUILDMODE_ADVANCED)
			to_chat(user, span_notice("***********************************************************<br>\
							Right Mouse Button on buildmode button = Set object type<br>\
							Middle Mouse Button on buildmode button= On/Off object type saying<br>\
							Middle Mouse Button on turf/obj        = Capture object type<br>\
							Left Mouse Button on turf/obj          = Place objects<br>\
							Right Mouse Button                     = Delete objects<br>\
							Mouse Button + ctrl                    = Copy object type<br>\
							Left Mouse Button + alt                = Open View Variable<br>\
							Right Mouse Button + alt               = Call Proc<br><br>\
							Use the button in the upper left corner to<br>\
							change the direction of built objects.<br>\
							***********************************************************"))

		if(BUILDMODE_EDIT)
			to_chat(user, span_notice("***********************************************************<br>\
							Right Mouse Button on buildmode button = Select var(type) & value<br>\
							Left Mouse Button on turf/obj/mob      = Set var(type) & value<br>\
							Right Mouse Button on turf/obj/mob     = Reset var's value<br>\
							***********************************************************"))

		if(BUILDMODE_THROW)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button on turf/obj/mob      = Select<br>\
							Right Mouse Button on turf/obj/mob     = Throw<br>\
							***********************************************************"))

		if(BUILDMODE_ROOM)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button on turf              = Select as point A<br>\
							Right Mouse Button on turf             = Select as point B<br>\
							Right Mouse Button on buildmode button = Change floor/wall type/area name<br>\
							***********************************************************"))

		if(BUILDMODE_LADDER)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button on turf              = Set as upper ladder loc<br>\
							Right Mouse Button on turf             = Set as lower ladder loc<br>\
							***********************************************************"))

		if(BUILDMODE_CONTENTS)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button on turf/obj/mob      = Select<br>\
							Right Mouse Button on turf/obj/mob     = Move into selection<br>\
							***********************************************************"))

		if(BUILDMODE_LIGHTS)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button on turf/obj/mob      = Make it glow<br>\
							Right Mouse Button on turf/obj/mob     = Reset glowing<br>\
							Right Mouse Button on buildmode button = Change glow properties<br>\
							***********************************************************"))

		if(BUILDMODE_AI)
			to_chat(user, span_notice("***********************************************************<br>\
							Left Mouse Button drag box             = Select only mobs in box<br>\
							Left Mouse Button drag box + shift     = Select additional mobs in area<br>\
							Left Mouse Button on non-mob           = Deselect all mobs<br>\
							Left Mouse Button on AI mob            = Select/Deselect mob<br>\
							Left Mouse Button + alt on AI mob      = Toggle hostility on mob<br>\
							Left Mouse Button + shift on AI mob    = Toggle AI (also resets)<br>\
							Left Mouse Button + ctrl on AI mob 	   = Copy mob faction<br>\
							Middle Mouse Button + alt on any atom  = Add atom to entity narrate menu <br>\
							Middle Mouse Button + shift on any     = Set selected mob(s) to wander<br>\
							Middle Mouse Button + ctrl on any      = Set selected mob(s) to NOT wander<br>\
							Right Mouse Button + ctrl on any mob   = Paste mob faction copied with Left Mouse Button + shift<br>\
							Right Mouse Button on enemy mob        = Command selected mobs to attack mob<br>\
							Right Mouse Button on allied mob       = Command selected mobs to follow mob<br>\
							Right Mouse Button + shift on any mob  = Command selected mobs to follow mob regardless of faction<br>\
							Note: The following also reset the mob's home position:<br>\
							Right Mouse Button on tile             = Command selected mobs to move to tile (will cancel if enemies are seen)<br>\
							Right Mouse Button + shift on tile     = Command selected mobs to reposition to tile (will not be interrupted by enemies)<br>\
							Right Mouse Button + alt on obj/turfs  = Command selected mobs to attack obj/turf<br>\
							***********************************************************"))

		if(BUILDMODE_DROP)
			to_chat(user, span_notice("***********************************************************<br>\
							Right Mouse Button on buildmode button = Set object type<br>\
							Middle Mouse Button on buildmode button= On/Off object type saying<br>\
							Middle Mouse Button on turf/obj        = Capture object type<br>\
							Left Mouse Button on turf/obj          = Drop objects safely<br>\
							Right Mouse Button                     = Drop objects unsafely<br>\
							Mouse Button + ctrl                    = Copy object type<br><br>\
							***********************************************************"))
	return 1

/obj/effect/bmode/buildquit
	icon_state = "buildquit"
	screen_loc = "NORTH,WEST+3"

/obj/effect/bmode/buildquit/Click()
	togglebuildmode(master().cl().mob)
	return 1

/obj/effect/bmode/buildholder
	density = FALSE
	anchored = TRUE
	/// The builder's ckey (a client is not a datum, so it is held by key); read with cl().
	var/tmp/cl_ckey
	var/obj/effect/bmode/builddir/builddir = null
	var/obj/effect/bmode/buildhelp/buildhelp = null
	var/obj/effect/bmode/buildmode/buildmode = null
	var/obj/effect/bmode/buildquit/buildquit = null
	var/tmp/atom/movable/throw_atom
	/// Mobs selected for AI orders (a relation list)
	var/list/selected_mobs
	var/copied_faction = null
	var/warned = 0

CAPABILITIES(/obj/effect/bmode/buildholder)
	owns_one(nameof(builddir), /obj/effect/bmode/builddir)
	owns_one(nameof(buildhelp), /obj/effect/bmode/buildhelp)
	owns_one(nameof(buildmode), /obj/effect/bmode/buildmode)
	owns_one(nameof(buildquit), /obj/effect/bmode/buildquit)

REGISTRY_MEMBERSHIP(/obj/effect/bmode/buildholder, REGISTRY_BUILDMODE_HOLDERS)


// AI mobs it selected are deselected.
/obj/effect/bmode/buildholder/on_destroy(force)
	for(var/mob/living/unit in selected_mobs?.Copy())
		deselect_AI_mob(cl(), unit)
	rel_clear(src, nameof(selected_mobs))
	..()

/// The first base-turf deletion asks once; the answer does that deletion.
/obj/effect/bmode/buildholder/proc/ask_base_turf(mob/user, turf/T)
	open_request(src, /datum/prompt/choice/buildmode_base_turf, PROC_REF(base_turf_acknowledged), answerer = user, subject = T)

/datum/prompt/choice/buildmode_base_turf
	title = "GRIEF ALERT"
	question = "Are you -sure- you want to delete this turf and make it the base turf for this Z level?"
	choices = list("No", "Yes")
	buttons = TRUE
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE

/datum/prompt/choice/buildmode_base_turf/recheck_extra()
	var/obj/effect/bmode/buildholder/holder = owner
	var/mob/user = answerer
	var/turf/target = subject
	if(!istype(holder) || QDELETED(holder) || !istype(user) || QDELETED(user) || !istype(target) || QDELETED(target))
		return "gone"
	return null

/obj/effect/bmode/buildholder/proc/base_turf_acknowledged(datum/act/request/context)
	if(!context.answer || context.answer.value != "Yes")
		return
	var/mob/user = context.answer.answerer
	var/turf/T = context.answer.subject
	warned = 1
	log_admin("[key_name(user)] has acknowledged the deletion of [T] and turned it into base turf. This could have resulted in spacing.")
	T.ChangeTurf(get_base_turf_by_area(T)) //Defaults to Z if area does not have a special base turf.
	T.flags |= ADMIN_SPAWNED

/obj/effect/bmode/buildholder/proc/select_AI_mob(client/C, mob/living/unit)
	rel_add(src, nameof(selected_mobs), unit)
	C.images += unit.selected_image

/obj/effect/bmode/buildholder/proc/deselect_AI_mob(client/C, mob/living/unit)
	rel_remove(src, nameof(selected_mobs), unit)
	C.images -= unit.selected_image

/obj/effect/bmode/buildmode
	icon_state = "buildmode1"
	screen_loc = "NORTH,WEST+2"
	var/varholder = "name"
	var/valueholder = "derp"
	var/objholder = null
	var/objsay = 1

	var/wall_holder = /turf/simulated/wall
	var/floor_holder = /turf/simulated/floor/plating
	var/tmp/turf/coordA
	var/tmp/turf/coordB
	var/area_enabled = 0
	var/area_name = "New Area"

	var/new_light_color = "#FFFFFF"
	var/new_light_range = 3
	var/new_light_intensity = 3

CAPABILITIES(/obj/effect/bmode/buildmode)
	click_on(PROC_REF(click_input))

/// The native Click's actor and arguments, handed over by the engine (click_on(), code/engine/lifeforms/input.dm).
/obj/effect/bmode/buildmode/proc/click_input(datum/act/input/A)
	return configure_with_actor(A.actor, A.params)

/obj/effect/bmode/buildmode/proc/configure_with_actor(mob/user, params)
	var/list/pa = params2list(params)

	if(pa.Find("middle"))
		switch(master().cl().buildmode)
			if(BUILDMODE_ADVANCED)
				objsay=!objsay

	if(pa.Find("left"))
		if(master().cl().buildmode == LAST_BUILDMODE)
			master().cl().buildmode = 1
		else
			master().cl().buildmode++
		src.icon_state = "buildmode[master().cl().buildmode]"

	else if(pa.Find("right"))
		switch(master().cl().buildmode)
			if(BUILDMODE_BASIC)

				return 1
			if(BUILDMODE_ADVANCED)
				ask_path(user, "objholder")

			if(BUILDMODE_EDIT)
				open_request(src, /datum/prompt/text/buildmode_edit, PROC_REF(ask_edit_type), answerer = user, title = "Name", question = "Enter variable name:", default = "name")

			if(BUILDMODE_ROOM)
				open_request(src, /datum/prompt/choice/buildmode_room_setting, PROC_REF(ask_area_name), answerer = user, title = "Room Builder", question = "Would you like to generate a new area as well?", choices = list("No", "Yes"), buttons = TRUE)

			if(BUILDMODE_LIGHTS)
				open_request(src, /datum/prompt/choice/buildmode_light, PROC_REF(ask_light_value), answerer = user, title = "Light Maker", question = "Change the new light range, power, or color?", choices = list("Range", "Power", "Color"), buttons = TRUE)
			if(BUILDMODE_DROP)
				ask_path(user, "objholder")
	return 1

/proc/build_click(mob/user, buildmode, params, obj/object)
	if(!user?.client)
		return
	var/obj/effect/bmode/buildholder/holder = null
	for(var/obj/effect/bmode/buildholder/H)
		if(H.cl() == user.client)
			holder = H
			break
	if(!holder) return
	var/list/pa = params2list(params)

	switch(buildmode)
		if(BUILDMODE_BASIC)
			if(istype(object,/turf) && pa.Find("left") && !pa.Find("alt") && !pa.Find("ctrl") )
				if(istype(object,/turf/space))
					var/turf/T = object
					T.ChangeTurf(/turf/simulated/floor)
					T.flags |= ADMIN_SPAWNED
					return
				else if(istype(object,/turf/simulated/floor))
					var/turf/T = object
					T.ChangeTurf(/turf/simulated/wall)
					T.flags |= ADMIN_SPAWNED
					return
				else if(istype(object,/turf/simulated/wall))
					var/turf/T = object
					T.ChangeTurf(/turf/simulated/wall/r_wall)
					T.flags |= ADMIN_SPAWNED
					return
			else if(pa.Find("right"))
				if(istype(object,/turf/simulated/wall))
					var/turf/T = object
					T.ChangeTurf(/turf/simulated/floor)
					T.flags |= ADMIN_SPAWNED
					return
				else if(istype(object,/turf/simulated/floor))
					var/turf/T = object
					if(!holder.warned)
						holder.ask_base_turf(user, T)
						return
					T.ChangeTurf(get_base_turf_by_area(T)) //Defaults to Z if area does not have a special base turf.
					T.flags |= ADMIN_SPAWNED
					return
				else if(istype(object,/turf/simulated/wall/r_wall))
					var/turf/T = object
					T.ChangeTurf(/turf/simulated/wall)
					T.flags |= ADMIN_SPAWNED
					return
				else if(istype(object,/obj))
					log_admin("[key_name(user)] qdel'd [object].")
					spent(object, user)
					return
			else if(istype(object,/turf) && pa.Find("alt") && pa.Find("left"))
				var/obj/new_door = new /obj/machinery/door/airlock(get_turf(object))
				new_door.flags |= ADMIN_SPAWNED
			else if(istype(object,/turf) && pa.Find("ctrl") && pa.Find("left"))
				switch(holder.builddir.dir)
					if(NORTH)
						var/obj/structure/window/reinforced/WIN = new/obj/structure/window/reinforced(get_turf(object))
						WIN.set_dir(NORTH)
						WIN.flags |= ADMIN_SPAWNED
					if(SOUTH)
						var/obj/structure/window/reinforced/WIN = new/obj/structure/window/reinforced(get_turf(object))
						WIN.set_dir(SOUTH)
						WIN.flags |= ADMIN_SPAWNED
					if(EAST)
						var/obj/structure/window/reinforced/WIN = new/obj/structure/window/reinforced(get_turf(object))
						WIN.set_dir(EAST)
						WIN.flags |= ADMIN_SPAWNED
					if(WEST)
						var/obj/structure/window/reinforced/WIN = new/obj/structure/window/reinforced(get_turf(object))
						WIN.set_dir(WEST)
						WIN.flags |= ADMIN_SPAWNED
					if(NORTHWEST)
						var/obj/structure/window/reinforced/WIN = new/obj/structure/window/reinforced(get_turf(object))
						WIN.set_dir(NORTHWEST)

		if(BUILDMODE_ADVANCED)
			if(pa.Find("left") && !pa.Find("ctrl") && !pa.Find("alt"))
				if(ispath(holder.buildmode.objholder,/turf))
					var/turf/T = get_turf(object)
					T.ChangeTurf(holder.buildmode.objholder)
					T.flags |= ADMIN_SPAWNED
				else if(ispath(holder.buildmode.objholder))
					var/obj/A = new holder.buildmode.objholder (get_turf(object))
					A.set_dir(holder.builddir.dir)
					A.flags |= ADMIN_SPAWNED
					//log_admin("BUILDMODE: [key_name(user)] spawned [A] at x:[object.x] y:[object.y] z:[object.z].") //Too spammy. We'll just log when they select the item initially.
			else if(pa.Find("right") && !pa.Find("alt"))
				if(isobj(object))
					log_admin("BUILDMODE: [key_name(user)] qdel'd [object].")
					spent(object, user)
			else if(pa.Find("ctrl"))
				holder.buildmode.objholder = object.type
				to_chat(user, span_notice("[object]([object.type]) copied to buildmode."))
				log_admin("BUILDMODE: [key_name(user)] has copied [object.type] to buildmode.")
			else if(pa.Find("left") && pa.Find("alt"))
				user.client.debug_variables(object)
			else if(pa.Find("right") && pa.Find("alt"))
				SSadmin_verbs.dynamic_invoke_verb(user, /datum/admin_verb/call_proc_datum, object) //This'll log itself later when the proc is actually called.
			if(pa.Find("middle"))
				holder.buildmode.objholder = text2path("[object.type]")
				if(holder.buildmode.objsay)
					to_chat(user, "[object.type]")
					log_admin("BUILDMODE: [key_name(user)] selected [object.type].")

		if(BUILDMODE_EDIT)
			if(pa.Find("left")) //I cant believe this shit actually compiles.
				if(object.vars.Find(holder.buildmode.varholder))
					log_admin("[key_name(user)] modified [object.name]'s [holder.buildmode.varholder] to [holder.buildmode.valueholder]")
					object.vars[holder.buildmode.varholder] = holder.buildmode.valueholder // ALLOW(api): admin buildmode var edits
					object.datum_flags |= DF_VAR_EDITED
				else
					to_chat(user, span_danger("[initial(object.name)] does not have a var called '[holder.buildmode.varholder]'"))
			if(pa.Find("right"))
				if(object.vars.Find(holder.buildmode.varholder))
					log_admin("[key_name(user)] modified [object.name]'s [holder.buildmode.varholder] to initial state.")
					object.vars[holder.buildmode.varholder] = initial(object.vars[holder.buildmode.varholder]) // ALLOW(api): admin buildmode var edits
					object.datum_flags |= DF_VAR_EDITED
				else
					to_chat(user, span_danger("[initial(object.name)] does not have a var called '[holder.buildmode.varholder]'"))

		if(BUILDMODE_THROW)
			if(pa.Find("left"))
				if(istype(object, /atom/movable))
					rel_set(holder, nameof(holder.throw_atom), object)
					log_admin("[key_name(user)] selected [object] to throw.")
			if(pa.Find("right"))
				if(holder.throw_atom())
					holder.throw_atom().throw_at(object, 10, 1) //No logging here since this gets spammed.

		if(BUILDMODE_ROOM)
			if(pa.Find("left"))
				rel_set(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordA), get_turf(object))
				to_chat(user, span_notice("Defined [object] ([object.type]) as point A."))

			if(pa.Find("right"))
				rel_set(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordB), get_turf(object))
				to_chat(user, span_notice("Defined [object] ([object.type]) as point B."))

			if(holder.buildmode.coordA() && holder.buildmode.coordB())
				if(isnull(holder.buildmode.area_name))
					to_chat(user, span_notice("ERROR: Insert area name before use."))
					rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordA))
					rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordB))
					return
				to_chat(user, span_notice("A and B set, creating rectangle."))
				holder.buildmode.make_rectangle(
					holder.buildmode.coordA(),
					holder.buildmode.coordB(),
					holder.buildmode.wall_holder,
					holder.buildmode.floor_holder,
					holder.buildmode.area_enabled,
					holder.buildmode.area_name)
				log_admin("BUILDMODE: [key_name(user)] has created a room starting at x: [get_x(holder.buildmode.coordA())] y: [get_y(holder.buildmode.coordA())] z: [get_z(holder.buildmode.coordA())] and ending at x: [get_x(holder.buildmode.coordB())] y: [get_y(holder.buildmode.coordB())] z: [get_z(holder.buildmode.coordB())].")
				rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordA))
				rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordB))

		if(BUILDMODE_LADDER)
			if(pa.Find("left"))
				rel_set(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordA), get_turf(object))
				to_chat(user, span_notice("Defined [object] ([object.type]) as upper ladder location."))

			if(pa.Find("right"))
				rel_set(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordB), get_turf(object))
				to_chat(user, span_notice("Defined [object] ([object.type]) as lower ladder location."))

			if(holder.buildmode.coordA() && holder.buildmode.coordB())
				to_chat(user, span_notice("Ladder locations set, building ladders."))
				var/obj/structure/ladder/A = new /obj/structure/ladder/up(holder.buildmode.coordA())
				var/obj/structure/ladder/B = new /obj/structure/ladder(holder.buildmode.coordB())
				rel_set(A, nameof(A.target_up), B) // pair: sets B.target_down
				A.flags |= ADMIN_SPAWNED
				B.flags |= ADMIN_SPAWNED
				A.update_icon()
				B.update_icon()
				log_admin("BUILDMODE: [key_name(user)] has created a ladder starting at x: [get_x(holder.buildmode.coordA())] y: [get_y(holder.buildmode.coordA())] z: [get_z(holder.buildmode.coordA())] and connecting to x: [get_x(holder.buildmode.coordB())] y: [get_y(holder.buildmode.coordB())] z: [get_z(holder.buildmode.coordB())].")
				rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordA))
				rel_clear(holder.buildmode, nameof(/obj/effect/bmode/buildmode::coordB))

		if(BUILDMODE_CONTENTS)
			if(pa.Find("left"))
				if(istype(object, /atom))
					rel_set(holder, nameof(holder.throw_atom), object)
			if(pa.Find("right"))
				if(holder.throw_atom() && istype(object, /atom/movable))
					object.forceMove(holder.throw_atom())
					log_admin("[key_name(user)] moved [object] into [holder.throw_atom()].")

		if(BUILDMODE_LIGHTS)
			if(pa.Find("left"))
				if(object)
					object.set_light(holder.buildmode.new_light_range, holder.buildmode.new_light_intensity, holder.buildmode.new_light_color)
					log_admin("[key_name(user)] adjusted [object]'s L I C to [holder.buildmode.new_light_range], [holder.buildmode.new_light_intensity], [holder.buildmode.new_light_color].")
			if(pa.Find("right"))
				if(object)
					object.set_light(0, 0, "#FFFFFF")
					log_admin("[key_name(user)] adjusted [object]'s light to default.")

		if(BUILDMODE_AI)
			if(pa.Find("left"))
				if(isliving(object))
					var/mob/living/L = object

					// Pause/unpause AI
					if(pa.Find("shift"))
						var/stance = (L.ai_brain ? (L.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE)
						if(!isnull(stance)) // Null means there's no AI datum or it has one but is player controlled w/o autopilot on.
							var/datum/ai_brain/AI = L.ai_brain
							if(stance == STANCE_SLEEP)
								AI.go_wake()
								L.datum_flags |= DF_VAR_EDITED //we'll consider messing with AI as varediting it.
								to_chat(user, span_notice("\The [L]'s AI has been enabled."))
								log_admin("[key_name(user)] activated [L]'s AI.")
							else
								AI.go_sleep()
								L.datum_flags |= DF_VAR_EDITED
								to_chat(user, span_notice("\The [L]'s AI has been disabled."))
								log_admin("[key_name(user)] deactivated [L]'s AI.")
							return
						else
							to_chat(user, span_warning("\The [L] is not AI controlled."))
						return

					// Toggle hostility
					if(pa.Find("alt"))
						if(L.ai_brain)
							var/datum/ai_brain/AI = L.ai_brain
							AI.set_hostile(!AI.get_hostile())
							L.datum_flags |= DF_VAR_EDITED
							to_chat(user, span_notice("\The [L] is now [AI.get_hostile() ? "hostile" : "passive"]."))
							log_admin("[key_name(user)] made [L]'s AI hostile.")
						else
							to_chat(user, span_warning("\The [L] is not AI controlled."))
						return

					// Copy faction
					if(pa.Find("ctrl"))
						holder.copied_faction = L.faction
						to_chat(user, span_notice("Copied faction '[holder.copied_faction]'."))
						return

					// Select/Deselect
					if(!isnull((L.ai_brain ? (L.ai_brain.primary_threat ? STANCE_FIGHT : STANCE_IDLE) : STANCE_IDLE)))
						if(L in holder.selected_mobs)
							holder.deselect_AI_mob(user.client, L)
							to_chat(user, span_notice("Deselected \the [L]."))
						else
							holder.select_AI_mob(user.client, L)
							to_chat(user, span_notice("Selected \the [L]."))
						return
					else
						to_chat(user, span_warning("\The [L] is not AI controlled."))
						return
				else //Not living
					for(var/mob/living/unit in holder.selected_mobs)
						holder.deselect_AI_mob(user.client, unit)

			if(pa.Find("middle"))
				if(pa.Find("shift"))
					to_chat(user, span_notice("All selected mobs set to wander"))
					log_admin("[key_name(user)] told selected mobs to wander.")
					for(var/mob/living/unit in holder.selected_mobs)
						var/datum/ai_brain/AI = unit.ai_brain
						if(AI)
							AI.wander = TRUE
						unit.datum_flags |= DF_VAR_EDITED
				if(pa.Find("ctrl"))
					to_chat(user, span_notice("Setting mobs set to NOT wander"))
					log_admin("[key_name(user)] told selected mobs to not wander.")
					for(var/mob/living/unit in holder.selected_mobs)
						var/datum/ai_brain/AI = unit.ai_brain
						if(AI)
							AI.wander = FALSE
						unit.datum_flags |= DF_VAR_EDITED
				if(pa.Find("alt") && isatom(object))
					to_chat(user, span_notice("Adding [object] to Entity Narrate List!"))
					log_admin("[key_name(user)] added [object] to the entity narration list.")
					SSadmin_verbs.dynamic_invoke_verb(user.client, /datum/admin_verb/add_mob_for_narration, object)

			if(pa.Find("right"))
				// Paste faction
				if(pa.Find("ctrl") && isliving(object))
					if(!holder.copied_faction)
						to_chat(user, span_warning("LMB+Shift a mob to copy their faction before pasting."))
						return
					else
						var/mob/living/L = object
						log_admin("[key_name(user)] changed [L]'s faction from [L.faction] to [holder.copied_faction].")
						L.faction = holder.copied_faction
						L.datum_flags |= DF_VAR_EDITED
						to_chat(user, span_notice("Pasted faction '[holder.copied_faction]'."))
						return

				if(istype(object, /atom)) // Force attack.
					var/atom/A = object

					if(pa.Find("alt"))
						var/i = 0
						for(var/mob/living/unit in holder.selected_mobs)
							var/datum/ai_brain/AI = unit.ai_brain
							AI.give_target(A)
							i++
						to_chat(user, span_notice("Commanded [i] mob\s to attack \the [A]."))
						log_admin("[key_name(user)] told selected mobs to attack [A].")
						var/image/orderimage = image(GLOB.buildmode_hud,A,"ai_targetorder")
						orderimage.plane = PLANE_BUILDMODE
						flick_overlay(orderimage, list(user.client), 8, TRUE)
						return

				if(isliving(object)) // Follow or attack.
					var/mob/living/L = object
					var/i = 0 // Attacking mobs.
					var/j = 0 // Following mobs.
					for(var/mob/living/unit in holder.selected_mobs)
						var/datum/ai_brain/AI = unit.ai_brain
						if(L.IIsAlly(unit) || !AI.hostile || pa.Find("shift"))
							AI.set_follow(L)
							j++
						else
							AI.give_target(L)
							i++
					var/message = "Commanded "
					if(i)
						message += "[i] mob\s to attack \the [L]"
						if(j)
							message += ", and "
						else
							message += "."
					if(j)
						message += "[j] mob\s to follow \the [L]."
					log_admin("[key_name(user)] told selected mobs to attack/follow [L].")
					to_chat(user, span_notice(message))
					var/image/orderimage = image(GLOB.buildmode_hud,L,"ai_targetorder")
					orderimage.plane = PLANE_BUILDMODE
					flick_overlay(orderimage, list(user.client), 8, TRUE)
					return

				if(isturf(object)) // Move or reposition.
					var/turf/T = object
					var/forced = 0
					var/told = 0
					for(var/mob/living/unit in holder.selected_mobs)
						var/datum/ai_brain/AI = unit.ai_brain
						if(!AI)
							unit.forceMove(T)
							forced++
							continue
						rel_set(AI, nameof(AI.home_turf), T)
						if(AI.process_flags == 0)
							unit.forceMove(T)
							forced++
						else
							AI.give_destination(T)
							told++
					to_chat(user, span_notice("Commanded [told] mob\s to move to \the [T], and manually placed [forced] of them."))
					log_admin("[key_name(user)] told selected mobs to move to [T].")
					var/image/orderimage = image(GLOB.buildmode_hud,T,"ai_turforder")
					orderimage.plane = PLANE_BUILDMODE
					flick_overlay(orderimage, list(user.client), 8, TRUE)
					return

		if(BUILDMODE_DROP)
			if(ispath(holder.buildmode.objholder,/turf))
				to_chat(user, span_warning("Cannot use turfs with this mode."))
				return
			if(pa.Find("left") && !pa.Find("ctrl"))
				if(ispath(holder.buildmode.objholder))
					drop_from_sky(get_turf(object), holder.buildmode.objholder, FALSE, TRUE)
					log_admin("[key_name(user)] dropped [holder.buildmode.objholder] onto [object] nonlethally.")
			else if(pa.Find("right"))
				if(ispath(holder.buildmode.objholder))
					drop_from_sky(get_turf(object), holder.buildmode.objholder, TRUE, TRUE)
					log_admin("[key_name(user)] dropped [holder.buildmode.objholder] onto [object] lethally.")
			else if(pa.Find("ctrl"))
				holder.buildmode.objholder = object.type
				to_chat(user, span_notice("[object]([object.type]) copied to buildmode."))
				log_admin("[key_name(user)] copied [object] ([object.type]) to buildmode.")
			if(pa.Find("middle"))
				holder.buildmode.objholder = text2path("[object.type]")
				log_admin("[key_name(user)] selected [holder.buildmode.objholder].")
				if(holder.buildmode.objsay)
					to_chat(user, "[object.type]")

/proc/build_drag(client/user, buildmode, atom/fromatom, atom/toatom, atom/fromloc, atom/toloc, fromcontrol, tocontrol, params)
	if(!user)
		return
	var/obj/effect/bmode/buildholder/holder = null
	for(var/obj/effect/bmode/buildholder/H)
		if(H.cl() == user)
			holder = H
			break
	if(!holder) return
	var/list/pa = params2list(params)

	switch(buildmode)
		if(BUILDMODE_AI)

			//Holding shift prevents the deselection of existing
			if(!pa.Find("shift"))
				for(var/mob/living/unit in holder.selected_mobs)
					holder.deselect_AI_mob(user, unit)

			var/turf/c1 = get_turf(fromatom)
			var/turf/c2 = get_turf(toatom)
			if(!c1 || !c2)
				return //Dragged outside window or something

			var/low_x = min(c1.x,c2.x)
			var/low_y = min(c1.y,c2.y)
			var/hi_x = max(c1.x,c2.x)
			var/hi_y = max(c1.y,c2.y)
			var/z = c1.z //Eh

			var/i = 0
			for(var/mob/living/L in REGISTRY_MEMBERS(REGISTRY_LIVING_MOBS))
				if(L.z != z || L.client)
					continue
				if(L.x >= low_x && L.x <= hi_x && L.y >= low_y && L.y <= hi_y)
					holder.select_AI_mob(user, L)
					i++

			to_chat(user, span_notice("Band-selected [i] mobs."))
			log_admin("[key_name(user)] selected [i] mobs. x:[low_x] y:[low_y]- x:[hi_x] y:[hi_y] z:[z].")
			return

/obj/effect/bmode/buildmode/proc/ask_edit_type(datum/act/request/context)
	if(!context.answer)
		return
	open_request(src, /datum/prompt/choice/buildmode_edit, PROC_REF(ask_edit_value), answerer = context.answer.answerer, title = "Type", question = "Select variable type:", choices = list("text","number","mob-reference","obj-reference","turf-reference"), step = context.answer.value)

/obj/effect/bmode/buildmode/proc/ask_edit_value(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_edit/ask = context.answer
	var/mob/user = ask.answerer
	switch(ask.value)
		if("text")
			open_request(src, /datum/prompt/text/buildmode_edit, PROC_REF(edit_text_entered), answerer = user, title = "Value", question = "Enter variable value:", default = "value", step = ask.step)
		if("number")
			open_request(src, /datum/prompt/number/buildmode_edit, PROC_REF(edit_number_entered), answerer = user, title = "Value", question = "Enter variable value:", default = 123, edit_var = ask.step)
		if("mob-reference")
			var/list/mob_choices = REGISTRY_MEMBERS(REGISTRY_MOBS)
			open_request(src, /datum/prompt/choice/buildmode_mob_reference, PROC_REF(edit_mob_ref_picked), answerer = user, choices = mob_choices?.Copy(), step = ask.step)
		if("obj-reference", "turf-reference")
			open_request(src, /datum/prompt/choice/buildmode_edit, PROC_REF(edit_ref_picked), answerer = user, title = "Value", question = "Enter variable value:", choices = world, step = ask.step)

/obj/effect/bmode/buildmode/proc/edit_text_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/buildmode_edit/ask = context.answer
	edit_answered(ask.answerer, ask.step, ask.value)

/obj/effect/bmode/buildmode/proc/edit_number_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/buildmode_edit/ask = context.answer
	edit_answered(ask.answerer, ask.edit_var, ask.value)

/obj/effect/bmode/buildmode/proc/edit_mob_ref_picked(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_mob_reference/ask = context.answer
	edit_answered(ask.answerer, ask.step, ask.value)

/obj/effect/bmode/buildmode/proc/edit_ref_picked(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_edit/ask = context.answer
	edit_answered(ask.answerer, ask.step, ask.value)

/obj/effect/bmode/buildmode/proc/edit_answered(mob/user, var_name, value)
	master().buildmode.varholder = var_name
	master().buildmode.valueholder = value
	log_admin("BUILDMODE: [key_name(user)] set var-edit: [valueholder].")

/obj/effect/bmode/buildmode/proc/ask_area_name(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_room_setting/ask = context.answer
	if(ask.value == "Yes")
		open_request(src, /datum/prompt/text/buildmode_room_name, PROC_REF(area_name_entered), answerer = ask.answerer, title = "Room Buildmode", question = "New area name")
		return
	area_enabled = 0
	ask_room_holder(ask.answerer)

/obj/effect/bmode/buildmode/proc/area_name_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/buildmode_room_name/ask = context.answer
	area_enabled = 1
	area_name = sanitize(ask.value, MAX_NAME_LEN)
	log_admin("BUILDMODE ROOM: [key_name(ask.answerer)] area: [area_name].")
	ask_room_holder(ask.answerer)

/// Optional: a cancel keeps the holders.
/obj/effect/bmode/buildmode/proc/ask_room_holder(mob/user)
	open_request(src, /datum/prompt/choice/buildmode_room_setting, PROC_REF(room_answered), answerer = user, title = "Room Builder", question = "Would you like to change the floor or wall holders?", choices = list("Floor", "Wall"), buttons = TRUE)

/obj/effect/bmode/buildmode/proc/room_answered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_room_setting/ask = context.answer
	switch(ask.value)
		if("Floor")
			ask_path(ask.answerer, "floor_holder", /turf/simulated/floor/plating)
		if("Wall")
			ask_path(ask.answerer, "wall_holder", /turf/simulated/wall)

/obj/effect/bmode/buildmode/proc/ask_light_value(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_light/ask = context.answer
	switch(ask.value)
		if("Range")
			open_request(src, /datum/prompt/number/buildmode_light, PROC_REF(light_number_entered), answerer = ask.answerer, title = "Light Maker", question = "New light range.", default = 3, light_setting = ask.value)
		if("Power")
			open_request(src, /datum/prompt/number/buildmode_light, PROC_REF(light_number_entered), answerer = ask.answerer, title = "Light Maker", question = "New light power.", default = 3, light_setting = ask.value)
		if("Color")
			open_request(src, /datum/prompt/color/buildmode_light, PROC_REF(light_color_picked), answerer = ask.answerer, title = "Light Maker", question = "New light color.", default = new_light_color, light_setting = ask.value)

/obj/effect/bmode/buildmode/proc/light_number_entered(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/number/buildmode_light/ask = context.answer
	lights_answered(ask.answerer, ask.light_setting, ask.value)

/obj/effect/bmode/buildmode/proc/light_color_picked(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/color/buildmode_light/ask = context.answer
	lights_answered(ask.answerer, ask.light_setting, ask.value)

/obj/effect/bmode/buildmode/proc/lights_answered(mob/user, what, input)
	if(!input)
		return
	switch(what)
		if("Range")
			new_light_range = input
			log_admin("BUILDMODE: [key_name(user)] set light r to [new_light_range].")
		if("Power")
			new_light_intensity = input
			log_admin("BUILDMODE: [key_name(user)] set light i to [new_light_intensity].")
		if("Color")
			new_light_color = input
			log_admin("BUILDMODE: [key_name(user)] set light c to [new_light_color].")

/// The atom paths containing `text`.
/obj/effect/bmode/buildmode/proc/paths_matching(text)
	var/list/matches = list()
	for(var/path in typesof(/atom))
		if(findtext("[path]", text))
			matches += path
	return matches

/// Asks for a typepath (typed in part, then picked from the matches) and stores it in `var_name`.
/obj/effect/bmode/buildmode/proc/ask_path(mob/user, var_name, default_path)
	open_request(src, /datum/prompt/text/buildmode_path, PROC_REF(ask_path_match), answerer = user, title = "Typepath", question = "Enter full or partial typepath.", default = "[default_path]", path_var = var_name)

/obj/effect/bmode/buildmode/proc/ask_path_match(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/text/buildmode_path/ask = context.answer
	var/mob/user = ask.answerer
	var/list/matches = paths_matching(ask.value)
	if(!matches.len)
		tgui_alert_async(user, "No results found.  Sorry.")
		return
	if(matches.len == 1)
		path_answered(user, ask.path_var, matches[1])
		return
	open_request(src, /datum/prompt/choice/buildmode_path, PROC_REF(path_picked), answerer = user, title = "Spawn Atom", question = "Select an atom type", choices = matches, path_var = ask.path_var)

/obj/effect/bmode/buildmode/proc/path_picked(datum/act/request/context)
	if(!context.answer)
		return
	var/datum/prompt/choice/buildmode_path/ask = context.answer
	path_answered(ask.answerer, ask.path_var, ask.value)

/obj/effect/bmode/buildmode/proc/path_answered(mob/user, var_name, result)
	log_admin("BUILDMODE/ITEM GENERATION: [key_name(user)] selected [result] to be spawned.")
	vars[var_name] = result // ALLOW(api): admin buildmode var edits

/obj/effect/bmode/buildmode/proc/make_rectangle(turf/A, turf/B, turf/wall_type, turf/floor_type, area_enabled, area_name)
	if(!A || !B) // No coords
		return
	if(A.z != B.z) // Not same z-level
		return

	var/height = A.y - B.y
	var/width = A.x - B.x
	var/z_level = A.z

	var/turf/lower_left_corner = null
	// First, try to find the lowest part
	var/desired_y = 0
	if(A.y <= B.y)
		desired_y = A.y
	else
		desired_y = B.y

	//Now for the left-most part.
	var/desired_x = 0
	if(A.x <= B.x)
		desired_x = A.x
	else
		desired_x = B.x

	lower_left_corner = locate(desired_x, desired_y, z_level)

	// Now we can begin building the actual room.  This defines the boundries for the room.
	var/low_bound_x = lower_left_corner.x
	var/low_bound_y = lower_left_corner.y

	var/high_bound_x = lower_left_corner.x + abs(width)
	var/high_bound_y = lower_left_corner.y + abs(height)

	var/origin_x = lower_left_corner.x + round((abs(width)/2))
	var/origin_y = lower_left_corner.y + round((abs(height)/2))
	var/turf/origin

	for(var/i = low_bound_x, i <= high_bound_x, i++)
		for(var/j = low_bound_y, j <= high_bound_y, j++)
			var/turf/T = locate(i, j, z_level)
			if(i == low_bound_x || i == high_bound_x || j == low_bound_y || j == high_bound_y)
				if(isturf(wall_type))
					T.ChangeTurf(wall_type)
					T.flags |= ADMIN_SPAWNED
				else
					var/atom/new_thing = new wall_type(T) //wall_type can be ANY /obj, /mob, /turf, etc
					new_thing.flags |= ADMIN_SPAWNED

			else
				if(T.x == origin_x && T.y == origin_y) //Get the middle of the square.
					origin = T
				if(isturf(floor_type))
					T.ChangeTurf(floor_type)
					T.flags |= ADMIN_SPAWNED
				else
					var/atom/new_thing = new floor_type(T)
					new_thing.flags |= ADMIN_SPAWNED

	if(area_enabled) //Let's try not to make a new area unless you got walls and a floor.
		create_buildmode_area(area_name, origin) //Generates a new area.

/proc/create_buildmode_area(area_name, turf/origin)
	var/turfs = detect_room_buildmode(origin)

	var/area/newA
	var/area/oldA = get_area(origin)
	var/str = area_name
	str = sanitize(str,MAX_NAME_LEN)
	if(!str || !length(str)) //cancel
		return
	newA = new /area/buildmode
	newA.dynamic_lighting = FALSE // Without this it's pitch black if you build anywhere but space.
	newA.luminosity = TRUE // Without this it's pitch black if you build anywhere but space.
	newA.setup(str)
	newA.has_gravity = oldA.has_gravity

	for(var/i in 1 to length(turfs)) //Fix lighting. Praise the lord.
		var/turf/thing = turfs[i]
		thing.assign_area(newA)
		thing.change_area(oldA, newA)

	set_area_machinery(newA, newA.name, oldA.name)// Change the name and area defines of all the machinery to the correct area.
	oldA.power_check() //Simply makes the area turn the power off if you nicked an APC from it.
	return TRUE

/proc/detect_room_buildmode(turf/first, allowedAreas = AREA_SPACE)
	if(!istype(first))
		return
	var/list/turf/found = list()
	var/list/turf/pending = list(first)
	while(pending.len)
		var/turf/T = pending[1]
		pending -= T
		for (var/dir in GLOB.cardinal)
			var/turf/NT = get_step(T,dir)
			if (!isturf(NT) || (NT in found) || (NT in pending))
				continue
			// We ask ZAS to determine if its airtight.  Thats what matters anyway right?
			if(SSair.air_blocked(T, NT))
				// Okay thats the edge of the room
				if(get_area_type_buildmode(NT.loc) == AREA_SPACE && SSair.air_blocked(NT, NT))
					found += NT // So we include walls/doors not already in any area
				continue
			if (istype(NT, /turf/space))
				return //omg hull breach we all going to die here
			if (istype(NT, /turf/simulated/shuttle))
				return // Unsure why this, but was in old code. Trusting for now.
			if (NT.loc != first.loc && !(get_area_type_buildmode(NT.loc) & allowedAreas))
				// Edge of a protected area.  Lets stop here...
				continue
			if (!istype(NT, /turf/simulated))
				// Great, unsimulated... eh, just stop searching here
				continue
			// Okay, NT looks promising, lets continue the search there!
			pending += NT
		found += T
	// end while
	return found

/proc/get_area_type_buildmode(area/A)
	if(A.outdoors)
		return AREA_SPACE

	for (var/type in GLOB.BUILDABLE_AREA_TYPES)
		if ( istype(A,type) )
			return AREA_SPACE

	for (var/type in GLOB.SPECIALS)
		if ( istype(A,type) )
			return AREA_SPECIAL
	return AREA_STATION

/area/buildmode
	dynamic_lighting = FALSE
	luminosity = FALSE

#undef BUILDMODE_BASIC
#undef BUILDMODE_ADVANCED
#undef BUILDMODE_EDIT
#undef BUILDMODE_THROW
#undef BUILDMODE_ROOM
#undef BUILDMODE_LADDER
#undef BUILDMODE_CONTENTS
#undef BUILDMODE_LIGHTS
#undef BUILDMODE_AI
#undef LAST_BUILDMODE
#undef BUILDMODE_DROP

/// The builder's client, or null while they are disconnected.
/obj/effect/bmode/buildholder/proc/cl() as /client
	return GLOB.directory[cl_ckey]

/// The throw_atom this refers to (a relation view: null once that is deleted).
/obj/effect/bmode/buildholder/proc/throw_atom() as /atom/movable
	return throw_atom

/// The coordA this refers to (a relation view: null once that is deleted).
/obj/effect/bmode/buildmode/proc/coordA() as /turf
	return coordA

/// The coordB this refers to (a relation view: null once that is deleted).
/obj/effect/bmode/buildmode/proc/coordB() as /turf
	return coordB

/// The master this refers to (a relation view: null once that is deleted).
/obj/effect/bmode/proc/master() as /obj/effect/bmode/buildholder
	return master

/datum/prompt/text/buildmode_path
	timeout = 0
	recheck_on_open = TRUE
	rights = R_BUILDMODE
	var/path_var

/datum/prompt/text/buildmode_path/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/buildmode_path/normalize(given)
	return istext(given) ? given : null

/datum/prompt/choice/buildmode_path
	timeout = 0
	recheck_on_open = TRUE
	rights = R_BUILDMODE
	var/path_var

/datum/prompt/choice/buildmode_path/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/choice/buildmode_room_setting
	timeout = 0
	recheck_on_open = TRUE
	rights = R_BUILDMODE

/datum/prompt/choice/buildmode_room_setting/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/buildmode_room_name
	timeout = 0
	recheck_on_open = TRUE
	rights = R_BUILDMODE
	max_len = MAX_NAME_LEN
	name_text = TRUE

/datum/prompt/text/buildmode_room_name/recheck_extra()
	return admin_can(answerer?.client, 0) ? null : "no admin rights"

/datum/prompt/text/buildmode_room_name/normalize(given)
	return istext(given) ? strip_name_tokens(given) : null


/// Scalar variable-edit questions; reference pickers retain their existing adapter.
/datum/prompt/text/buildmode_edit
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/step

/datum/prompt/text/buildmode_edit/normalize(given)
	return istext(given) ? given : null

/datum/prompt/text/buildmode_edit/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	return null

/datum/prompt/choice/buildmode_edit
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/step

/datum/prompt/choice/buildmode_edit/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	var/static/list/locked = list("vars", "key", "ckey", "client", "firemut", "ishulk", "telekinesis", "xray", "virus", "viruses", "cuffed", "ka", "last_eaten", "urine")
	if(!isnull(value) && (step in locked) && !check_rights_for(user.client, R_DEBUG))
		return "locked variable"
	return null

/datum/prompt/number/buildmode_edit
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/edit_var

/datum/prompt/number/buildmode_edit/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	return null

/datum/prompt/number/buildmode_edit/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default || 0, INFINITY, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box


/datum/prompt/choice/buildmode_mob_reference
	title = "Value"
	question = "Enter variable value:"
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/step

/datum/prompt/choice/buildmode_mob_reference/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	if(!isnull(value))
		var/mob/picked = value
		if(!istype(picked) || QDELETED(picked))
			return "gone"
	return null

/datum/prompt/choice/buildmode_light
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE

/datum/prompt/choice/buildmode_light/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	return null

/datum/prompt/number/buildmode_light
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/light_setting

/datum/prompt/number/buildmode_light/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	return null

/datum/prompt/color/buildmode_light
	timeout = 0
	rights = R_BUILDMODE
	recheck_on_open = TRUE
	var/light_setting

/datum/prompt/color/buildmode_light/recheck_extra()
	var/obj/effect/bmode/buildmode/editor = owner
	var/mob/user = answerer
	if(!istype(editor) || QDELETED(editor) || !istype(user) || QDELETED(user))
		return "gone"
	return null

/datum/prompt/number/buildmode_light/present(mob/user)
	var/datum/tgui_input_number/prompt/box = new(user, question, title || "Number Input", default || 0, INFINITY, 0, timeout, TRUE, GLOB.tgui_always_state)
	rel_set(box, nameof(box.prompt), src)
	box.tgui_interact(user)
	return box

/datum/prompt/color/buildmode_light/normalize(given)
	return given

/datum/prompt/color/buildmode_light/present(mob/user)
	var/datum/tgui_color_picker/prompt/picker = new(user, question, title || "Pick a color", default || "#000000", timeout, TRUE, GLOB.tgui_always_state)
	rel_set(picker, nameof(picker.prompt), src)
	picker.tgui_interact(user)
	return picker
