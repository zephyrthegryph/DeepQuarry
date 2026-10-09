ADMIN_VERB(spawn_tanktransferbomb, R_SPAWN, "Instant TTV", "Spawn a tank transfer valve bomb.", ADMIN_CATEGORY_DEBUG_GAME)
	var/obj/effect/spawner/newbomb/proto = /obj/effect/spawner/newbomb/radio/custom
	var/datum/ttv_bomb_review/review = new
	rel_set(review, nameof(review.actor), user.mob)
	review.phoron = initial(proto.phoron_amt)
	review.oxygen = initial(proto.oxygen_amt)
	review.carbon = initial(proto.carbon_amt)
	review.start()

/// The three gas amounts, then the bomb at the admin's feet. The admin keeps R_SPAWN throughout.
/datum/ttv_bomb_review
	parent_type = /datum/prompt_workflow
	var/mob/actor
	var/phoron
	var/oxygen
	var/carbon

CAPABILITIES(/datum/ttv_bomb_review)
	ref_one(nameof(actor), /mob)

/datum/prompt/number/ttv_bomb_review
	timeout = 0
	rights = R_SPAWN
	step = 1
	min_value = 0
	max_value = INFINITY

/datum/ttv_bomb_review/proc/start()
	if(QDELETED(actor) || !admin_can(actor.client, R_SPAWN))
		retire()
		return
	var/datum/result/result = safe_call(PROC_REF(start_step))
	if(!result.ok)
		stack_trace("[type] start_step: [result.error]")
		retire()

/datum/ttv_bomb_review/proc/start_step()
	open_request(src, /datum/prompt/number/ttv_bomb_review, PROC_REF(phoron_entered), answerer = actor, asker = actor, title = "Phoron", question = "Enter phoron amount (mol):", default = phoron)

/datum/ttv_bomb_review/proc/run_step(step, datum/act/request/A)
	if(!A.answer || QDELETED(actor))
		retire()
		return
	var/datum/result/result = safe_call(step, A)
	if(!result.ok)
		stack_trace("TTV bomb step [step]: [result.error]")
		retire()

/datum/ttv_bomb_review/proc/phoron_entered(datum/act/request/A)
	run_step(PROC_REF(phoron_step), A)

/datum/ttv_bomb_review/proc/phoron_step(datum/act/request/A)
	phoron = A.answer.value
	open_request(src, /datum/prompt/number/ttv_bomb_review, PROC_REF(oxygen_entered), answerer = actor, asker = actor, title = "Oxygen", question = "Enter oxygen amount (mol):", default = oxygen)

/datum/ttv_bomb_review/proc/oxygen_entered(datum/act/request/A)
	run_step(PROC_REF(oxygen_step), A)

/datum/ttv_bomb_review/proc/oxygen_step(datum/act/request/A)
	oxygen = A.answer.value
	open_request(src, /datum/prompt/number/ttv_bomb_review, PROC_REF(carbon_entered), answerer = actor, asker = actor, title = "Carbon Dioxide", question = "Enter carbon dioxide amount (mol):", default = carbon)

/datum/ttv_bomb_review/proc/carbon_entered(datum/act/request/A)
	run_step(PROC_REF(carbon_step), A)

/datum/ttv_bomb_review/proc/carbon_step(datum/act/request/A)
	spawn_ttv_bomb(get_turf(actor), /obj/effect/spawner/newbomb/radio/custom, phoron, oxygen, A.answer.value)
	retire()

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

CAPABILITIES(/obj/effect/spawner/newbomb)
	map_resolver(GLOBAL_PROC_REF(resolve_newbomb), vars = list("carbon_amt", "oxygen_amt", "phoron_amt"))

/// The map resolver of mapped TTV bombs. The bomb goes where the spawner was: a
/// spawner created inside a container (the syndicate "screwed" kit box) fills
/// that container, not the floor under it.
/proc/resolve_newbomb(atom/loc, path, list/varedits)
	var/obj/effect/spawner/newbomb/P = path
	spawn_ttv_bomb(loc, path, MAP_VAR(P, varedits, phoron_amt), MAP_VAR(P, varedits, oxygen_amt), MAP_VAR(P, varedits, carbon_amt))
	return TRUE

/// Builds a welded tank transfer valve bomb of spawner type `path` (its assembly) at `loc`.
/proc/spawn_ttv_bomb(atom/loc, path, phoron, oxygen, carbon)
	var/obj/effect/spawner/newbomb/P = path
	var/assembly_type = initial(P.assembly_type)
	var/obj/item/transfer_valve/V = new(loc)
	var/obj/item/tank/phoron/PT = new(V)
	var/obj/item/tank/oxygen/OT = new(V)

	rel_set(V, nameof(V.tank_one), PT)
	rel_set(V, nameof(V.tank_two), OT)

	rel_set(PT, nameof(PT.master), V)
	rel_set(OT, nameof(OT.master), V)

	PT.valve_welded = 1
	// XGM exposed total_moles as a writable var; LINDA exposes it only
	// as a computed proc. The total is implied by the adjust_gas calls above —
	// dropping the assignment is correct, and update_values() is a no-op under
	// auxmos archiving.
	PT.air_contents.adjust_gas(GAS_PHORON, (phoron) - LINDA_GAS_AMT(PT.air_contents, GAS_PHORON))
	PT.air_contents.adjust_gas(GAS_CO2, (carbon) - LINDA_GAS_AMT(PT.air_contents, GAS_CO2))
	heat_set(PT.air_contents, PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	OT.valve_welded = 1
	OT.air_contents.adjust_gas(GAS_O2, (oxygen) - LINDA_GAS_AMT(OT.air_contents, GAS_O2))
	heat_set(OT.air_contents, PLASMA_MINIMUM_BURN_TEMPERATURE+1)

	var/obj/item/assembly/S = new assembly_type(V)
	rel_set(V, nameof(V.attached_device), S)

	rel_set(S, nameof(S.holder), V)
	S.toggle_secure()




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

CAPABILITIES(/obj/effect/spawner/onetankbomb)
	map_resolver(GLOBAL_PROC_REF(resolve_loot))
	loot(table = list(/obj/item/tank/phoron/onetankbomb, /obj/item/tank/oxygen/onetankbomb))


/obj/effect/spawner/onetankbomb/full
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"


	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
CAPABILITIES(/obj/effect/spawner/onetankbomb/full)
	configure(loot(table = list(/obj/item/tank/phoron/onetankbomb/full, /obj/item/tank/oxygen/onetankbomb/full)))


/obj/effect/spawner/onetankbomb/frag
	name = "Single-tank bomb"
	icon = 'icons/mob/screen1.dmi'
	icon_state = "x"


	//Note that the maximum amount of gas you can put in a 70L air tank at 1013.25 kPa and 519K is 16.44 mol.
