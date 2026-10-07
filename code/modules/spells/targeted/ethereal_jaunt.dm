/datum/spell/targeted/ethereal_jaunt
	name = "Ethereal Jaunt"
	desc = "This spell creates your ethereal form, temporarily making you invisible and able to pass through walls."

	school = "transmutation"
	charge_max = 300
	spell_flags = Z2NOCAST | NEEDSCLOTHES | INCLUDEUSER
	invocation = "none"
	invocation_type = SpI_NONE
	range = -1
	max_targets = 1
	cooldown_min = 100 //50 deciseconds reduction per rank
	duration = 50 //in deciseconds

	hud_state = "wiz_jaunt"

/datum/spell/targeted/ethereal_jaunt/cast(list/targets) //magnets, so mostly hardcoded
	for(var/mob/living/target in targets)
		target.set_transforming(1) //protects the mob from being transformed (replaced) midjaunt and getting stuck in bluespace
		if(target?.buckled_to())
			var/atom/movable/_tmp_buck_41 = target?.buckled_to()
			_tmp_buck_41.unbuckle_mob( target, TRUE)
		var/mobloc = get_turf(target.loc)
		var/obj/effect/dummy/spell_jaunt/holder = new /obj/effect/dummy/spell_jaunt( mobloc )
		var/atom/movable/overlay/animation = new /atom/movable/overlay( mobloc )
		animation.name = "water"
		animation.set_density(FALSE)
		animation.set_anchored(TRUE)
		animation.icon = 'icons/mob/mob.dmi'
		animation.plane = MOB_PLANE
		animation.layer = ABOVE_MOB_LAYER
		rel_set(animation, nameof(animation.master), holder)
		target.extinguish_mob()
		if(target?.buckled_to())
			var/atom/movable/_tmp_buck_42 = target?.buckled_to()
			_tmp_buck_42.unbuckle_mob( target, TRUE)
		jaunt_disappear(animation, target)
		target.forceMove(holder)
		target.set_transforming(0) //mob is safely inside holder now, no need for protection.
		jaunt_steam(mobloc)
		after(src, duration, PROC_REF(jaunt_resurface), with = list(target, holder, animation))

/// The jaunt ends: steam where the jaunter will come out.
/datum/spell/targeted/ethereal_jaunt/proc/jaunt_resurface(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	if(!target || !holder || !animation)
		jaunt_finish(target, holder, animation)
		return
	var/mobloc = holder.last_valid_turf()
	animation.forceMove(mobloc)
	jaunt_steam(mobloc)
	target.canmove = 0
	holder.reappearing = 1
	after(src, 2 SECONDS, PROC_REF(jaunt_reform), with = list(target, holder, animation))

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_reform(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	if(!target || !holder || !animation)
		jaunt_finish(target, holder, animation)
		return
	jaunt_reappear(animation, target)
	after(src, 0.5 SECONDS, PROC_REF(jaunt_finish), with = list(target, holder, animation))

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_finish(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	var/mobloc = holder?.last_valid_turf() || get_turf(target)
	if(target)
		if(mobloc && !target.forceMove(mobloc))
			for(var/direction in list(1,2,4,8,5,6,9,10))
				var/turf/T = get_step(mobloc, direction)
				if(T)
					if(target.forceMove(T))
						break
		target.canmove = 1
		target.reset_perspective() // Fixes a blackscreen
	spent(animation)
	spent(holder)

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_disappear(atom/movable/overlay/animation, mob/living/target)
	animation.icon_state = "liquify"
	flick("liquify",animation)

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_reappear(atom/movable/overlay/animation, mob/living/target)
	flick("reappear",animation)

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_steam(mobloc)
	var/datum/effect/effect/system/steam_spread/steam = new /datum/effect/effect/system/steam_spread()
	steam.set_up(10, 0, mobloc)
	steam.start()

/obj/effect/dummy/spell_jaunt
	name = "water"
	resistance_flags = BOMB_PROOF
	icon = 'icons/effects/effects.dmi'
	icon_state = "nothing"
	var/canmove = 1
	var/reappearing = 0
	density = FALSE
	anchored = TRUE
	var/tmp/turf/last_valid_turf

// ALLOW(init/INSTANCE_STATE): remembers the turf it started on
/obj/effect/dummy/spell_jaunt/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(last_valid_turf), get_turf(loc))

CAPABILITIES(/obj/effect/dummy/spell_jaunt)
	owns_many(nameof(contents), on_destroy = ON_DESTROY_SPILL)
	extend(/datum/act/hit/projectile, instead())

/obj/effect/dummy/spell_jaunt/relaymove(mob/user, direction)
	if (!src.canmove || reappearing) return
	var/turf/newLoc = get_step(src,direction)
	if(newLoc && !(newLoc.flags & NOJAUNT))
		loc = newLoc // ALLOW(containment): jaunt holder abstract move: must not trigger Entered/Crossed
		var/turf/T = get_turf(loc)
		if(!T.contains_dense_objects())
			rel_set(src, nameof(last_valid_turf), T)
	else
		to_chat(user, span_warning("Some strange aura is blocking the way!"))
	src.canmove = 0
	after(src, 0.2 SECONDS, PROC_REF(allow_move))


/obj/effect/dummy/spell_jaunt/proc/allow_move()
	canmove = 1

/// the last_valid_turf this refers to (a relation view: null once it is deleted).
/obj/effect/dummy/spell_jaunt/proc/last_valid_turf() as /turf
	return last_valid_turf
