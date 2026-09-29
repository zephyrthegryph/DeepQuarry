/obj/structure/closet/secure_closet
	name = "secure locker"
	desc = "It's an immobile card-locked storage unit."
	icon = 'icons/obj/closet.dmi'
	icon_state = "secure1"
	density = TRUE
	opened = 0
	var/locked = 1
	var/broken = 0
	var/large = 1
	wall_mounted = 0 //never solid (You can always pass over it)
	max_integrity = 200
	anchored = 1 // Making them properly IMMOBILE. Like the Desc says? Yeah...

	closet_appearance = /datum/decl/closet_appearance/secure_closet

/obj/structure/closet/secure_closet/can_open()
	if(locked)
		return 0
	return ..()

DAMAGE_REACTION(/obj/structure/closet/secure_closet, DAMAGE_EMP, PROC_REF(secure_closet_emp))
/// An EMP may toggle the lock, pop the closet or scramble its access.
/obj/structure/closet/secure_closet/proc/secure_closet_emp(datum/damage_packet/packet)
	var/severity = packet.severity
	if(!broken)
		if(prob(50/severity))
			locked = !locked
			update_icon()
		if(prob(20/severity) && !opened)
			if(!locked)
				open()
			else
				req_access = list()
				req_access += pick(SSaccess.get_all_station_access())

/obj/structure/closet/secure_closet/proc/togglelock(mob/user as mob)
	if(opened)
		to_chat(user, span_notice("Close the locker first."))
		return
	if(broken)
		to_chat(user, span_warning("The locker appears to be broken."))
		return
	if(user.loc == src)
		to_chat(user, span_notice("You can't reach the lock from inside."))
		return
	if(allowed(user))
		locked = !locked
		play_sfx(src, SFX_MACHINES_CLICK, 0.3, extrarange = -3)
		for(var/mob/O in viewers(user, 3))
			if((O.client && !( O.blinded )))
				to_chat(O, span_notice("The locker has been [locked ? null : "un"]locked by [user]."))
		update_icon()
	else
		to_chat(user, span_notice("Access Denied"))

/// Overrides closet's interaction_item(): secure closets check grab size and can be sliced open.
/obj/structure/closet/secure_closet/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(opened)
		if(istype(W, /obj/item/storage/laundry_basket))
			return ..()
		if(istype(W, /obj/item/grab))
			var/obj/item/grab/G = W
			if(large)
				MouseDrop_T(G?.grab_target(), user)	//act like they were dragged onto the closet
			else
				to_chat(user, span_notice("The locker is too small to stuff [G?.grab_target()] into!"))
		if(isrobot(user))
			return TRUE
		if(W.loc != user) // This should stop mounted modules ending up outside the module.
			return TRUE
		user.drop_item()
		if(W)
			W.forceMove(loc)
	else if(istype(W, /obj/item/melee/energy/blade))
		if(emag_act(INFINITY, user, span_danger("The locker has been sliced open by [user] with \an [W]!"), span_danger("You hear metal being sliced and sparks flying.")))
			fx_sparks(loc, 5, FALSE)
			play_sfx(src, SFX_WEAPONS_BLADE1)
			play_sfx(src, SFX_SPARKS)
	else if(istype(W,/obj/item/packageWrap))
		return ..()
	else
		togglelock(user)
	return TRUE

/obj/structure/closet/secure_closet/emag_act(remaining_charges, mob/user, emag_source, visual_feedback = "", audible_feedback = "")
	if(!broken)
		broken = 1
		locked = 0
		desc = "It appears to be broken."

		if(visual_feedback)
			visible_message(visual_feedback, audible_feedback)
		else if(user && emag_source)
			act_message(src, user, others = span_warning("%U% has been broken by %T% with \an [emag_source]!"), blind = "You hear a faint electrical spark.")
		else
			visible_message(span_warning("\The [src] sparks and breaks open!"), "You hear a faint electrical spark.")
		update_icon()
		return 1

