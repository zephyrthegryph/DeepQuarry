#define COGBAR_ANIMATION_TIME (0.5 SECONDS)

/**
 * ### Cogbar
 * Represents that the user is busy doing something.
 */
/datum/cogbar
	parent_type = /datum/cog_view
	/// Who's doing the thing
	var/mob/user
	/// The user client
	var/client/user_client
	/// The visible element to other players
	var/obj/effect/overlay/vis/cog
	/// The blank image that overlaps the cog - hides it from the source user
	var/image/blank
	/// The offset of the icon
	var/offset_y
	/// Icon path of the cog
	var/cogicon
	/// The icon state
	var/cogiconstate

/datum/cogbar/New(mob/user, cogicon, cogiconstate)
	rel_set(src, nameof(user), user)
	rel_set(src, nameof(user_client), user.client)
	src.cogicon = cogicon
	src.cogiconstate = cogiconstate
	var/list/icon_offsets = user.get_oversized_icon_offsets()
	offset_y = icon_offsets["y"]
	if(isnull(cogicon))
		stack_trace("/datum/cogbar was created with a null icon.")
		spent(src, user)
		return
	if(isnull(cogiconstate))
		stack_trace("/datum/cogbar was created with a null icon state.")
		spent(src, user)
		return

	add_cog_to_user()

	observe(user, /datum/notice/qdeleting, src, then(PROC_REF(on_user_delete)))


/// Phase 1: take the overlay off the user and the blank image (owned, dropped in phase 4) off the client.
/datum/cogbar/lifecycle_unbind()
	var/mob/user = user()
	if(user)
		SSvis_overlays.remove_vis_overlay(user, user.managed_vis_overlays)
		user_client()?.images -= blank

/// Adds the cog to the user, visible by other players
/datum/cogbar/proc/add_cog_to_user()
	var/obj/effect/overlay/vis/cog = SSvis_overlays.add_vis_overlay(user(),
		icon = cogicon,
		iconstate = cogiconstate,
		plane = ABOVE_PLANE,
		add_appearance_flags = APPEARANCE_UI_IGNORE_ALPHA,
		unique = TRUE,
		alpha = 0,
	)
	rel_set(src, nameof(cog), cog)
	cog.pixel_y = ICON_SIZE_Y + offset_y
	animate(cog, alpha = user().alpha, time = COGBAR_ANIMATION_TIME)

	if(isnull(user_client()))
		return

	blank = image('icons/system/blank_32x32.dmi', cog, "nothing")
	blank.plane = ABOVE_PLANE //Change to SET_PLANE_EXPLICIT(blank, HIGH_GAME_PLANE, user)
	blank.appearance_flags = APPEARANCE_UI_IGNORE_ALPHA
	blank.override = TRUE

	user_client().images += blank

/// Removes the cog from the user
/datum/cogbar/remove()
	if(isnull(cog()))
		spent(src)
		return

	animate(cog(), alpha = 0, time = COGBAR_ANIMATION_TIME)

	om_qdel_after(src, COGBAR_ANIMATION_TIME)

/// When the user is deleted, remove the cog
/datum/cogbar/proc/on_user_delete(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)

	ended_with(src)

#undef COGBAR_ANIMATION_TIME

/// The busy mob (a relation view).
/datum/cogbar/proc/user() as /mob
	return user

/// The busy mob's client (a relation view).
/datum/cogbar/proc/user_client() as /client
	return user_client

/// The cog vis overlay (SSvis_overlays owns it) (a relation view).
/datum/cogbar/proc/cog() as /obj/effect/overlay/vis
	return cog
