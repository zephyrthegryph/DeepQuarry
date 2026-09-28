ADMIN_VERB(spawn_tanktransferbomb, R_SPAWN, "Instant TTV", "Spawn a tank transfer valve bomb.", ADMIN_CATEGORY_DEBUG_GAME)
	var/obj/effect/spawner/newbomb/proto = /obj/effect/spawner/newbomb/radio/custom

	om_prompt_sequence(user, user, list(
		list("key" = "p", "kind" = "number", "message" = "Enter phoron amount (mol):", "title" = "Phoron", "default" = initial(proto.phoron_amt)),
		list("key" = "o", "kind" = "number", "message" = "Enter oxygen amount (mol):", "title" = "Oxygen", "default" = initial(proto.oxygen_amt)),
		list("key" = "c", "kind" = "number", "message" = "Enter carbon dioxide amount (mol):", "title" = "Carbon Dioxide", "default" = initial(proto.carbon_amt)),
	), GLOBAL_PROC_REF(spawn_tanktransferbomb_answered), list("requires" = PROMPT_ADMIN(R_SPAWN)))

/proc/spawn_tanktransferbomb_answered(client/C, mob/user, datum/om/prompt/ask)
	new /obj/effect/spawner/newbomb/radio/custom(get_turf(user), ask.get("p"), ask.get("o"), ask.get("c"))

/obj/effect/spawner/newbomb
	name = "TTV bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"

	var/assembly_type = /obj/item/assembly/signaler

	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
	var/phoron_amt = 12
	var/oxygen_amt = 18
	var/carbon_amt = 0

/obj/effect/spawner/newbomb/timer
	name = "TTV bomb - timer"
	assembly_type = /obj/item/assembly/timer

/obj/effect/spawner/newbomb/timer/syndicate
	name = "TTV bomb - merc"
	//High yield bombs. Yes, it is possible to make these with toxins
	phoron_amt = 18.5
	oxygen_amt = 28.5

/obj/effect/spawner/newbomb/proximity
	name = "TTV bomb - proximity"
	assembly_type = /obj/item/assembly/prox_sensor

/obj/effect/spawner/newbomb/radio/custom/Initialize(mapload, ph, ox, co)
	if(ph != null) phoron_amt = ph
	if(ox != null) oxygen_amt = ox
	if(co != null) carbon_amt = co
	. = ..()

/obj/effect/spawner/newbomb/Initialize(mapload)
	. = ..()
	var/obj/item/transfer_valve/V = new(src.loc)
	var/obj/item/tank/phoron/PT = new(V)
	var/obj/item/tank/oxygen/OT = new(V)

	V.tank_one = PT
	V.tank_two = OT

	PT.master = V
	OT.master = V

	PT.valve_welded = 1
	// XGM exposed total_moles as a writable var; LINDA exposes it only
	// as a computed proc. The total is implied by the adjust_gas calls above —
	// dropping the assignment is correct, and update_values() is a no-op under
	// auxmos archiving.
	PT.air_contents.adjust_gas(GAS_PHORON, (phoron_amt) - LINDA_GAS_AMT(PT.air_contents, GAS_PHORON))
	PT.air_contents.adjust_gas(GAS_CO2, (carbon_amt) - LINDA_GAS_AMT(PT.air_contents, GAS_CO2))
	PT.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	OT.valve_welded = 1
	OT.air_contents.adjust_gas(GAS_O2, (oxygen_amt) - LINDA_GAS_AMT(OT.air_contents, GAS_O2))
	OT.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	var/obj/item/assembly/S = new assembly_type(V)
	V.attached_device = S

	S.holder_handle = om_handle(V)
	S.toggle_secure()

	V.update_icon()
	return INITIALIZE_HINT_QDEL


///////////////////////
//One Tank Bombs, WOOOOOOO! -Luke
///////////////////////

/obj/effect/spawner/onetankbomb
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"

//	var/assembly_type = /obj/item/assembly/signaler

	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
	var/phoron_amt = 0
	var/oxygen_amt = 0

/obj/effect/spawner/onetankbomb/Initialize(mapload) //just needs an assembly.
	. = ..()

	var/type = pick(/obj/item/tank/phoron/onetankbomb, /obj/item/tank/oxygen/onetankbomb)
	replace_with(src, type)


/obj/effect/spawner/onetankbomb/full
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"

//	var/assembly_type = /obj/item/assembly/signaler

	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
/obj/effect/spawner/onetankbomb/full/Initialize(mapload) //just needs an assembly.
	. = ..()

	var/type = pick(/obj/item/tank/phoron/onetankbomb/full, /obj/item/tank/oxygen/onetankbomb/full)
	replace_with(src, type)


/obj/effect/spawner/onetankbomb/frag
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"

//	var/assembly_type = /obj/item/assembly/signaler

	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