// Secure closet's Use fully replaces closet's (the original override never called ..()
// into it either), so it swaps out closet_hand for its own interaction, while still
// inheriting closet_item (whose effect it overrides above, polymorphically).
/obj/structure/closet/secure_closet/declare_interactions(list/into)
	into += list(
		/datum/interaction/entry_hand/secure_closet_hand,
		/datum/interaction/entry_alt/secure_closet_alt,
	)
	var/static/list/lock_spec = INTERACT_VERB("Toggle Lock", PROC_REF(secure_closet_verb_togglelock_effect))
	into += dq_interaction_from_spec(/obj/structure/closet/secure_closet, lock_spec)
	..()
	into -= /datum/interaction/entry_hand/closet_hand

/// Old attack_hand: toggle the lock, or open/close if unlocked.
/datum/interaction/entry_hand/secure_closet_hand
	id = "secure_closet_hand"
	name = "Use"
	effect = /obj/structure/closet/secure_closet/proc/interaction_secure_hand

/obj/structure/closet/secure_closet/proc/interaction_secure_hand(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	if(locked)
		togglelock(user)
	else
		toggle(user)
	return TRUE

/// Old click_alt: toggle the lock.
/datum/interaction/entry_alt/secure_closet_alt
	id = "secure_closet_alt"
	name = "Toggle lock"
	effect = /obj/structure/closet/secure_closet/proc/interaction_alt

/obj/structure/closet/secure_closet/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	secure_closet_verb_togglelock_effect(user)
	return TRUE

/obj/structure/closet/secure_closet/proc/secure_closet_verb_togglelock_effect(mob/user, obj/item/held, datum/interaction/interaction)

	if(!user.canmove || user.stat || user.restrained() || !Adjacent(user)) // Don't use it if you're not able to! Checks for stuns, ghost and restrain
		return

	if(ishuman(user) || isrobot(user))
		add_fingerprint(user)
		togglelock(user)
	else
		to_chat(user, span_warning("This mob type can't use this verb."))

/obj/structure/closet/secure_closet/update_icon()
	if(opened)
		icon_state = "open"
	else
		if(broken)
			icon_state = "closed_emagged[sealed ? "_welded" : ""]"
		else
			if(locked)
				icon_state = "closed_locked[sealed ? "_welded" : ""]"
			else
				icon_state = "closed_unlocked[sealed ? "_welded" : ""]"

/obj/structure/closet/secure_closet/req_breakout()
	if(!opened && locked) return 1
	return ..() //It's a secure closet, but isn't locked.

/obj/structure/closet/secure_closet/break_open()
	desc += " It appears to be broken."
	broken = 1
	locked = 0
	..()

/obj/structure/closet/secure_closet/mind
	name = "mind secured locker"
	var/owner_handle
	var/self_del = 1
	anchored = 0

/obj/structure/closet/secure_closet/mind/Initialize(mapload, datum/mind/mind_target, del_self = 1)
	. = ..()
	self_del = del_self
	if(mind_target)
		owner_handle = om_handle(mind_target)
		name = "Owned by [owner_ref().name]"
		if(owner_ref().current)
			var/icon/I = get_flat_icon(owner_ref().current, dir=SOUTH, no_anim=TRUE)
			var/image/IM = image(I, pixel_x = (32 - I.Width()))
			add_overlay(IM)
			qdel(I)

/obj/structure/closet/secure_closet/mind/allowed(mob/user)
	if(user.mind == owner_ref())
		return TRUE
	else
		return FALSE

/obj/structure/closet/secure_closet/mind/open()
	.=..()
	if(self_del)
		qdel(src)

/obj/structure/closet/secure_closet/mind/LateInitialize()
	if(ispath(closet_appearance))
		closet_appearance = GLOB.closet_appearances[closet_appearance]
		if(istype(closet_appearance))
			icon = closet_appearance.icon
			color = null
	update_icon()

/// LC-refs: owner -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/structure/closet/secure_closet/mind/proc/owner_ref() as /datum/mind
	return om_resolve(owner_handle)
