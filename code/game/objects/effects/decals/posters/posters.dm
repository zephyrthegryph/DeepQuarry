/// Returns a randomly picked poster decl of the subtype specified by the path argument. If the exact argument is true, it will return the decl from the decls_repository of the exact path specified.
/proc/get_poster_decl(path = null, exact = TRUE, forbid_types)
	if(ispath(path))
		if(exact)
			return GLOB.decls_repository.get_decl(path)
		else
			// Get the list of decals and Remove some forbidden types. These two base types don't have proper icon_states so they're illegal.
			var/list/L = GLOB.decls_repository.get_decls_of_type(path)
			L -= GLOB.decls_repository.get_decl(/datum/decl/poster/lewd)
			if(forbid_types)
				L -= GLOB.decls_repository.get_decls_of_type(forbid_types)
			return L[pick(L)]
	return null

/obj/item/poster
	name = "rolled-up poster"
	desc = "The poster comes with its own automatic adhesive mechanism, for easy pinning to any vertical surface."
	icon = 'icons/obj/contraband.dmi'
	icon_state = "rolled_poster"
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	pickup_sound = SFX_ITEMS_PICKUP_WRAPPER
	force = 0
	VAR_PROTECTED/datum/decl/poster/poster_decl = null
	VAR_PROTECTED/poster_type = /obj/structure/sign/poster

CAPABILITIES(/obj/item/poster)
	param(nameof(design_at_make), pos = 1, apply = PROC_REF(choose_design), keep = FALSE)

/// The poster design a rolled poster is made with (its constructor param): a decl or its type.
/obj/item/poster/var/tmp/design_at_make

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/poster/proc/choose_design(P)
	if(ispath(poster_decl))
		poster_decl = get_poster_decl(poster_decl, TRUE, null)
	else if(istype(P, /datum/decl/poster))
		poster_decl = P
	else if(ispath(P))
		poster_decl = get_poster_decl(P, TRUE, null)
	else
		poster_decl = get_poster_decl(/datum/decl/poster, FALSE, /datum/decl/poster/lewd)
	name += " - [poster_decl.name]"

/// Get the current poster_decl
/obj/item/poster/proc/get_decl()
	RETURN_TYPE(/datum/decl/poster)
	SHOULD_NOT_OVERRIDE(TRUE)
	return poster_decl

//Places the poster on a wall
/obj/item/poster/afterattack(atom/A, mob/user, adjacent, clickparams)
	if(!adjacent)
		return FALSE

	//must place on a wall and user must not be inside a closet/mecha/whatever
	var/turf/W = A
	if(!iswall(W) || !isturf(user.loc))
		to_chat(user, span_warning("You can't place this here!"))
		return FALSE

	var/placement_dir = get_dir(user, W)
	if(!(placement_dir in GLOB.cardinal))
		to_chat(user, span_warning("You must stand directly in front of the wall you wish to place that on."))
		return FALSE

	//just check if there is a poster on or adjacent to the wall
	var/stuff_on_wall = 0
	if(locate_on(W, /obj/structure/sign/poster))
		stuff_on_wall = 1

	//crude, but will cover most cases. We could do stuff like check pixel_x/y but it's not really worth it.
	for (var/dir in GLOB.cardinal)
		var/turf/T = get_step(W, dir)
		if (locate_on(T, /obj/structure/sign/poster))
			stuff_on_wall = 1
			break

	if(stuff_on_wall)
		to_chat(user, span_notice("There is already a poster there!"))
		return FALSE

	to_chat(user, span_notice("You start placing the poster on the wall...")) //Looks like it's uncluttered enough. Place the poster.

	new poster_type(user.loc, get_dir(user, W), src)

	task_timed(user, 17, target = src, receiver = src, on_done = PROC_REF(afterattack_timed_done), done_args = list(user))
	return TRUE

/obj/item/poster/proc/afterattack_timed_done(mob/user)
	to_chat(user, span_notice("You place the poster!"))
	consume(src, user)
	return TRUE

//############################## THE ACTUAL DECALS ###########################

/obj/structure/sign/poster
	name = "poster"
	desc = "A large piece of space-resistant printed paper. "
	icon = 'icons/obj/contraband_vr.dmi'
	icon_state = "poster"
	anchored = TRUE
	VAR_PROTECTED/datum/decl/poster/poster_decl = null // Assigned by Initialize() to a random poster decl. If this is mapset to a path, it will be used to locate the decl specified by that path.
	VAR_PROTECTED/roll_type = /obj/item/poster
	VAR_PRIVATE/ruined = FALSE

