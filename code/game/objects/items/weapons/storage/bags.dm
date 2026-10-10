/*
 *	These absorb the functionality of the plant bag, ore satchel, etc.
 *	They use the use_to_pickup, quick_gather, and quick_empty functions
 *	that were already defined in weapon/storage, but which had been
 *	re-implemented in other classes.
 *
 *	Contains:
 *		Generic non-item
 *		Trash Bag
 *		Plastic Bag
 *		Mining Satchel
 *		Plant Bag
 *		Sheet Snatcher
 *		Sheet Snatcher (Cyborg)
 *		Cash Bag
 *		Chemistry Bag
 *		Food Bag
 *		Food Bag (Service Hound)
 *		Evidence Bag
 *
 *	-Sayu
 */


// -----------------------------
//          Generic non-item
// -----------------------------
/obj/item/storage/bag
	allow_quick_gather = 1
	allow_quick_empty = 1
	display_contents_with_number = 0 // UNStABLE AS FuCK, turn on when it stops crashing clients
	use_to_pickup = TRUE
	slot_flags = SLOT_BELT
	drop_sound = SFX_ITEMS_DROP_BACKPACK
	pickup_sound = SFX_ITEMS_PICKUP_BACKPACK

// -----------------------------
//          Trash bag
// -----------------------------
/obj/item/storage/bag/trash
	name = "trash bag"
	desc = "It's the heavy-duty black polymer kind. Time to take out the trash!"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "trashbag0"
	item_state_slots = list(slot_r_hand_str = "trashbag", slot_l_hand_str = "trashbag")
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	pickup_sound = SFX_ITEMS_PICKUP_WRAPPER

	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_SMALL * 21
	resistance_flags = FLAMMABLE


CAPABILITIES(/obj/item/storage/bag/trash)
	configure(storage(refuses = list(/obj/item/disk/nuclear)))

/obj/item/storage/bag/trash/draw(datum/look/look)
	. = ..()
	var/held = held_count()
	if(held == 0)
		look.state("trashbag0")
	else if(held < 9)
		look.state("trashbag1")
	else if(held < 18)
		look.state("trashbag2")
	else
		look.state("trashbag3")

/obj/item/storage/bag/trash/holding
	name = "trash bag of holding"
	desc = "The latest and greatest in custodial convenience, a trashbag that is capable of holding vast quantities of garbage."
	icon_state = "bluetrashbag"
	max_storage_space = ITEMSIZE_COST_NORMAL * 10 // Slightly less than BoH
	resistance_flags = FIRE_PROOF


CAPABILITIES(/obj/item/storage/bag/trash/holding)
	configure(storage(refuses = list(/obj/item/disk/nuclear), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//        Plastic Bag
// -----------------------------
/obj/item/storage/bag/plasticbag
	name = "plastic bag"
	desc = "It's a very flimsy, very noisy alternative to a bag."
	icon = 'icons/obj/trash.dmi'
	icon_state = "plasticbag"
	drop_sound = SFX_ITEMS_DROP_WRAPPER
	pickup_sound = SFX_ITEMS_PICKUP_WRAPPER

	w_class = ITEMSIZE_LARGE
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/plasticbag)
	configure(storage(refuses = list(/obj/item/disk/nuclear)))

// -----------------------------
//          Plant bag
// -----------------------------

/obj/item/storage/bag/plants
	name = "plant bag"
	icon = 'icons/obj/hydroponics_machines.dmi'
	icon_state = "plantbag"
	desc = "A sturdy bag used to transport fresh produce with ease."
	max_storage_space = ITEMSIZE_COST_NORMAL * 25
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE


CAPABILITIES(/obj/item/storage/bag/plants)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks/grown,
		/obj/item/seeds,
		/obj/item/grown), max_size = ITEMSIZE_NORMAL))

/obj/item/storage/bag/plants/large
	name = "large plant bag"
	icon_state = "large_plantbag"
	desc = "A large and sturdy bag used to transport fresh produce with ease."
	max_storage_space = ITEMSIZE_COST_NORMAL * 50

// -----------------------------
//        Sheet Snatcher
// -----------------------------
// Because it stacks stacks, this doesn't operate normally.
// However, making it a storage/bag allows us to reuse existing code in some places. -Sayu

/obj/item/storage/bag/sheetsnatcher
	name = "sheet snatcher"
	icon = 'icons/obj/mining.dmi'
	icon_state = "sheetsnatcher"
	desc = "A patented storage system designed for any kind of mineral sheet."

	var/capacity = 500 //the number of sheets it can carry.
	w_class = ITEMSIZE_NORMAL
	storage_slots = 7

	allow_quick_empty = 1 // this function is superceded
	resistance_flags = FIRE_PROOF


