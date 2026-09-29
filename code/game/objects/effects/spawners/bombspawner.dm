ADMIN_VERB(spawn_tanktransferbomb, R_SPAWN, "Instant TTV", "Spawn a tank transfer valve bomb.", ADMIN_CATEGORY_DEBUG_GAME)
	var/obj/effect/spawner/newbomb/proto = /obj/effect/spawner/newbomb/radio/custom

	om_flow_start(/datum/om/flow/ttv_bomb, user.mob, null, phoron = initial(proto.phoron_amt), oxygen = initial(proto.oxygen_amt), carbon = initial(proto.carbon_amt))

/// The three gas amounts, then the bomb at the admin's feet. The admin keeps R_SPAWN throughout.
/datum/om/flow/ttv_bomb
	requires = PROMPT_ADMIN(R_SPAWN)
	var/phoron
	var/oxygen
	var/carbon

/datum/om/flow/ttv_bomb/start()
	om_ask(actor, /datum/om/prompt/number, PROC_REF(phoron_entered), title = "Phoron", message = "Enter phoron amount (mol):", default = phoron)

/datum/om/flow/ttv_bomb/proc/phoron_entered(datum/om/prompt/number/ask)
	phoron = ask.number
	om_ask(actor, /datum/om/prompt/number, PROC_REF(oxygen_entered), title = "Oxygen", message = "Enter oxygen amount (mol):", default = oxygen)

/datum/om/flow/ttv_bomb/proc/oxygen_entered(datum/om/prompt/number/ask)
	oxygen = ask.number
	om_ask(actor, /datum/om/prompt/number, PROC_REF(carbon_entered), title = "Carbon Dioxide", message = "Enter carbon dioxide amount (mol):", default = carbon)

/datum/om/flow/ttv_bomb/proc/carbon_entered(datum/om/prompt/number/ask)
	spawn_ttv_bomb(get_turf(actor), /obj/effect/spawner/newbomb/radio/custom, phoron, oxygen, ask.number)

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

/// The admin "Instant TTV" bomb: signaler, gas amounts given by the admin (spawn_ttv_bomb()).
/obj/effect/spawner/newbomb/radio/custom

MAP_RESOLVER(/obj/effect/spawner/newbomb, GLOBAL_PROC_REF(resolve_newbomb))
MAP_RESOLVER_VARS(/obj/effect/spawner/newbomb, "carbon_amt;oxygen_amt;phoron_amt")

/// MAP_RESOLVER for mapped TTV bombs.
/proc/resolve_newbomb(atom/loc, path, list/varedits)
	var/obj/effect/spawner/newbomb/P = path
	spawn_ttv_bomb(get_turf(loc), path, MAP_VAR(P, varedits, phoron_amt), MAP_VAR(P, varedits, oxygen_amt), MAP_VAR(P, varedits, carbon_amt))
	return TRUE

/// Builds a welded tank transfer valve bomb of spawner type `path` (its assembly) at `loc`.
/proc/spawn_ttv_bomb(atom/loc, path, phoron, oxygen, carbon)
	var/obj/effect/spawner/newbomb/P = path
	var/assembly_type = initial(P.assembly_type)
	var/obj/item/transfer_valve/V = new(loc)
	var/obj/item/tank/phoron/PT = new(V)
	var/obj/item/tank/oxygen/OT = new(V)

	own_set(V, "tank_one", PT)
	own_set(V, "tank_two", OT)

	rel_set(PT, "master", V)
	rel_set(OT, "master", V)

	PT.valve_welded = 1
	// XGM exposed total_moles as a writable var; LINDA exposes it only
	// as a computed proc. The total is implied by the adjust_gas calls above —
	// dropping the assignment is correct, and update_values() is a no-op under
	// auxmos archiving.
	PT.air_contents.adjust_gas(GAS_PHORON, (phoron) - LINDA_GAS_AMT(PT.air_contents, GAS_PHORON))
	PT.air_contents.adjust_gas(GAS_CO2, (carbon) - LINDA_GAS_AMT(PT.air_contents, GAS_CO2))
	PT.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	OT.valve_welded = 1
	OT.air_contents.adjust_gas(GAS_O2, (oxygen) - LINDA_GAS_AMT(OT.air_contents, GAS_O2))
	OT.air_contents.set_temperature(PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	var/obj/item/assembly/S = new assembly_type(V)
	own_set(V, "attached_device", S)

	rel_set(S, "holder", V)
	S.toggle_secure()

	V.update_icon()



///////////////////////
//One Tank Bombs, WOOOOOOO! -Luke
///////////////////////

/obj/effect/spawner/onetankbomb
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"


	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
	var/phoron_amt = 0
	var/oxygen_amt = 0

MAP_RESOLVER(/obj/effect/spawner/onetankbomb, GLOBAL_PROC_REF(resolve_loot))
DECLARE_LOOT(/obj/effect/spawner/onetankbomb, LOOT_TABLE(/obj/item/tank/phoron/onetankbomb, /obj/item/tank/oxygen/onetankbomb))


/obj/effect/spawner/onetankbomb/full
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"


	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
DECLARE_LOOT(/obj/effect/spawner/onetankbomb/full, LOOT_TABLE(/obj/item/tank/phoron/onetankbomb/full, /obj/item/tank/oxygen/onetankbomb/full))


/obj/effect/spawner/onetankbomb/frag
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"


	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
