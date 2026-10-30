MATERIAL_MIX(/obj/item/assembly/igniter, list(MAT_STEEL = 500, MAT_GLASS = 50))
/obj/item/assembly/igniter
	name = "igniter"
	desc = "A small electronic device able to ignite combustable substances."
	icon_state = "igniter"

	secured = 1
	wires_type = WIRE_RECEIVE
	special_handling = TRUE

/obj/item/assembly/igniter/activate()
	if(!..())
		return FALSE

	if(holder() && istype(holder().loc,/obj/item/grenade/chem_grenade))
		var/obj/item/grenade/chem_grenade/grenade = holder().loc
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

		fx_sparks(src, 3)

	return TRUE


/// Overrides assembly's interaction_self(): activate instead of opening the UI.
/obj/item/assembly/igniter/interaction_self(datum/act/op/A)
	activate()
	add_fingerprint(A.actor)
	return OP_OK

/obj/item/assembly/igniter/is_hot()
	return TRUE
