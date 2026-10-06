/obj/item/projectile/spell_projectile
	resistance_flags = BOMB_PROOF
	name = "spell"
	icon = 'icons/obj/projectiles.dmi'

	nodamage = 1 //Most of the time, anyways

	var/tmp/datum/spell/targeted/projectile/carried

	penetrating = 0
	range = 10 //set by the duration of the spell

	var/proj_trail = 0 //if it leaves a trail
	var/proj_trail_lifespan = 0 //deciseconds
	var/proj_trail_icon = 'icons/obj/wizard.dmi'
	var/proj_trail_icon_state = "trail"
	var/list/trails

CAPABILITIES(/obj/item/projectile/spell_projectile)
	owns_many(nameof(trails))


/obj/item/projectile/spell_projectile/before_move()
	if(proj_trail && src && src.loc) //pretty trails
		var/obj/effect/overlay/trail = new /obj/effect/overlay(src.loc)
		rel_add(src, nameof(trails), trail)
		trail.icon = proj_trail_icon
		trail.icon_state = proj_trail_icon_state
		trail.set_density(FALSE)
		after(src, proj_trail_lifespan, PROC_REF(expire_trail), with = list(trail)) // our Destroy() takes the trails with us

/obj/item/projectile/spell_projectile/proc/expire_trail(obj/effect/trail)
	rel_remove(src, nameof(trails), trail) // disposes of it

/obj/item/projectile/spell_projectile/proc/prox_cast(list/targets)
	if(loc)
		carried().prox_cast(targets, src)
		spent(src)
	return

/obj/item/projectile/spell_projectile/Bump(atom/A)
	if(loc && carried())
		prox_cast(carried().choose_prox_targets(user = carried().holder(), spell_holder = src))
	return 1

/obj/item/projectile/spell_projectile/on_impact()
	if(loc && carried())
		prox_cast(carried().choose_prox_targets(user = carried().holder(), spell_holder = src))
	return 1

/obj/item/projectile/spell_projectile/seeking
	name = "seeking spell"

/// the carried this refers to (a relation view: null once it is deleted).
/obj/item/projectile/spell_projectile/proc/carried() as /datum/spell/targeted/projectile
	return carried
