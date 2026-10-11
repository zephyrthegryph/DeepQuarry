// Targets, the things that actually get shot!
/obj/item/target
	name = "shooting target"
	desc = "A shooting target."
	icon = 'icons/obj/objects.dmi'
	icon_state = "target_h"
	density = FALSE
	max_integrity = 1800
	var/icon/virtualIcon
	var/list/bulletholes

/obj/item/target/atom_destruction(damage_flag)
	for(var/mob/O in oviewers(src))
		if ((O.client && !( O.blinded )))
			to_chat(O, span_warning("\The [src] breaks into tiny pieces and collapses!"))
	return ..()

/obj/item/target/Moved(atom/old_loc, direction, forced = FALSE)
	. = ..()
	// After target moves, check for nearby stakes. If associated, move to target
	for(var/obj/structure/target_stake/M in view(3,src))
		if(M.density == 0 && M.pinned_target == src)
			M.forceMove(loc)

	// This may seem a little counter-intuitive but I assure you that's for a purpose.
	// Stakes are the ones that carry targets, yes, but in the stake code we set
	// a stake's density to 0 meaning it can't be pushed anymore. Instead of pushing
	// the stake now, we have to push the target.

/obj/item/target/proc/welder_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	var/obj/item/weldingtool/WT = W.get_welder()
	if(WT.remove_fuel(0, user))
		cut_overlays()
		to_chat(user, "You slice off [src]'s uneven chunks of aluminum and scorch marks.")
	return OP_OK

CAPABILITIES(/obj/item/target)
	op("unpin", hand(), when(req(PROC_REF(is_pinned))), then(PROC_REF(unpinned)))
	op("use_welder", tool(TOOL_WELDER), wait(0), costs(RES_FUEL, 0), then(PROC_REF(welder_used)))

/// The stake this target is pinned to, if one is near.
/obj/item/target/proc/pinning_stake()
	for(var/obj/structure/target_stake/T in view(3,src))
		if(T.pinned_target == src)
			return T
	return null

/// An empty hand takes a pinned target off its stake; a free target is picked up as any item.
/obj/item/target/proc/is_pinned(datum/act/op/A)
	return (!!pinning_stake()) ? null : /datum/msg/req_failed

/// Taking pinned targets off.
/obj/item/target/proc/unpinned(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/structure/target_stake/stake = pinning_stake()
	if(!stake)
		return OP_REFUSED
	stake.set_density(TRUE)
	set_density(FALSE)
	layer = OBJ_LAYER

	forceMove(user.loc)
	if(ishuman(user))
		if(!user.get_active_hand())
			user.put_in_hands(src)
			to_chat(user, "You take the target out of the stake.")
	else
		src.forceMove(get_turf(user))
		to_chat(user, "You take the target out of the stake.")

	rel_clear(stake, nameof(stake.pinned_target))
	return OP_OK

/obj/item/target/syndicate
	icon_state = "target_s"
	desc = "A shooting target that looks like a hostile agent."
	max_integrity = 2600 // i guess syndie targets are sturdier?
/obj/item/target/alien
	icon_state = "target_q"
	desc = "A shooting target with a threatening silhouette."
	max_integrity = 2350 // alium onest too kinda

/obj/item/target/bullet_act(obj/item/projectile/Proj)
	var/p_x = Proj.p_x + pick(0,0,0,0,0,-1,1) // really ugly way of coding "sometimes offset Proj.p_x!"
	var/p_y = Proj.p_y + pick(0,0,0,0,0,-1,1)
	var/decaltype = 1 // 1 - scorch, 2 - bullet

	if(istype(Proj, /obj/item/projectile/bullet))
		decaltype = 2

	virtualIcon = new(icon, icon_state)

	if( virtualIcon.GetPixel(p_x, p_y) ) // if the located pixel isn't blank (null)

		// Only rounds that land on the silhouette wear the target down.
		take_damage(Proj.damage, BRUTE, null, FALSE)
		if(QDELETED(src))
			return

		// Create a temporary object to represent the damage
		var/obj/bmark = new
		bmark.pixel_x = p_x
		bmark.pixel_y = p_y
		bmark.icon = 'icons/effects/effects.dmi'
		bmark.icon_state = "scorch"

		if(decaltype == 1)
			// Energy weapons are hot. they scorch!

			// offset correction
			bmark.pixel_x--
			bmark.pixel_y--

			if(Proj.damage >= 20 || istype(Proj, /obj/item/projectile/beam/practice))
				bmark.icon_state = "scorch"
				bmark.set_dir(pick(NORTH,SOUTH,EAST,WEST)) // random scorch design

			else
				bmark.icon_state = "light_scorch"
		else

			// Bullets are hard. They make dents!
			bmark.icon_state = "dent"

		if(Proj.damage >= 10 && length(bulletholes) <= 35) // maximum of 35 bullet holes
			if(decaltype == 2) // bullet
				if(prob(Proj.damage+30)) // bullets make holes more commonly!
					new/datum/bullethole(src, bmark.pixel_x, bmark.pixel_y) // create new bullet hole
			else // Lasers!
				if(prob(Proj.damage-10)) // lasers make holes less commonly
					new/datum/bullethole(src, bmark.pixel_x, bmark.pixel_y) // create new bullet hole

		// draw bullet holes
		for(var/datum/bullethole/B in bulletholes)

			virtualIcon.DrawBox(null, B.b1x1, B.b1y,  B.b1x2, B.b1y) // horizontal line, left to right
			virtualIcon.DrawBox(null, B.b2x, B.b2y1,  B.b2x, B.b2y2) // vertical line, top to bottom

		add_overlay(bmark) // add the decal

		icon = virtualIcon // apply bulletholes over decals

		return

	return PROJECTILE_CONTINUE // the bullet/projectile goes through the target!

// Small memory holder entity for transparent bullet holes
/datum/bullethole
	// First box
	var/b1x1 = 0
	var/b1x2 = 0
	var/b1y = 0

	// Second box
	var/b2x = 0
	var/b2y1 = 0
	var/b2y2 = 0

/datum/bullethole/New(obj/item/target/Target, pixel_x = 0, pixel_y = 0)
	if(!Target) return

	// Randomize the first box
	b1x1 = pixel_x - pick(1,1,1,1,2,2,3,3,4)
	b1x2 = pixel_x + pick(1,1,1,1,2,2,3,3,4)
	b1y = pixel_y
	if(prob(35))
		b1y += rand(-4,4)

	// Randomize the second box
	b2x = pixel_x
	if(prob(35))
		b2x += rand(-4,4)
	b2y1 = pixel_y + pick(1,1,1,1,2,2,3,3,4)
	b2y2 = pixel_y - pick(1,1,1,1,2,2,3,3,4)

	rel_add(Target, nameof(Target.bulletholes), src)

