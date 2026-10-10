#define COOLING_FACTOR 12500 //5000 in a near empty 7x7 room with a heat cap of 478325 drops it by 20.9C. 125000 drops it by 52.25C. This seems appropriate.
/obj/structure/reagent_dispensers/coolanttank
	name = "coolant tank"
	desc = "A tank of industrial coolant"
	icon = 'icons/obj/objects.dmi'
	icon_state = "coolanttank"
	amount_per_transfer_from_this = 10

/obj/structure/reagent_dispensers/coolanttank/bullet_act(obj/item/projectile/Proj)
	if(Proj.get_structure_damage())
		explode()

CAPABILITIES(/obj/structure/reagent_dispensers/coolanttank)
	configure(reagents(add = list(REAGENT_ID_COOLANT = 1000)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(tank_blast_explode))))

/// A blast bursts the tank.
/obj/structure/reagent_dispensers/coolanttank/proc/tank_blast_explode(datum/act/hit/explosion/A)
	explode()
	return OP_OK

/obj/structure/reagent_dispensers/coolanttank/proc/explode()
	var/datum/effect/effect/system/smoke_spread/S = new /datum/effect/effect/system/smoke_spread
	S.set_up(5, 0, src.loc)

	play_sfx(src, SFX_EFFECTS_SMOKE)
	S.start()
	var/datum/gas_mixture/env = src.loc.return_air()
	if(env)
		var/cooling_strength = reagents.machine_cooling_power()
		if(cooling_strength > 0)
			heat_add(env, -(cooling_strength * COOLING_FACTOR), HEAT_SOURCE_DEVICE)

	expire(10)

#undef COOLING_FACTOR
