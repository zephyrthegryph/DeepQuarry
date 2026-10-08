//backpack item
/obj/item/medigun_backpack
	name = "protoype bluespace medigun backpack"
	desc = "Contains a bluespace medigun, this portable unit digitizes and stores chems and battery power used by the attached gun."
	icon = 'icons/obj/borkmedigun.dmi'
	icon_override = 'icons/obj/borkmedigun.dmi'
	icon_state = "mg-backpack"
	item_state = "mg-backpack-onmob"
	slot_flags = SLOT_BACK
	force = 5
	throwforce = 6
	preserve_item = TRUE
	w_class = ITEMSIZE_HUGE
	unacidable = TRUE

	var/medigun_path = /obj/item/bork_medigun/linked
	var/obj/item/cell/bcell = /obj/item/cell
	var/obj/item/cell/ccell = null
	var/obj/item/stock_parts/matter_bin/sbin = /obj/item/stock_parts/matter_bin
	var/obj/item/stock_parts/scanning_module/smodule = /obj/item/stock_parts/scanning_module
	var/obj/item/stock_parts/manipulator/smanipulator = /obj/item/stock_parts/manipulator
	var/obj/item/stock_parts/capacitor/scapacitor = /obj/item/stock_parts/capacitor
	var/obj/item/stock_parts/micro_laser/slaser = /obj/item/stock_parts/micro_laser
	var/charging = FALSE
	var/brutecharge = 0
	var/toxcharge = 0
	var/burncharge = 0
	var/brutevol = 0
	var/toxvol = 0
	var/burnvol = 0
	var/chemcap = 60
	var/tankmax = 30
	var/containsgun = TRUE
	var/maintenance = FALSE
	var/smaniptier = 1
	var/sbintier = 1
	var/gridstatus = 0
	var/chargecap = 1000

CAPABILITIES(/obj/item/medigun_backpack)
	// Recharges its tanks and cell every 2 s while its manipulator, capacitor and matter bin are all fitted.
	every(2 SECONDS, then(PROC_REF(medigun_backpack_step)), when = cond_all(nameof(smanipulator), nameof(scapacitor), nameof(sbin)))
	owns_one(nameof(scapacitor), /obj/item/stock_parts/capacitor, starts = nameof(scapacitor))
	owns_one(nameof(slaser), /obj/item/stock_parts/micro_laser, starts = nameof(slaser))
	owns_one(nameof(smanipulator), /obj/item/stock_parts/manipulator, starts = nameof(smanipulator))
	owns_one(nameof(smodule), /obj/item/stock_parts/scanning_module, starts = nameof(smodule))
	owns_one(nameof(bcell), starts = nameof(bcell))
	interface("Medigun")
	without("ui_open")
	op("celleject", ui_act("celleject"), then(PROC_REF(ui_act_celleject)))
	op("cancel_healing", ui_act("cancel_healing"), then(PROC_REF(ui_act_cancel_healing)))
	op("toggle_maintenance", ui_act("toggle_maintenance"), then(PROC_REF(ui_act_toggle_maintenance)))
	op("rem_smodule", ui_act("rem_smodule"), then(PROC_REF(ui_act_rem_smodule)))
	op("rem_mani", ui_act("rem_mani"), then(PROC_REF(ui_act_rem_mani)))
	op("rem_laser", ui_act("rem_laser"), then(PROC_REF(ui_act_rem_laser)))
	op("rem_cap", ui_act("rem_cap"), then(PROC_REF(ui_act_rem_cap)))
	op("rem_bin", ui_act("rem_bin"), then(PROC_REF(ui_act_rem_bin)))
	op("hand", hand(), label("Use"), then(PROC_REF(interaction_hand)))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(medigun_backpack_emp)))
	drag_onto(PROC_REF(drop_input))

