/obj/machinery/smartfridge/tcrystal
	name = "Telecrystal storage"
	desc = "Some kind of storage machine that only accepts telecrystals"
	icon_state = "donkvendor"
	icon_base = "donkvendor"
	icon_contents = null
	icon = 'icons/obj/survival_pod_vend.dmi'
	light_range = 5
	light_power = 1.2
	light_color = "#DDFFD3"
	pixel_y = -4
	max_n_of_items = 1000000

/obj/machinery/smartfridge/tcrystal/accept_check(obj/item/O)
	return istype(O,/obj/item/stack/telecrystal)

/obj/machinery/smartfridge/tcrystal/proc/mod_amount(datum/stored_item/I,mod)
	if(I.amount + mod <= 0)
		own_take_member(src, nameof(item_records), I)
		spent(I)
	else
		I.set_amount(I.amount + (mod))

/obj/machinery/smartfridge/tcrystal/stock(obj/item/stack/telecrystal/O)
	var/hasRecord = FALSE	//Check to see if this passes or not.
	for(var/datum/stored_item/I in item_records)
		if((O.type == I.item_path) && (O.name == I.item_name))
			mod_amount(I,O.get_amount())
			hasRecord = TRUE
			consumed(O, src)
			break
	if(!hasRecord)
		var/datum/stored_item/item = new/datum/stored_item(src,O.type,O.name,O.get_amount())
		rel_add(src, nameof(item_records), item)
		consume(O)

/// Release (the fridge's op, its question included): the fridge's own Release runs first, as the old parent-first tgui_act() did; when it refuses,
/// the crystals' own release takes the same amount.
/obj/machinery/smartfridge/tcrystal/ui_act_release(datum/act/op/A, amount, index)
	. = ..()
	if(.)
		return
	if(!amount)
		amount = A.step_value("amount")
	if(amount)
		release_crystals(A.actor, amount, index)
	return TRUE

/obj/machinery/smartfridge/tcrystal/proc/release_crystals(mob/user, amount, index_param)
	if(QDELETED(src) || QDELETED(user) || !user.Adjacent(src))
		return FALSE

	if(!isnum(amount) || amount <= 0 || amount != round(amount))
		return FALSE
	var/index = isnum(index_param) ? index_param : text2num(index_param)
	if(!isnum(index) || index < 1 || index != round(index) || index > LAZYLEN(item_records))
		return FALSE
	var/datum/stored_item/I = item_records[index]
	if(!I)
		return FALSE
	var/count = I.get_amount()

	// Sanity check, there are probably ways to press the button when it shouldn't be possible.
	if(count > 0)
		if((count - amount) < 0)
			amount = count
		mod_amount(I,-amount)
		var/crystal_amount = min(240,amount)
		while(crystal_amount > 0)
			new /obj/item/stack/telecrystal(loc,crystal_amount)
			amount -= crystal_amount
			crystal_amount = min(240,amount)

	return TRUE

/datum/stored_item/telecrystals
	item_name = "Telecrystals"

/datum/stored_item/telecrystals/get_amount()
	return amount

/obj/tcspawner
	name = "Telecrystal spawner"
	desc = "This item spawns stack of 5 telecrystals"
	icon = 'icons/misc/mark.dmi'
	icon_state = "x4"
	var/amount_to_spawn = 5

CAPABILITIES(/obj/tcspawner)
	map_resolver(GLOBAL_PROC_REF(resolve_tcspawner), vars = list("amount_to_spawn"))

/// The map resolver of telecrystal spawners: one stack, inside the closet on the tile if there is one.
/proc/resolve_tcspawner(atom/loc, path, list/varedits)
	var/obj/tcspawner/P = path
	var/turf/T = get_turf(loc)
	var/obj/item/stack/telecrystal/M = new (T, MAP_VAR(P, varedits, amount_to_spawn))
	var/obj/structure/closet/C = locate_on(T, /obj/structure/closet)
	if(C)
		M.forceMove(C)
	return TRUE

/obj/tcspawner/stack5
	desc = "This item spawns stack of 5 telecrystals"
	amount_to_spawn = 5

/obj/tcspawner/stack10
	desc = "This item spawns stack of 10 telecrystals"
	amount_to_spawn = 10

/obj/tcspawner/stack15
	desc = "This item spawns stack of 15 telecrystals"
	amount_to_spawn = 15

/obj/tcspawner/stack20
	desc = "This item spawns stack of 20 telecrystals"
	amount_to_spawn = 20

/obj/tcspawner/stack25
	desc = "This item spawns stack of 25 telecrystals"
	amount_to_spawn = 25

/obj/tcspawner/stack50
	desc = "This item spawns stack of 50 telecrystals"
	amount_to_spawn = 50

/obj/tcspawner/stack75
	desc = "This item spawns stack of 75 telecrystals"
	amount_to_spawn = 75

/obj/tcspawner/stack100
	desc = "This item spawns stack of 100 telecrystals"
	amount_to_spawn = 100

/obj/tcspawner/stack150
	desc = "This item spawns stack of 150 telecrystals"
	amount_to_spawn = 150

/obj/tcspawner/stack200
	desc = "This item spawns stack of 200 telecrystals"
	amount_to_spawn = 200

/obj/tcspawner/stack240
	desc = "This item spawns stack of 240 telecrystals"
	amount_to_spawn = 240
