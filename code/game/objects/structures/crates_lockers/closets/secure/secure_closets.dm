/obj/structure/closet/secure_closet
	name = "secure locker"
	desc = "It's an immobile card-locked storage unit."
	icon = 'icons/obj/closet.dmi'
	icon_state = "secure1"
	density = TRUE
	opened = 0
	/// Whether it starts locked (a map says `locked = 0` for one that does not). The lock itself is the lock() capability's key: read it with lock_locked().
	var/locked = 1
	var/broken = 0
	var/large = 1
	wall_mounted = 0 //never solid (You can always pass over it)
	max_integrity = 200
	anchored = 1 // Making them properly IMMOBILE. Like the Desc says? Yeah...

	closet_appearance = /datum/decl/closet_appearance/secure_closet

TRACKED(/obj/structure/closet/secure_closet, broken)

MSG_DEF_SELF(secure_closet/close_first, "Close the locker first.")
MSG_DEF_SELF(secure_closet/broken, "The locker appears to be broken.")
MSG_DEF_SELF(secure_closet/inside, "You can't reach the lock from inside.")

// A secure locker is a closet with an ID lock (the library's lock(): a card in hand, an alt-click, the "Toggle Lock" entry, and the hand of somebody whose own
// ID has the access) and a lock that can be broken for good (an emag, a blade, a break-out): a broken lock stays open. The hand opens a locker that is unlocked,
// and works the lock of one that is locked; only a shut locker has a lock to reach, and not from inside.
CAPABILITIES(/obj/structure/closet/secure_closet)
	lock(starts_locked = nameof(locked))
	extend(CAP_LOCK, needs(req_is(nameof(opened), FALSE, because = MSG(secure_closet/close_first)), req_is(nameof(broken), FALSE, because = MSG(secure_closet/broken)), req(PROC_REF(actor_outside), because = MSG(secure_closet/inside))), plays(SFX_MACHINES_CLICK))
	extend("lock.toggle_worn", binds(menu()), label("Toggle Lock"))
	extend("door", when(cond_not(LOCK_LOCKED)), priority(above("lock.toggle_worn")))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	extend("emag.use", needs(req_is(nameof(broken), FALSE, because = MSG(emag/already))))
	extend("emag.subvert", needs(req_is(nameof(broken), FALSE, because = MSG(emag/already))))
	op("slice", item(/obj/item/melee/energy/blade), label("Slice open"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART), then(PROC_REF(blade_sliced)))
	op("lock_with_item", item(/obj/item), label("Toggle Lock"), when(cond_not(nameof(opened))), when(req_credential_worn(null)), priority(OP_PRIORITY_DEFAULT + 1),
		needs(req_is(nameof(broken), FALSE, because = MSG(secure_closet/broken)), req(PROC_REF(actor_outside), because = MSG(secure_closet/inside))), toggles(LOCK_LOCKED), says(PROC_REF(lock_toggled_message)), plays(SFX_MACHINES_CLICK))
	on_change(LOCK_LOCKED, ANY, then(PROC_REF(lock_changed)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(secure_closet_emp)))

/// Whoever works the lock is not shut in with it.
/obj/structure/closet/secure_closet/proc/actor_outside(datum/act/op/A)
	return A.actor?.loc != src // ALLOW(reads): where the one at the lock is, read when the entry is offered and again at the click

/// A locked or unlocked locker is drawn again.
/obj/structure/closet/secure_closet/proc/lock_changed(datum/act/A)
	update_icon()

/// A locked locker is shut for good until unlocked: it opens only unlocked.
/obj/structure/closet/secure_closet/can_open()
	if(lock_locked(src))
		return 0
	return ..()

/// Locks or unlocks it outright (an EMP, a code, a break-out): the lock's key is the one state there is.
/obj/structure/closet/proc/force_lock(on)
	return key_set(src, LOCK_LOCKED, !!on)

/// An EMP may toggle the lock, pop the closet or scramble its access.
/obj/structure/closet/secure_closet/proc/secure_closet_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	if(!broken)
		if(prob(50/severity))
			force_lock(!lock_locked(src))
			update_icon()
		if(prob(20/severity) && !opened)
			if(!lock_locked(src))
				open()
			else
				req_access = list()
				req_access += pick(SSaccess.get_all_station_access())