//backpack item
/obj/item/medigun_backpack/cmo
	name = "prototype bluespace medigun backpack - CMO"
	desc = "Contains a compact version of the bluespace medigun able to be used one handed, this portable unit digitizes and stores chems and battery power used by the attached gun."
	icon_state = "mg-backpack_cmo"
	item_state = "mg-backpack_cmo-onmob"
	scapacitor = /obj/item/stock_parts/capacitor
	smanipulator = /obj/item/stock_parts/manipulator
	smodule = /obj/item/stock_parts/scanning_module
	slaser = /obj/item/stock_parts/micro_laser
	bcell = /obj/item/cell/apc
	tankmax = 60
	brutecharge = 60
	toxcharge = 60
	burncharge = 60
	chemcap = 120
	brutevol = 120
	toxvol = 120
	burnvol = 120
	chargecap = 5000

/obj/item/medigun_backpack/proc/is_twohanded()
	return TRUE

// --- Treatment modes ----------------------------------------------------------
// Each tank is a mode: it provides treatment tags and the medigun mends only
// the tags the patient's automated triage demands. Nothing reads injury loads.

#define MEDIGUN_TANK_BRUTE 1
#define MEDIGUN_TANK_BURN 2
#define MEDIGUN_TANK_TOX 3
#define MEDIGUN_TANK_COUNT 3

/// TREAT_* -> the tank (MEDIGUN_TANK_*) that powers it.
TYPE_TABLE_DECLARE(/obj/item/medigun_backpack, medigun_mode_tags, list( \
		TREAT_TISSUE_REPAIR = MEDIGUN_TANK_BRUTE, \
		TREAT_HEMOSTATIC = MEDIGUN_TANK_BRUTE, \
		TREAT_BURN_CARE = MEDIGUN_TANK_BURN, \
		TREAT_ANTITOXIN = MEDIGUN_TANK_TOX, \
	))

/obj/item/medigun_backpack/proc/tank_charge(tank)
	switch(tank)
		if(MEDIGUN_TANK_BRUTE)
			return brutecharge
		if(MEDIGUN_TANK_BURN)
			return burncharge
		if(MEDIGUN_TANK_TOX)
			return toxcharge
	return 0

/obj/item/medigun_backpack/proc/drain_tank(tank, amount)
	switch(tank)
		if(MEDIGUN_TANK_BRUTE)
			brutecharge = max(0, brutecharge - amount)
		if(MEDIGUN_TANK_BURN)
			burncharge = max(0, burncharge - amount)
		if(MEDIGUN_TANK_TOX)
			toxcharge = max(0, toxcharge - amount)

/// Mend what `H`'s automated triage demands from the tanks' tags, up to
/// `strength` per tank this cycle. Returns the total amount treated.
/obj/item/medigun_backpack/proc/treat_demand(mob/living/H, strength)
	. = 0
	var/list/demand = H.treatment_demand(/datum/diagnostic_profile/automation)
	if(!demand || strength <= 0)
		return
	var/list/tags = TYPE_TABLE_GET(src, medigun_mode_tags)
	var/list/spent = new /list(MEDIGUN_TANK_COUNT)
	for(var/tag in tags)
		if(!demand[tag])
			continue
		var/tank = tags[tag]
		var/budget = min(strength - spent[tank], tank_charge(tank))
		if(budget <= 0)
			continue
		var/treated = min(H.mend(tag, budget), budget)
		if(treated <= 0)
			continue
		spent[tank] += treated
		drain_tank(tank, treated)
		. += treated
	if(.)
		log_game("MEDIGUN: [src] treated [key_name(H)] for [round(., 0.1)] (brute [round(spent[MEDIGUN_TANK_BRUTE], 0.1)], burn [round(spent[MEDIGUN_TANK_BURN], 0.1)], tox [round(spent[MEDIGUN_TANK_TOX], 0.1)]).")

#undef MEDIGUN_TANK_BRUTE
#undef MEDIGUN_TANK_BURN
#undef MEDIGUN_TANK_TOX
#undef MEDIGUN_TANK_COUNT

