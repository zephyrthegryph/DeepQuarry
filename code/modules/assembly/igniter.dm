/obj/item/assembly/igniter
	name = "igniter"
	desc = "A small electronic device able to ignite combustable substances."
	icon_state = "igniter"
	MATERIAL_MIX(list(MAT_STEEL = 500, MAT_GLASS = 50))

	secured = 1
	wires_type = WIRE_RECEIVE
	special_handling = TRUE

/obj/item/assembly/igniter/activate()
	if(!..())
		return FALSE

	if(holder && istype(holder.loc,/obj/item/grenade/chem_grenade))
		var/obj/item/grenade/chem_grenade/grenade = holder.loc
		grenade.detonate()
	else
		var/turf/location = get_turf(loc)
		if(location)
			location.hotspot_expose(1000,1000)
		if (istype(src.loc,/obj/item/assembly_holder))
			if (istype(src.loc.loc, /obj/structure/reagent_dispensers/fueltank/))
				var/obj/structure/reagent_dispensers/fueltank/tank = src.loc.loc
				if (tank && tank.modded)
					tank.explode()

		var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
		s.set_up(3, 1, src)
		s.start()

	return TRUE


/// Overrides assembly's interaction_self(): activate instead of opening the UI.
/obj/item/assembly/igniter/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE
	activate()
	add_fingerprint(user)
	return TRUE

/obj/item/assembly/igniter/is_hot()
	return TRUE
