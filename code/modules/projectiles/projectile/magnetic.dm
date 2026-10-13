// Rod for railguns. Slightly less nasty than the sniper round.
/obj/item/projectile/bullet/magnetic
	name = "rod"
	icon = 'icons/obj/projectiles.dmi' //Ywedit, uses default icon path not _yw
	icon_state = "rod"
	fire_sound = SFX_WEAPONS_RAILGUN
	damage = 65
	stun = 0 // Guaranteed stuns from a gun bad.
	weaken = 0 // Guaranteed stuns from a gun bad.
	penetrating = 5
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic)
	configure(item_combat(armor_penetration = 70))

/obj/item/projectile/bullet/magnetic/slug
	name = "slug"
	icon_state = "gauss_silenced"
	damage = 75
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/slug)
	configure(item_combat(armor_penetration = 90))

/obj/item/projectile/bullet/magnetic/flechette
	name = "flechette"
	icon_state = "flechette"
	fire_sound = SFX_WEAPONS_RAPIDSLICE
	damage = 20
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/flechette)
	configure(item_combat(armor_penetration = 100))

/obj/item/projectile/bullet/magnetic/flechette/small
	name = "small flechette"
	icon_state = "flechette"
	fire_sound = SFX_WEAPONS_RAPIDSLICE
	damage = 12
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/flechette/small)
	configure(item_combat(armor_penetration = 100))

/obj/item/projectile/bullet/magnetic/flechette/hunting
	name = "shredder slug"
	mob_bonus_damage = 40
	hud_state = "alloy_spike"

/obj/item/projectile/bullet/magnetic/heated
	name = "slug"
	icon_state = "gauss"
	weaken = 0
	stun = 0
	damage = 30
	injury_kind = INJURY_BLUNT
	injury_kinds = alist(INJURY_BURN = 1/3, INJURY_BLUNT = 2/3)
	embed_chance = 0
	penetrating = 1
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/heated)
	configure(item_combat(armor_penetration = 40))

/obj/item/projectile/bullet/magnetic/heated/weak
	icon_state = "gauss_silenced"
	damage = 15
	agony = 5
	embed_chance = 0
	penetrating = 0
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/heated/weak)
	configure(item_combat(armor_penetration = 30))

/obj/item/projectile/bullet/magnetic/fuelrod
	name = "fuel rod"
	icon_state = "fuel-deuterium"
	damage = 30
	stun = 1
	weaken = 0
	agony = 30
	incendiary = 1
	flammability = 0 //Deuterium and Tritium are both held in water, but the object moving so quickly will ignite the target.
	penetrating = 2
	embed_chance = 0
	range = 20
	hud_state = "rocket_he"

	var/searing = 0 //Does this fuelrod ignore shields?
	var/detonate_travel = 0 //Will this fuelrod explode when it reaches maximum distance?
	var/detonate_mob = 0 //Will this fuelrod explode when it hits a mob?
	var/energetic_impact = 0 //Does this fuelrod cause a bright flash on impact with a mob?

CAPABILITIES(/obj/item/projectile/bullet/magnetic/fuelrod)
	configure(item_combat(armor_penetration = 40))

/obj/item/projectile/bullet/magnetic/fuelrod/on_hit(atom/target, blocked = 0, def_zone = null) //Future-proofing. Special effects for impact.
	if(isliving(target))
		var/mob/living/V = target
		if(detonate_mob)
			if(V.loc)
				explosion(V.loc, -1, -1, 2, 3)

		if(energetic_impact)
			var/eye_coverage = 0
			for(var/mob/living/carbon/M in viewers(world.view, get_turf(src)))
				eye_coverage = 0
				if(iscarbon(M))
					eye_coverage = M.eyecheck()
				if(eye_coverage < 2)
					M.flash_eyes()
					M.status_at_least(STAT_STUNNED, 2)
					M.status_at_least(STAT_WEAKENED, 10)

		if(searing)
			if(blocked)
				blocked = 0

	return ..(target, blocked, def_zone)

/obj/item/projectile/bullet/magnetic/fuelrod/on_impact(atom/A) //Future-proofing, again. In the event new fuel rods are introduced, and have special effects for when they stop flying.
	if(src.loc)
		if(detonate_travel && detonate_mob)
			visible_message(span_warning("\The [src] shatters in a violent explosion!"))
			explosion(src.loc, 1, 1, 3, 4)
		else if(detonate_travel)
			visible_message(span_warning("\The [src] explodes in a shower of embers!"))
			explosion(src.loc, -1, 1, 2, 3)
	..(A)

/obj/item/projectile/bullet/magnetic/fuelrod/tritium
	icon_state = "fuel-tritium"
	damage = 40
	flammability = -1
	penetrating = 3
	hud_state = "rocket_ap"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/fuelrod/tritium)
	configure(item_combat(armor_penetration = 50))