/// An energy blade slices the lock of a shut locker open.
/obj/structure/closet/secure_closet/proc/blade_sliced(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(break_lock(user, null, span_danger("The locker has been sliced open by [user] with \an [W]!"), span_danger("You hear metal being sliced and sparks flying.")))
		fx_sparks(loc, 5, FALSE)
		play_sfx(src, SFX_WEAPONS_BLADE1)
		play_sfx(src, SFX_SPARKS)
	return OP_OK

/// An emag breaks the lock.
/obj/structure/closet/secure_closet/proc/on_emag(datum/act/op/A)
	break_lock(A.actor, A.held)
	return OP_OK

/// A locker too small to stuff a person into (large = 0) refuses a grab.
/obj/structure/closet/secure_closet/grab_fits(datum/act/op/A)
	return large

/// Breaks the lock open (an emag, or a blade slicing it). Returns 1 if it was still intact.
/obj/structure/closet/secure_closet/proc/break_lock(mob/user, obj/item/emag_source, visual_feedback, audible_feedback)
	if(!broken)
		set_broken(TRUE)
		force_lock(FALSE)
		desc = "It appears to be broken."

		if(visual_feedback)
			visible_message(visual_feedback, audible_feedback)
		else if(user && emag_source)
			act_message(src, user, others = span_warning("%U% has been broken by %T% with \an [emag_source]!"), blind = "You hear a faint electrical spark.")
		else
			visible_message(span_warning("\The [src] sparks and breaks open!"), "You hear a faint electrical spark.")
		update_icon()
		return 1

/obj/structure/closet/secure_closet/proc/appearance_lock_state()
	if(broken)
		return "emagged"
	return lock_locked(src) ? "locked" : "unlocked"

APPEARANCE_TEMPLATE(/obj/structure/closet/secure_closet, "closed_{appearance_lock_state}{appearance_sealed?_welded:}")

/obj/structure/closet/secure_closet/req_breakout()
	if(!opened && lock_locked(src)) return 1
	return ..() //It's a secure closet, but isn't locked.

/obj/structure/closet/secure_closet/break_open()
	desc += " It appears to be broken."
	set_broken(TRUE)
	force_lock(FALSE)
	..()

/obj/structure/closet/secure_closet/mind
	name = "mind secured locker"
	var/datum/mind/owner
	var/self_del = 1
	anchored = 0

// Only the mind it was made for works the lock.
CAPABILITIES(/obj/structure/closet/secure_closet/mind)
	extend(CAP_LOCK, needs(req(PROC_REF(owner_present), because = MSG(lock/denied))))
	extend("lock_with_item", needs(req(PROC_REF(owner_present), because = MSG(lock/denied))))
	param(nameof(owner), pos = 1)
	param(nameof(self_del), pos = 2)

/obj/structure/closet/secure_closet/mind/proc/owner_present(datum/act/op/A)
	return allowed(A.actor)

// ALLOW(init/INSTANCE_STATE): an owned closet is named for its owner and shows their picture
/obj/structure/closet/secure_closet/mind/Initialize(mapload)
	. = ..()
	if(owner_ref())
		name = "Owned by [owner_ref().name]"
		if(owner_ref().current)
			var/icon/I = get_flat_icon(owner_ref().current, dir=SOUTH, no_anim=TRUE)
			var/image/IM = image(I, pixel_x = (32 - I.Width()))
			add_overlay(IM)
			spent(I)

/obj/structure/closet/secure_closet/mind/allowed(mob/user)
	if(user.mind == owner_ref()) // ALLOW(reads): whose mind it is is read at the click; the locker is made for one mind and never changes it
		return TRUE
	else
		return FALSE

/obj/structure/closet/secure_closet/mind/open()
	.=..()
	if(self_del)
		spent(src)

/// A mind's locker takes nothing in: it only resolves its look.
/obj/structure/closet/secure_closet/mind/closet_after_init(datum/act/timer/A)
	if(ispath(closet_appearance))
		closet_appearance = GLOB.closet_appearances[closet_appearance]
		if(istype(closet_appearance))
			icon = closet_appearance.icon
			color = null
	update_icon()

/// Relation view: owner (reads null once it is gone).
/obj/structure/closet/secure_closet/mind/proc/owner_ref() as /datum/mind
	return owner // ALLOW(reads): the owner is set once when the locker is made