CAPABILITIES(/obj/item/storage/bag/sheetsnatcher)
	configure(storage(accepts = list(/obj/item/stack/material), max_size = null))

/// Sheets only, counted by the sheet rather than by size or slot.
/datum/relation_definition/slot/storage/sheets
	holder = /obj/item/storage/bag/sheetsnatcher
	capacity_model = SLOT_CAPACITY_NONE

/datum/relation_definition/slot/storage/sheets/refusal(obj/item/storage/bag/sheetsnatcher/holder, atom/movable/thing, mob/actor)
	if(!istype(thing, /obj/item/stack/material))
		return "it only takes sheets"
	. = dq_constraint_refusal(holder, CONSTRAINT_HOLD, thing, actor)
	if(.)
		return .
	if(holder.sheets_held() >= holder.capacity)
		return "the snatcher is full"
	return null

/obj/item/storage/bag/sheetsnatcher/proc/sheets_held()
	. = 0
	for(var/obj/item/stack/material/S in stored_items())
		. += S.get_amount()

/// Sheets merge into a stack of the same type already inside, up to capacity.
/obj/item/storage/bag/sheetsnatcher/insert_item(obj/item/W, mob/user, prevent_warning = FALSE)
	var/obj/item/stack/material/S = W
	if(!istype(S) || insert_refusal(S, user))
		return FALSE
	var/amount = min(S.get_amount(), capacity - sheets_held())
	for(var/obj/item/stack/material/sheet in stored_items())
		if(S.type == sheet.type)
			// we are violating the amount limitation because these are not sane objects
			sheet.set_amount(sheet.get_amount() + amount, TRUE)
			containment_ledger()?.refresh(sheet)
			S.use(amount) // will qdel() if we use it all
			refresh_hud()
			return TRUE
	if(amount < S.get_amount())
		var/obj/item/stack/F = S.split(amount)
		if(!move_into(src, CONTAINER_SLOT_STORAGE, F, user))
			return FALSE
		return TRUE
	return ..()

// Numbered display shows each stack's sheet count.
/obj/item/storage/bag/sheetsnatcher/hud_group_key(obj/item/I)
	return I

/obj/item/storage/bag/sheetsnatcher/hud_group_amount(obj/item/stack/material/I)
	return I.get_amount()

// Quick-empty drops full-size stacks.
/obj/item/storage/bag/sheetsnatcher/drop_contents(mob/user)
	if(user)
		hide_from(user)
	var/location = get_turf(src)
	for(var/obj/item/stack/material/S in stored_items())
		var/cur_amount = S.get_amount()
		var/full_stacks = round(cur_amount / S.max_amount) // Floor of current/max is amount of full stacks we make
		var/remainder = cur_amount % S.max_amount // Current mod max is remainder after full sheets removed
		for(var/i = 1 to full_stacks)
			new S.type(location, S.max_amount)
		if(remainder)
			new S.type(location, remainder)
		spent(S, user)

// Instead of removing
/obj/item/storage/bag/sheetsnatcher/remove_from_storage(obj/item/W, atom/new_location, mob/user)
	var/obj/item/stack/material/S = W
	if(!istype(S)) return 0

	//I would prefer to drop a new stack, but the item/attack_hand code
	// that calls this can't recieve a different object than you clicked on.
	//Therefore, make a new stack internally that has the remainder.
	// -Sayu

	if(S.get_amount() > S.max_amount)
		var/newstack_amt = S.get_amount() - S.max_amount
		new S.type(src, newstack_amt) // The one we'll keep to replace the one we give
		S.set_amount(S.max_amount) // The one we hand to the clicker
		containment_ledger()?.refresh(S)

	return ..()

// -----------------------------
//    Sheet Snatcher (Bluespace)
// -----------------------------

/obj/item/storage/bag/sheetsnatcher/holding
	name = "sheet snatcher of holding"
	icon_state = "sheetsnatcher_bspace"
	desc = "A patented storage system designed for any kind of mineral sheet, this one has been upgraded with bluespace technology to allow it to carry ten times as much."

	capacity = 5000 //Should be far more than enough.

// -----------------------------
//    Sheet Snatcher (Cyborg)
// -----------------------------

/obj/item/storage/bag/sheetsnatcher/borg
	name = "sheet snatcher 9000"
	desc = null
	capacity = 700//Borgs get more because >specialization

/obj/item/storage/bag/sheetsnatcher/borg/proc/upgrade()
	name += " of holding"
	capacity = 5000

// -----------------------------
//           Cash Bag
// -----------------------------

