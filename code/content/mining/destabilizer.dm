//destablizing force
/obj/item/projectile/destabilizer
	name = "destabilizing force"
	icon_state = "pulse1"
	nodamage = TRUE
	damage = 0 //We're just here to mark people. This is still a melee weapon.
	range = 6
	accuracy = INFINITY	// NO.
	var/tmp/obj/item/kinetic_crusher/hammer_synced

CAPABILITIES(/obj/item/projectile/destabilizer)
	ref_one(nameof(hammer_synced))

/obj/item/projectile/destabilizer/on_impact(atom/A)
	if(ismineralturf(A))
		var/turf/simulated/mineral/M = A
		new /obj/effect/temp_visual/kinetic_blast(M)
		M.GetDrilled(firer)
	. = ..()

/obj/item/projectile/destabilizer/on_hit(atom/target, blocked = FALSE)
	if(isliving(target))
		var/mob/living/L = target
		if(hammer_synced()?.can_mark(L))
			L.apply_body_effect(/datum/body_effect/crusher_mark, 30 SECONDS, hammer_synced(), TRUE)
	..()


/// Accessor for the hammer_synced var.
/obj/item/projectile/destabilizer/proc/hammer_synced() as /obj/item/kinetic_crusher
	return hammer_synced