/obj/item/medigun_backpack/cmo/is_twohanded()
	return FALSE

/obj/item/medigun_backpack/proc/apc_charge()
	gridstatus = 0
	var/area/A = get_area(src)
	if(!istype(A) || !A.powered(EQUIP))
		return FALSE
	gridstatus = 1
	if(bcell && (bcell.charge < bcell.maxcharge))
		var/cur_charge = bcell.charge
		var/delta = min(50, bcell.maxcharge-cur_charge)
		bcell.give(delta)
		A.use_power_oneoff(delta*100, EQUIP)
		gridstatus = 2
	return TRUE

/obj/item/medigun_backpack/proc/adjust_brutevol(modifier)
	if(modifier > brutevol)
		modifier = brutevol
	if(modifier > (tankmax - brutecharge))
		modifier = tankmax - brutecharge
	brutevol -= modifier
	brutecharge += modifier

/obj/item/medigun_backpack/proc/adjust_burnvol(modifier)
	if(modifier > burnvol)
		modifier = burnvol
	if(modifier > (tankmax - burncharge))
		modifier = tankmax - burncharge
	burnvol -= modifier
	burncharge += modifier

/obj/item/medigun_backpack/proc/adjust_toxvol(modifier)
	if(modifier > toxvol)
		modifier = toxvol
	if(modifier > (tankmax - toxcharge))
		modifier = tankmax - toxcharge
	toxvol -= modifier
	toxcharge += modifier

/obj/item/medigun_backpack/proc/medigun_backpack_step(datum/act/timer/A)
	if(!bcell)
		return

	var/obj/item/bork_medigun/medigun = get_medigun()

	if(bcell.charge >= 10)
		var/icon_needs_update = FALSE
		if(brutecharge < tankmax && brutevol > 0 && (bcell.checked_use(smaniptier * 2)))
			adjust_brutevol(smaniptier * 2)
			icon_needs_update = TRUE
		if(burncharge < tankmax && burnvol > 0 && (bcell.checked_use(smaniptier * 2)))
			adjust_burnvol(smaniptier * 2)
			icon_needs_update = TRUE
		if(toxcharge < tankmax && toxvol > 0 && (bcell.checked_use(smaniptier * 2)))
			adjust_toxvol(smaniptier * 2)
			icon_needs_update = TRUE
		//Alien tier
		if(sbintier >= 5 && medigun.busy == MEDIGUN_IDLE && (bcell.charge >= 10))
			if(brutevol < chemcap && (bcell.checked_use(10)))
				icon_needs_update = TRUE
				brutevol ++
			if(burnvol < chemcap && (bcell.checked_use(10)))
				icon_needs_update = TRUE
				burnvol ++
			if(toxvol < chemcap && (bcell.checked_use(10)))
				icon_needs_update = TRUE
				toxvol ++

		if(icon_needs_update)
			changed(src)

	if(scapacitor.get_rating() >= 5)
		if(apc_charge())
			charging = FALSE
			return
		charging = TRUE

	if(!charging || !ccell)
		return

	var/scaptier = scapacitor.get_rating()
	var/missing = min(scaptier*25, bcell.amount_missing())

	if(missing > 0)
		if(ccell && ccell.checked_use(missing))
			bcell.give(missing)
			changed(src)
			return

		if(ismob(loc))
			to_chat(loc, span_notice("The [ccell] runs out of power.."))
		charging = FALSE

/obj/item/medigun_backpack/get_cell()
	return bcell