/// The rolled poster a hung one is made from (its constructor param).
/obj/structure/sign/poster/var/tmp/obj/item/poster/hung_from

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm). The poster takes its design and hangs on the wall it faces.
/obj/structure/sign/poster/proc/hang(obj/item/poster/P)
	if(ispath(poster_decl))
		poster_decl = get_poster_decl(poster_decl, TRUE, null)
	else if(istype(P))
		poster_decl = P.get_decl()
		roll_type = P.type
	else if(ispath(P))
		poster_decl = get_poster_decl(P, TRUE, null)
	else
		poster_decl = get_poster_decl(/datum/decl/poster, FALSE, /datum/decl/poster/lewd)

	name = "[initial(name)] - [poster_decl.name]"
	desc = "[initial(desc)] [poster_decl.desc]"
	if(poster_decl.icon_override)
		icon = poster_decl.icon_override
	icon_state = poster_decl.icon_state

	switch (dir)
		if (NORTH)
			pixel_x = 0
			pixel_y = 32
		if (SOUTH)
			pixel_x = 0
			pixel_y = -32
		if (EAST)
			pixel_x = 32
			pixel_y = 0
		if (WEST)
			pixel_x = -32
			pixel_y = 0

	flick("poster_being_set", src) // If you don't see this animation, check that the decl/poster's icon_override dmi file has the icon states for posters being set.

CAPABILITIES(/obj/structure/sign/poster)
	op("use_wirecutter", tool(TOOL_WIRECUTTER), wait(0), then(PROC_REF(wirecutter_used)))
	param(nameof(dir), pos = 1)
	param(nameof(hung_from), pos = 2, apply = PROC_REF(hang), keep = FALSE)

/obj/structure/sign/poster/proc/wirecutter_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/tool = A.held
	playsound(src, tool.usesound, 100, 1)
	if(ruined)
		to_chat(user, span_notice("You remove the remnants of the poster."))
		consume(src, user)
	else
		to_chat(user, span_notice("You carefully remove the poster from the wall."))
		roll_and_drop(get_turf(user), user)
	return OP_OK

DECLARE_INTERACTIONS(/obj/structure/sign/poster, INTERACT_HAND_UNGATED(null, PROC_REF(interaction_hand)))

/// Old attack_hand.
/obj/structure/sign/poster/proc/interaction_hand(mob/user, obj/item/held, datum/interaction/interaction)
	if(ruined)
		return TRUE

	open_request(src, /datum/prompt/yes_no/rip_poster, PROC_REF(rip_answered), answerer = user)

/// Re-checked on the answer: still next to it, and it isn't ripped already.
/datum/prompt/yes_no/rip_poster
	title = "You think..."
	question = "Do I want to rip the poster from the wall?"
	ask_flags = ASK_ADJACENT | ASK_CAPABLE
	timeout = 0

/datum/prompt/yes_no/rip_poster/recheck_extra()
	var/obj/structure/sign/poster/P = owner
	return P.is_ruined() ? "already ripped" : null

/obj/structure/sign/poster/proc/rip_answered(datum/act/request/A)
	if(!A.answer || !A.answer.value)
		return
	var/mob/user = A.request.answerer
	act_message(user, src, others = span_warning("%U% rips %T% in a single, decisive motion!"))
	play_sfx(src, SFX_ITEMS_POSTER_RIPPED)
	ruined = TRUE
	icon_state = "poster_ripped"
	name = "ripped poster"
	desc = "You can't make out anything from the poster's original print. It's ruined."
	add_fingerprint(user)

/// Consumes the wall poster before returning its matching rolled item.
/obj/structure/sign/poster/proc/roll_and_drop(turf/newloc, mob/user)
	SHOULD_NOT_OVERRIDE(TRUE)
	var/product_type = roll_type
	var/datum/decl/poster/product_decl = poster_decl
	if(!consume(src, user))
		return null
	var/obj/item/poster/P = new product_type(newloc, product_decl)
	P.forceMove(newloc)
	return P

/// Whether the poster has been ripped.
/obj/structure/sign/poster/proc/is_ruined()
	return ruined