/obj/item/projectile/bullet/magnetic/fuelrod/phoron
	name = "blazing fuel rod"
	icon_state = "fuel-phoron"
	damage = 35
	incendiary = 2
	flammability = 2
	penetrating = 5
	irradiate = 20
	detonate_mob = 1
	hud_state = "rocket_fire"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/fuelrod/phoron)
	configure(item_combat(armor_penetration = 60))

/obj/item/projectile/bullet/magnetic/fuelrod/supermatter
	name = "painfully incandescent fuel rod"
	icon_state = "fuel-supermatter"
	damage = 15
	incendiary = 2
	flammability = 4
	weaken = 2
	penetrating = 100 //Theoretically, this shouldn't stop flying for a while, unless someone lines it up with a wall or fires it into a mountain.
	irradiate = 120
	range = 75
	searing = 1
	detonate_travel = 1
	detonate_mob = 1
	energetic_impact = 1
	hud_state = "rocket_thermobaric"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/fuelrod/supermatter)
	configure(item_combat(armor_penetration = 100))

/obj/item/projectile/bullet/magnetic/fuelrod/supermatter/on_hit(atom/target, blocked = 0, def_zone = null) //You cannot touch the supermatter without disentigrating. Assumedly, this is true for condensed rods of it flying at relativistic speeds.
	if(istype(target,/turf/simulated/wall) || isliving(target))
		target.visible_message(span_danger("The [src] burns a perfect hole through \the [target] with a blinding flash!"))
		play_sfx(target, SFX_EFFECTS_TELEPORT)
	return ..(target, blocked, def_zone)

/obj/item/projectile/bullet/magnetic/fuelrod/supermatter/check_penetrate()
	return 1

/obj/item/projectile/bullet/magnetic/bore
	name = "phorogenic blast"
	icon_state = "purpleemitter"
	damage = 20
	incendiary = 1
	penetrating = 0
	irradiate = 20
	range = 6
	hud_state = "plasma_rifle_blast"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/bore)
	configure(item_combat(armor_penetration = 20))
	param(nameof(range_mod), pos = 1, apply = PROC_REF(extend_range))

/// Extra range the gun gives the bore (its constructor param).
/obj/item/projectile/bullet/magnetic/bore/var/range_mod = 0

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/projectile/bullet/magnetic/bore/proc/extend_range(extra)
	range += extra

/obj/item/projectile/bullet/magnetic/bore/get_structure_damage()
	return damage * 3 //made for boring holes

/obj/item/projectile/bullet/magnetic/bore/Bump(atom/A, forced=0)
	if(ismineralturf(A))
		var/turf/simulated/mineral/MI = A
		forceMove(get_turf(A)) // Careful.
		rel_add(src, nameof(permutated), A)
		MI.GetDrilled(TRUE)
		return 0
	else if(istype(A, /turf/simulated/wall) || istype(A, /turf/simulated/shuttle/wall))	// Cause a loud, but relatively minor explosion on the wall it hits.
		explosion(A, -1, -1, 1, 3)
		return ..()
	else
		..()


// === merged from magnetic_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/projectile/bullet/magnetic/flechette/rapid
	name = "rapid flechette"
	icon_state = "flechette"
	fire_sound = SFX_WEAPONS_RAPIDSLICE
	damage = 15
	hud_state = "alloy_spike"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/flechette/rapid)
	configure(item_combat(armor_penetration = 60))

/obj/item/projectile/bullet/magnetic/fuelrod/blitz
	name = "blitz rod"
	icon = 'icons/obj/projectiles_ch.dmi'
	icon_state = "fuel-blitz"
	damage = 900
	accuracy = 200
	incendiary = 20
	flammability = 4
	weaken = 40
	penetrating = 1
	irradiate = 120
	range = 75
	searing = 1
	detonate_travel = 1
	detonate_mob = 1
	energetic_impact = 1
	hud_state = "rocket_thermobaric"

CAPABILITIES(/obj/item/projectile/bullet/magnetic/fuelrod/blitz)
	configure(item_combat(armor_penetration = 100))

/obj/item/projectile/bullet/magnetic/fuelrod/blitz/on_impact(atom/A)
	if(isturf(loc))
		explosion(loc, 3, 4, 5, 10)
	..(A)

/obj/item/projectile/bullet/magnetic/fuelrod/blitz/on_hit(atom/target, blocked = 0, def_zone)
	var/mob/living/M = target
	if(istype(M) && M.get_endurance() <= 200)
		M.dust()
	if(isturf(loc))
		explosion(loc, 3, 4, 5, 10)
	visible_message(span_warning("\The [src] impacts energetically with its target and shatters in a violent explosion!"))
	..(target, blocked, def_zone)