/obj/item/medigun_backpack/draw(datum/look/look)
	..()
	if((bcell.percent() <= 5 ))
		look.overlay(image('icons/obj/borkmedigun.dmi', "no_battery"))
	else if((bcell.percent() <= 25 && bcell.percent() > 5))
		look.overlay(image('icons/obj/borkmedigun.dmi', "low_battery"))

	if(brutevol <= 0 && brutecharge > 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "red"))
	else if(brutecharge <= 0 && brutevol <= 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "redstrike-blink"))

	if(toxvol <= 0 && toxcharge > 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "green"))
	else if(toxcharge <= 0 && toxvol <= 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "greenstrike-blink"))

	if(burnvol <= 0 && burncharge > 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "orange"))
	else if(burncharge <= 0 && burnvol <= 0)
		look.overlay(image('icons/obj/borkmedigun.dmi', "orangestrike-blink"))

/obj/item/medigun_backpack/proc/replace_icon(inhand)
	var/obj/item/bork_medigun/medigun = get_medigun()
	if(inhand)
		icon_state = "mg-backpack-deployed"
		item_state = "mg-backpack-deployed-onmob"
		if(is_twohanded())
			medigun.icon_state = "medblaster"
			medigun.base_icon_state = "medblaster"
			medigun.wielded_item_state = "medblaster-wielded"
		else
			medigun.icon_state = "medblaster_cmo"
			medigun.base_icon_state = "medblaster_cmo"
			medigun.wielded_item_state = ""
	else if(is_twohanded())
		icon_state = "mg-backpack"
		item_state = "mg-backpack-onmob"
		medigun.icon_state = "medblaster"
		medigun.base_icon_state = "medblaster"
	else
		icon_state = "mg-backpack_cmo"
		item_state = "mg-backpack_cmo-onmob"
		medigun.icon_state = "medblaster_cmo"
		medigun.base_icon_state = "medblaster_cmo"

	changed(src)

/obj/item/medigun_backpack/Initialize(mapload)
	make_tethered(medigun_path)
	. = ..()

	var/obj/item/bork_medigun/linked/medigun = get_medigun()
	rel_set(medigun, nameof(medigun.medigun_base_unit), src)

	if(!is_twohanded())
		medigun.beam_range = 4
		medigun.icon_state = "medblaster_cmo"
		medigun.base_icon_state = "medblaster_cmo"
		medigun.wielded_item_state = ""
	if(bcell) // declared default: starts empty
		bcell.charge = 0


/obj/item/medigun_backpack/proc/get_medigun()
	return tethered_handheld()

/// The pulse reaches the cell.
/obj/item/medigun_backpack/proc/medigun_backpack_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	if(bcell)
		bcell.emp_act(packet.severity)

/// Old attack_hand.
/obj/item/medigun_backpack/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	// See important note in code/datums/behaviours/tethered_item.dm
	if(tether_swap(user))
		return TRUE
	return OP_DECLINE

/// The native drop's actor and arguments, handed over by the engine (drag_onto(), code/engine/lifeforms/input.dm). The worn pack is dragged into its wearer's hands.
/obj/item/medigun_backpack/proc/drop_input(datum/act/input/A)
	drag_backpack_with_actor(A.actor)
	return TRUE

/obj/item/medigun_backpack/proc/drag_backpack_with_actor(mob/user)
	if(ismob(src.loc))
		if(!CanMouseDrop(src, user))
			return
		var/mob/M = src.loc
		if(!M.unEquip(src))
			return
		src.add_fingerprint(user)
		M.put_in_any_hand_if_possible(src)

