/mob/living/simple_mob/mechanical/mecha/eclipse/proc/summon_puddles(atom/A, next_cycle, puddle_item)
	for(var/mob/living/L in orange(src, 14))
		if(L.stat != DEAD && !IIsAlly(L))
			L.apply_body_effect(puddle_item, 3, src)
	attackcycle = next_cycle

/datum/body_effect/mmo_drop
	name = "Targeted"
	on_created_text = span_notice("You feel like you're being targeted.")
	stacks = MODIFIER_STACK_FORBID
	var/puddleitem = /obj/effect/spider/spiderling/antling

/datum/body_effect/mmo_drop/on_end(mob/living/L, expired)
	if(L.stat != DEAD)
		var/turf/T = get_turf(L)
		new puddleitem(T)

/datum/body_effect/mmo_drop/lingering
	tick_interval = 2 SECONDS
	var/dropchance = 50

/datum/body_effect/mmo_drop/lingering/on_tick(mob/living/L)
	if(L.stat != DEAD && prob(dropchance))
		var/turf/T = get_turf(L)
		new puddleitem(T)

/datum/body_effect/mmo_drop/jelly_fish
	puddleitem = /obj/effect/ant_structure/trap

/datum/body_effect/mmo_drop/blade_boss_long
	puddleitem = /obj/item/grenade/shooter/auto_explode/blade_boss_long

/datum/body_effect/mmo_drop/blade_boss_short
	puddleitem = /obj/item/grenade/shooter/auto_explode/blade_boss_short

/obj/item/grenade/shooter/auto_explode
	icon ='icons/obj/guns/precursor/tyr.dmi'
	icon_state = "explosion_marker"
	mouse_opacity = 0 //no touching the attack
	spread_range = 3
	var/fuse_time = 3.5 SECONDS

DECLARE_START_TIMER(/obj/item/grenade/shooter/auto_explode, "fuse_time", PROC_REF(detonate))

/obj/item/grenade/shooter/auto_explode/blood_boss
	spread_range = 2

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/blood_boss, shooter_grenade_projectiles, list(/obj/item/projectile/energy/blood_bullet))

/datum/body_effect/mmo_drop/lingering/blood_flower
	puddleitem = /obj/item/grenade/shooter/auto_explode/blood_boss

/obj/item/projectile/bullet/incendiary/dragonflame/occult
	range = 4
	speed = 4
	damage = 10

/obj/item/grenade/shooter/auto_explode/blade_boss_long
	spread_range = 1

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/blade_boss_long, shooter_grenade_projectiles, list(/obj/item/projectile/bullet/astral_blade))

/obj/item/grenade/shooter/auto_explode/blade_boss_short
	spread_range = 3

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/blade_boss_short, shooter_grenade_projectiles, list(/obj/item/projectile/bullet/astral_blade/short))

/obj/item/grenade/shooter/auto_explode/occult_fireball
	spread_range = 2

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/occult_fireball, shooter_grenade_projectiles, list(/obj/item/projectile/bullet/incendiary/dragonflame/occult))

/datum/body_effect/mmo_drop/occult_fireball
	puddleitem = /obj/item/grenade/shooter/auto_explode/occult_fireball

/obj/item/grenade/shooter/auto_explode/eclipse_iceball
	spread_range = 2

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/eclipse_iceball, shooter_grenade_projectiles, list(/obj/item/projectile/energy/eclipse_boss/chillingwind))

/datum/body_effect/mmo_drop/eclipse_iceball
	puddleitem = /obj/item/grenade/shooter/auto_explode/eclipse_iceball

/datum/body_effect/mmo_drop/metal_tomb
	puddleitem = /obj/structure/foamedmetal

/obj/item/grenade/shooter/auto_explode/eclipse_dagger
	spread_range = 4

TYPE_TABLE(/obj/item/grenade/shooter/auto_explode/eclipse_dagger, shooter_grenade_projectiles, list(/obj/item/projectile/energy/astral_collective/dagger))

/datum/body_effect/mmo_drop/eclipse_dagger
	puddleitem = /obj/item/grenade/shooter/auto_explode/eclipse_dagger
