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
		target.transforming = 1 //protects the mob from being transformed (replaced) midjaunt and getting stuck in bluespace
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
		animation.master = holder
		target.extinguish_mob()
		if(target?.buckled_to())
			var/atom/movable/_tmp_buck_42 = target?.buckled_to()
			_tmp_buck_42.unbuckle_mob( target, TRUE)
		jaunt_disappear(animation, target)
		target.forceMove(holder)
		target.transforming=0 //mob is safely inside holder now, no need for protection.
		jaunt_steam(mobloc)
		om_after(src, duration, PROC_REF(jaunt_resurface), target, holder, animation)

/// The jaunt ends: steam where the jaunter will come out.
/datum/spell/targeted/ethereal_jaunt/proc/jaunt_resurface(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	var/mobloc = holder.last_valid_turf()
	animation.forceMove(mobloc)
	jaunt_steam(mobloc)
	target.canmove = 0
	holder.reappearing = 1
	om_after(src, 2 SECONDS, PROC_REF(jaunt_reform), target, holder, animation)

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_reform(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	jaunt_reappear(animation, target)
	om_after(src, 5, PROC_REF(jaunt_finish), target, holder, animation)

/datum/spell/targeted/ethereal_jaunt/proc/jaunt_finish(mob/living/target, obj/effect/dummy/spell_jaunt/holder, atom/movable/overlay/animation)
	var/mobloc = holder.last_valid_turf()
	if(!target.forceMove(mobloc))
		for(var/direction in list(1,2,4,8,5,6,9,10))
			var/turf/T = get_step(mobloc, direction)
			if(T)
				if(target.forceMove(T))
					break
	target.canmove = 1
	target.reset_perspective() // Fixes a blackscreen
	qdel(animation)
	qdel(holder)

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
	var/tmp/last_valid_turf_handle

/obj/effect/dummy/spell_jaunt/Initialize(mapload)
	. = ..()
	last_valid_turf_handle = om_handle(get_turf(loc))

DECLARE_REF(/obj/effect/dummy/spell_jaunt, "contents", SPILL_LIST, null)

/obj/effect/dummy/spell_jaunt/relaymove(mob/user, direction)
	if (!src.canmove || reappearing) return
	var/turf/newLoc = get_step(src,direction)
	if(newLoc && !(newLoc.flags & NOJAUNT))
		loc = newLoc // ALLOW(containment): jaunt holder abstract move: must not trigger Entered/Crossed
		var/turf/T = get_turf(loc)
		if(!T.contains_dense_objects())
			last_valid_turf_handle = om_handle(T)
	else
		to_chat(user, span_warning("Some strange aura is blocking the way!"))
	src.canmove = 0
	om_after(src, 2, PROC_REF(allow_move))

DAMAGE_REACTION(/obj/effect/dummy/spell_jaunt, DAMAGE_PROJECTILE, TYPE_PROC_REF(/atom, damage_reaction_block))

/obj/effect/dummy/spell_jaunt/proc/allow_move()
	canmove = 1

/// LC-refs: the last_valid_turf this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/effect/dummy/spell_jaunt/proc/last_valid_turf() as /turf
	return om_resolve(last_valid_turf_handle)