/// Old attackby.
/obj/item/medigun_backpack/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(refill_reagent(W, user))
		return OP_PASS

	var/obj/item/bork_medigun/medigun = get_medigun()

	if(W.has_tool_quality(TOOL_CROWBAR) && maintenance)
		if(smodule )
			smodule.forceMove(get_turf(loc))
			rel_take(src, nameof(smodule))

		if(smanipulator)
			smanipulator.forceMove(get_turf(loc))
			rel_take(src, nameof(smanipulator))
			smaniptier = 0

		if(slaser)
			slaser.forceMove(get_turf(loc))
			rel_take(src, nameof(slaser))

		if(scapacitor)
			scapacitor.forceMove(get_turf(loc))
			rel_take(src, nameof(scapacitor))

		if(sbin)
			sbin.forceMove(get_turf(loc))
			rel_take(src, nameof(sbin))
			sbintier = 0

		to_chat(user, span_notice("You remove the Components from \the [src]."))
		return TRUE

	if(W.has_tool_quality(TOOL_SCREWDRIVER))
		if(!maintenance)
			maintenance = TRUE
			to_chat(user, span_notice("You open the maintenance hatch on \the [src]."))
			return OP_PASS

		maintenance = FALSE
		to_chat(user, span_notice("You close the maintenance hatch on \the [src]."))
		return OP_PASS

	if(istype(W, /obj/item/cell))
		if(ccell)
			to_chat(user, span_notice("You swap the [W] for \the [ccell]."))
		if(!move_into(src, nameof(src.ccell), W, user))
			return OP_PASS
		to_chat(user, span_notice("You install the [W] into \the [src]."))
		charging = TRUE
		return OP_PASS

	if(maintenance)
		if(istype(W, /obj/item/stock_parts/scanning_module))
			if(smodule)
				to_chat(user, span_notice("\The [src] already has a scanning module."))
			else
				if(!move_into(src, nameof(src.smodule), W, user))
					return OP_PASS
				to_chat(user, span_notice("You install the [W] into \the [src]."))
				medigun.beam_range = 3+smodule.get_rating()
				return OP_PASS

		if(istype(W, /obj/item/stock_parts/manipulator))
			if(smanipulator)
				to_chat(user, span_notice("\The [src] already has a manipulator."))
				return OP_PASS
			if(!move_into(src, nameof(src.smanipulator), W, user))
				return OP_PASS
			smaniptier = smanipulator.get_rating()
			to_chat(user, span_notice("You install the [W] into \the [src]."))
			return OP_PASS

		if(istype(W, /obj/item/stock_parts/micro_laser))
			if(slaser)
				to_chat(user, span_notice("\The [src] already has a micro laser."))
				return OP_PASS
			if(!move_into(src, nameof(src.slaser), W, user))
				return OP_PASS
			to_chat(user, span_notice("You install the [W] into \the [src]."))
			return OP_PASS

		if(istype(W, /obj/item/stock_parts/capacitor))
			if(scapacitor)
				to_chat(user, span_notice("\The [src] already has a capacitor."))
				return OP_PASS
			if(!move_into(src, nameof(src.scapacitor), W, user))
				return OP_PASS
			var/scaptier = scapacitor.get_rating()
			if(scaptier == 1)
				chargecap = 1000
				bcell.maxcharge = 1000
				if(bcell.charge > chargecap)
					bcell.charge = chargecap
			else if(scaptier == 2)
				chargecap = 2000
				bcell.maxcharge = 2000
				if(bcell.charge > chargecap)
					bcell.charge = chargecap
			else if(scaptier == 3)
				chargecap = 3000
				bcell.maxcharge = 3000
				if(bcell.charge > chargecap)
					bcell.charge = chargecap
			else if(scaptier == 4)
				chargecap = 4000
				bcell.maxcharge = 4000
				if(bcell.charge > chargecap)
					bcell.charge = chargecap
			else if(scaptier == 5)
				chargecap = 5000
				bcell.maxcharge = 5000
				if(bcell.charge > chargecap)
					bcell.charge = chargecap

			to_chat(user, span_notice("You install the [W] into \the [src]."))
			return OP_PASS

		if(istype(W, /obj/item/stock_parts/matter_bin))
			if(sbin)
				to_chat(user, span_notice("\The [src] already has a matter bin."))
				return OP_PASS
			if(!move_into(src, nameof(src.sbin), W, user))
				return OP_PASS
			sbintier = sbin.get_rating()
			if(sbintier >= 5)
				chemcap = 300
				tankmax = 150
			else
				chemcap = 60*(sbintier)
				tankmax = 30*sbintier
			if(brutecharge > chemcap)
				brutecharge = chemcap
			if(burncharge > chemcap)
				burncharge = chemcap
			if(toxcharge > chemcap)
				toxcharge = chemcap
			if(brutecharge > tankmax)
				brutecharge = tankmax
			if(burncharge > tankmax)
				burncharge = tankmax
			if(toxcharge > tankmax)
				toxcharge = tankmax
			to_chat(user, span_notice("You install the [W] into \the [src]."))
			return OP_PASS

	return OP_DECLINE