/obj/item/storage/bag/cash
	name = "cash bag"
	icon = 'icons/obj/storage.dmi'
	icon_state = "cashbag"
	desc = "A bag for carrying lots of cash. It's got a big dollar sign printed on the front."
	max_storage_space = ITEMSIZE_COST_NORMAL * 25
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/cash)
	configure(storage(accepts = list(
		/obj/item/coin,
		/obj/item/spacecash,
		/obj/item/spacecasinocash), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//         Chemistry Bag
// -----------------------------

/obj/item/storage/bag/chemistry
	name = "chemistry bag"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "chembag"
	desc = "A bag for storing pills, patches, and bottles."
	max_storage_space = 200
	w_class = ITEMSIZE_LARGE
	slowdown = 1 //you probably shouldn't be running with chemicals
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/chemistry)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/pill,
		/obj/item/reagent_containers/glass/beaker,
		/obj/item/reagent_containers/glass/bottle,
		/obj/item/reagent_containers/hypospray/autoinjector)))

// -----------------------------
//           Xeno Bag
// -----------------------------

/obj/item/storage/bag/xeno
	name = "xenobiology bag"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "xenobag"
	desc = "A bag for storing various slime products."
	max_storage_space = ITEMSIZE_COST_SMALL * 12
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/xeno)
	configure(storage(accepts = list(
		/obj/item/slime_extract,
		/obj/item/slimepotion,
		/obj/item/reagent_containers/food/snacks/monkeycube), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//         Virology Bag
// -----------------------------

/obj/item/storage/bag/virology
	name = "virology bag"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "biobag"
	desc = "A bag for storing various biological products."
	max_storage_space = ITEMSIZE_COST_SMALL * 12
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/virology)
	configure(storage(accepts = list(/obj/item/reagent_containers/glass/beaker/vial), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//           Food Bag
// -----------------------------

/obj/item/storage/bag/food
	name = "food bag"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "foodbag"
	desc = "A bag for storing foods of all kinds."
	max_storage_space = ITEMSIZE_COST_NORMAL * 25
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/food)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks,
		/obj/item/reagent_containers/food/condiment), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//    Food Bag (Service Hound)
// -----------------------------

/obj/item/storage/bag/serviceborg
	name = "service bag"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "foodbag"
	desc = "An intergrated bag for storing things of all kinds."
	max_storage_space = ITEMSIZE_COST_NORMAL * 25
	w_class = ITEMSIZE_SMALL
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/storage/bag/serviceborg)
	configure(storage(accepts = list(
		/obj/item/reagent_containers/food/snacks,
		/obj/item/reagent_containers/food/condiment,
		/obj/item/reagent_containers/glass/beaker,
		/obj/item/reagent_containers/glass/bottle,
		/obj/item/coin,
		/obj/item/spacecash,
		/obj/item/reagent_containers/food/snacks/grown,
		/obj/item/seeds,
		/obj/item/grown,
		/obj/item/reagent_containers/pill), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//           Evidence Bag
// -----------------------------

/obj/item/storage/bag/detective
	name = "secure satchel"
	icon = 'icons/obj/storage_vr.dmi'
	icon_state = "detbag"
	desc = "A bag for storing investigation things. You know, securely."
	max_storage_space = ITEMSIZE_COST_NORMAL * 15
	w_class = ITEMSIZE_SMALL
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/storage/bag/detective)
	configure(storage(accepts = list(
		/obj/item/forensics/swab,
		/obj/item/sample/print,
		/obj/item/sample/fibers,
		/obj/item/evidencebag), max_size = ITEMSIZE_NORMAL))

// -----------------------------
//          Santa bag
// -----------------------------

/obj/item/storage/bag/santabag
	name = "\improper Santa's gift bag"
	desc = "Space Santa uses this to deliver toys to all the nice children in space in Christmas! Wow, it's pretty big!"
	icon = 'icons/obj/storage.dmi'
	icon_state = "giftbag0"
	item_state_slots = list(slot_r_hand_str = "giftbag", slot_l_hand_str = "giftbag")

	w_class = ITEMSIZE_LARGE
	max_storage_space = ITEMSIZE_COST_NORMAL * 100 // can store a ton of shit!
	resistance_flags = FIRE_PROOF //ho ho ho


CAPABILITIES(/obj/item/storage/bag/santabag)
	configure(storage(refuses = list(/obj/item/disk/nuclear), max_size = ITEMSIZE_NORMAL))

/obj/item/storage/bag/santabag/draw(datum/look/look)
	. = ..()
	var/held = held_count()
	if(held < 10)
		look.state("giftbag0")
	else if(held < 25)
		look.state("giftbag1")
	else
		look.state("giftbag2")
