// Structures

/obj/effect/weaversilk
	name = "weaversilk web"
	desc = "A thin layer of fiberous webs. It looks like it can be torn down with one strong hit."
	icon = 'icons/vore/weaver_icons_vr.dmi'
	anchored = TRUE
	density = FALSE

CAPABILITIES(/obj/effect/weaversilk)
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(blasted_away))))

/// Any blast destroys the silk outright.
/obj/effect/weaversilk/proc/blasted_away(datum/act/A)
	spent(src)
	return TRUE

EXTEND_INTERACTIONS(/obj/effect/weaversilk, \
	INTERACT_ITEM(null, PROC_REF(interaction_hit_weaversilk)), \
	INTERACT_HAND_HOSTILE("Tear down", PROC_REF(interaction_tear_weaversilk)), \
)

/// Old attackby: any real hit tears the silk (afterattack still follows, as before).
/obj/effect/weaversilk/proc/interaction_hit_weaversilk(mob/user, obj/item/held, datum/interaction/interaction)
	var/obj/item/W = held
	user.setClickCooldown(user.get_attack_speed(W))

	if(W.force)
		act_message(user, src, others = span_warning("%T% has been [LAZYLEN(W.attack_verb) ? pick(W.attack_verb) : "attacked"] with %I% by %U%."), item = W)
		consume(src, user)
	return INTERACTION_HANDLED_PASS

/obj/effect/weaversilk/bullet_act(obj/item/projectile/Proj)
	..()
	if(Proj.get_structure_damage())
		consume(src)

/// Heat behaviour rule: silk burns away and feeds the fire.
/obj/effect/weaversilk/proc/rule_burn_away(datum/rule/rule)
	var/turf/T = get_turf(src)
	T?.feed_lingering_fire(0.1)
	destroyed(src, null, BURN)

/obj/effect/weaversilk/attack_generic(mob/user as mob, damage)
	if(damage)
		consume(src, user)

/// Old attack_hand on harm intent: tear the silk down by hand.
/obj/effect/weaversilk/proc/interaction_tear_weaversilk(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user,span_warning("You easily tear down [name]."))
	consume(src, user)
	return TRUE

/obj/effect/weaversilk/floor
	var/possible_icon_states = list("floorweb1", "floorweb2", "floorweb3", "floorweb4", "floorweb5", "floorweb6", "floorweb7", "floorweb8")
	plane = DIRTY_PLANE
	layer = DIRTY_LAYER

CAPABILITIES(/obj/effect/weaversilk/floor)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/effect/weaversilk/floor/proc/roll_icon_state(datum/roller/R)
	return R.choose(possible_icon_states)

/obj/effect/weaversilk/wall
	name = "weaversilk web wall"
	desc = "A thin layer of fiberous webs, but just thick enough to block your way. It looks like it can be torn down with one strong hit."
	icon_state = "wallweb1"
	var/possible_icon_states = list("wallweb1", "wallweb2", "wallweb3")
	density = TRUE

CAPABILITIES(/obj/effect/weaversilk/wall)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state))

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/effect/weaversilk/wall/proc/roll_icon_state(datum/roller/R)
	return R.choose(possible_icon_states)

/obj/effect/weaversilk/wall/CanPass(atom/movable/mover, turf/target)
	var/mob/living/L = mover
	if(istype(L) && L.get_weaver_state()) //only spooders can move on by
		return TRUE
	return FALSE

/obj/structure/bed/double/weaversilk_nest
	name = "weaversilk nest"
	desc = "A nest of some kind, made of fiberous material."
	icon = 'icons/vore/weaver_icons_vr.dmi'
	icon_state = "nest"
	base_icon = "nest"

APPEARANCE_NONE(/obj/structure/bed/double/weaversilk_nest)

EXTEND_INTERACTIONS(/obj/structure/bed/double/weaversilk_nest, \
	INTERACT_HAND_HOSTILE("Tear down", PROC_REF(interaction_tear_down)), \
	INTERACT_ITEM(null, PROC_REF(weaversilk_nest_interaction_item)), \
)

/// Old attackby.
/obj/structure/bed/double/weaversilk_nest/proc/weaversilk_nest_interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(W.has_tool_quality(TOOL_WRENCH) || istype(W,/obj/item/stack) || W.has_tool_quality(TOOL_WIRECUTTER))
		return INTERACTION_HANDLED_PASS
	return FALSE

/// Old attack_hand's harm branch: tear the empty nest down (combat mode only).
/obj/structure/bed/double/weaversilk_nest/proc/interaction_tear_down(mob/user, obj/item/held, datum/interaction/interaction)
	if(has_buckled_mobs())
		return FALSE
	to_chat(user,span_warning("You easily tear down [name]."))
	consume(src, user)
	return TRUE

/obj/effect/weaversilk/trap
	name = "weaversilk trap"
	desc = "A silky, yet firm trap. Be careful not to step into it! Or don't..."
	icon_state = "trap"
	var/trap_active = TRUE
	can_buckle = TRUE

/obj/effect/weaversilk/trap/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	var/mob/living/L = AM
	if(istype(L) && L.get_weaver_state())
		return
	if(isliving(AM) && trap_active)
		if(L.m_intent == I_RUN)
			act_message(L, src, MSG_SELF(span_danger("You step on %T%!")), \
				MSG_OTHERS(span_danger("%U% steps on %T%.")), \
				MSG_BLIND(span_infoplain(span_bold("You hear a squishy noise!"))))
			set_dir(L.dir)
			buckle_mob(L)
			L.status_at_least(STAT_STUNNED, 1)
			to_chat(L, span_danger("The sticky fibers of \the [src] ensnare, trapping you in place!"))
			trap_active = FALSE
			desc += " Actually, it looks like it's been all spent."
	..()


EXTEND_INTERACTIONS(/obj/effect/weaversilk/trap, \
	INTERACT_DRAG(null, TYPE_PROC_REF(/atom, interaction_swallow)), \
)

// Items

// TODO: Spidersilk clothing and actual bindings, once sprites are ready.

/obj/item/clothing/suit/weaversilk_bindings
	icon = 'icons/vore/custom_clothes_vr.dmi'
	icon_override = 'icons/vore/custom_clothes_vr.dmi'
	name = "weaversilk bindings"
	desc = "A webbed cocoon that completely restrains the wearer."
	icon_state = "web_bindings"
	body_parts_covered = CHEST|LEGS|FEET|ARMS|HANDS
	flags_inv = HIDEGLOVES|HIDESHOES|HIDEJUMPSUIT|HIDETAIL
	// Teshari sprite, this was originally aof the old web bindings
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/vore/custom_onmob_yw.dmi'
		)
	// end