/obj/item/medigun_backpack/proc/refill_reagent(obj/item/container, mob/user)
	. = FALSE
	if(!maintenance && (istype(container, /obj/item/reagent_containers/glass/beaker) || istype(container, /obj/item/reagent_containers/glass/bottle)))

		if(!container.is_open_container())
			to_chat(user, span_warning("You need to open the [container] first!"))
			return

		var/reagentwhitelist = list(REAGENT_ID_BICARIDINE, REAGENT_ID_ANTITOXIN, REAGENT_ID_KELOTANE, REAGENT_ID_DERMALINE)//"tricordrazine")

		for(var/G in container.reagents.reagent_list)
			var/datum/reagent/R = G
			var/modifier = 1
			var/totransfer = 0
			var/name = ""

			if(R.id in reagentwhitelist)
				switch(R.id)
					if(REAGENT_ID_BICARIDINE)
						name = "bruteheal"
						modifier = 4
						totransfer = chemcap - brutevol
					if(REAGENT_ID_ANTITOXIN)
						name = "toxheal"
						modifier = 4
						totransfer = chemcap - toxvol
					if(REAGENT_ID_KELOTANE)
						name = "burnheal"
						modifier = 4
						totransfer = chemcap - burnvol
					if(REAGENT_ID_DERMALINE)
						name = "burnheal"
						modifier = 8
						totransfer = chemcap - burnvol
				if(totransfer <= 0)
					to_chat(user, span_notice("The [src] cannot accept anymore [name]!"))
				totransfer = min(totransfer, container.reagents.get_reagent_amount(R.id) * modifier)

				switch(R.id)
					if(REAGENT_ID_BICARIDINE)
						brutevol += totransfer
					if(REAGENT_ID_ANTITOXIN)
						toxvol += totransfer
					if(REAGENT_ID_KELOTANE)
						burnvol += totransfer
					if(REAGENT_ID_DERMALINE)
						burnvol += totransfer
				if(totransfer > 0)
					if(R.id != "tricordrazine")
						to_chat(user, span_notice("You add [totransfer / modifier] units of [R.name] to the [src]. \n The [src] stores [round(totransfer)] U of [name]."))
					container.reagents.remove_reagent(R.id, totransfer / modifier)
					play_sfx(src, SFX_WEAPONS_EMPTY)
				changed(src)
				. = TRUE
	return

//checks that the base unit is in the correct slot to be used
/obj/item/medigun_backpack/proc/slot_check()
	var/mob/M = loc
	if(!istype(M))
		return FALSE //not equipped

	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_BACK) == src)
		return TRUE
	if(HAS_TAG(src, TAG_WEAR_BACK) && M.get_equipped_item(SLOT_ID_SUIT_STORAGE) == src)
		return TRUE
	return FALSE

/obj/item/medigun_backpack/dropped(mob/user, equipping, slot)
	..()
	replace_icon()

/obj/item/medigun_backpack/proc/checked_use(charge_amt)
	return (bcell && bcell.checked_use(charge_amt))

/obj/item/medigun_backpack/ownership()
	. = ..()
	. += owns(nameof(ccell), policy = OWN_CONTAINED)
	. += owns(nameof(sbin), policy = OWN_CONTAINED, starts = nameof(sbin))
