/obj/machinery/item_bank
	name = "electronic lockbox"
	desc = "A place to store things you might want later!"
	icon = 'icons/obj/stationobjs.dmi'
	icon_state = "item_bank"
	idle_power_usage = 1
	active_power_usage = 5
	anchored = TRUE
	density = FALSE
	var/busy_bank = FALSE
	var/static/list/item_takers = list()

/obj/machinery/item_bank/proc/persist_item_savefile_path(mob/user)
	return "data/player_saves/[copytext(user.ckey, 1, 2)]/[user.ckey]/persist_item.sav"

/obj/machinery/item_bank/proc/persist_item_savefile_save(mob/user, obj/item/O)
	if(IsGuestKey(user.key))
		return 0

	var/savefile/F = new /savefile(src.persist_item_savefile_path(user))

	F["persist item"] << O.type
	F["persist name"] << initial(O.name)

	return 1

/obj/machinery/item_bank/proc/persist_item_savefile_load(mob/user, thing)
	if (IsGuestKey(user.key))
		return 0

	var/path = src.persist_item_savefile_path(user)

	if (!fexists(path))
		return 0

	var/savefile/F = new /savefile(path)

	if(!F) return 0

	var/persist_item
	F["persist item"] >> persist_item

	if (isnull(persist_item) || !ispath(persist_item))
		fdel(path)
		tgui_alert_async(user, "An item could not be retrieved.")
		return 0
	if(thing == "type")
		return persist_item
	if(thing == "name")
		var/persist_name
		F["persist name"] >> persist_name
		return persist_name


/obj/machinery/item_bank/declare_interactions(list/into)
	into += list(
		/datum/interaction/machine_hand/ungated/item_bank_use,
		/datum/interaction/machine_item/item_bank_store,
	)
	..()

/**
 * Old attack_hand: `. = ..()` but never checked `.` before continuing, so the gate never
 * actually stopped it; approximated here as ungated with its own !operable()/panel_open
 * checks, which is what the gate would otherwise have caught. Any message or side effect
 * the base gated attack_hand used to produce is no longer shown; note in the I7 report.
 */
/datum/interaction/machine_hand/ungated/item_bank_use
	id = "item_bank_use"
	name = "Use"
	effect = /obj/machinery/item_bank/proc/interaction_use

/obj/machinery/item_bank/proc/interaction_use(mob/living/user, obj/item/held, datum/interaction/interaction)
	if(!ishuman(user))
		return TRUE
	if(istype(user) && Adjacent(user))
		if(!operable() || panel_open)
			to_chat(user, span_warning("\The [src] seems to be nonfunctional..."))
		else
			start_using(user)
	return TRUE

/// The questions re-run this proc; the bank is only taken (busy) once the retrieval starts.
/obj/machinery/item_bank/proc/start_using(mob/living/user)
	if(!ishuman(user))
		return
	if(busy_bank)
		to_chat(user, span_warning("\The [src] is already in use."))
		return
	var/I = persist_item_savefile_load(user, "type")
	var/Iname = persist_item_savefile_load(user, "name")
	var/choice = rerun_ask(user, "choice", PROC_REF(start_using), args, /datum/om/prompt/choice/alert, message = "What would you like to do [src]?", title = "[src]", choices = list("Check contents", "Retrieve item", "Info", "Cancel"), timeout = 10 SECONDS)
	if(!choice || choice == "Cancel" || !Adjacent(user) || !operable() || panel_open)
		return
	else if(choice == "Check contents" && I)
		to_chat(user, span_notice("\The [src] has \the [Iname] for you!"))
	else if(choice == "Retrieve item" && I)
		if(user.hands_are_full())
			to_chat(user,span_notice("Your hands are full!"))
			return
		if(user.ckey in item_takers)
			to_chat(user, span_warning("You have already taken something out of \the [src] this shift."))
			return
		choice = rerun_ask(user, "retrieve", PROC_REF(start_using), args, /datum/om/prompt/choice/alert, message = "If you remove this item from the bank, it will be unable to be stored again. Do you still want to remove it?", title = "[src]", choices = list("No", "Yes"), timeout = 10 SECONDS)
		if(!choice || choice == "No" || !Adjacent(user) || !operable() || panel_open || busy_bank)
			return
		busy_bank = TRUE
		icon_state = "item_bank_o"
		om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(retrieve_done), done_args = list(user, I), on_fail = PROC_REF(bank_interrupted))
		return
	else if(choice == "Info")
		to_chat(user, span_notice("\The [src] can store a single item for you between shifts! Anything that has been retrieved from the bank cannot be stored again in the same shift. Anyone can withdraw from the bank one time per shift. Some items are not able to be accepted by the bank."))
		return
	else if(!I)
		to_chat(user, span_warning("\The [src] doesn't seem to have anything for you..."))

/obj/machinery/item_bank/proc/bank_interrupted()
	busy_bank = FALSE
	icon_state = "item_bank"

/obj/machinery/item_bank/proc/retrieve_done(mob/living/user, I)
	if(!operable())
		bank_interrupted()
		return
	var/obj/item/N = new I(get_turf(src))
	log_admin("[key_name_admin(user)] retrieved [N] from the item bank.")
	visible_message(span_notice("\The [src] dispenses the [N] to \the [user]."))
	user.put_in_hands(N)
	N.persist_storable = FALSE
	var/path = src.persist_item_savefile_path(user)
	var/savefile/F = new /savefile(src.persist_item_savefile_path(user))
	F["persist item"] << null
	F["persist name"] << null
	fdel(path)
	item_takers += user.ckey
	busy_bank = FALSE
	icon_state = "item_bank"

/// Old attackby: entirely self-contained, never called ..(), so it catches every item.
/datum/interaction/machine_item/item_bank_store
	id = "item_bank_store"
	name = "Store"
	category = INTERACTION_CAT_INSERT
	held_type = /obj/item
	effect = /obj/machinery/item_bank/proc/interaction_store

/obj/machinery/item_bank/proc/store_done(mob/living/user, obj/item/O)
	if(!operable())
		bank_interrupted()
		return
	src.persist_item_savefile_save(user, O)
	user.visible_message(span_notice("\The [user] stores \the [O] in \the [src]."),span_notice("You stored \the [O] in \the [src]."))
	log_admin("[key_name_admin(user)] stored [O] in the item bank.")
	consume(O, user)
	busy_bank = FALSE
	icon_state = "item_bank"

/obj/machinery/item_bank/proc/interaction_store(mob/living/user, obj/item/O, datum/interaction/interaction)
	if(!ishuman(user))
		return TRUE
	if(busy_bank)
		to_chat(user, span_warning("\The [src] is already in use."))
		return TRUE
	var/I = persist_item_savefile_load(user, "type")
	if(!istool(O) && O.persist_storable)
		if(ispath(I))
			to_chat(user, span_warning("You cannot store \the [O]. You already have something stored."))
			return TRUE
		var/choice = rerun_ask(user, "store", PROC_REF(interaction_store), args, /datum/om/prompt/choice/alert, message = "If you store \the [O], anything it contains may be lost to \the [src]. Are you sure?", title = "[src]", choices = list("Store", "Cancel"), timeout = 10 SECONDS)
		if(!choice || choice == "Cancel" || !Adjacent(user) || !operable() || panel_open || busy_bank || O.loc != user)
			return TRUE
		for(var/obj/item/check in contents_of(O))
			if(!check.persist_storable || check?.tether_host())
				to_chat(user, span_warning("\The [src] buzzes. \The [O] contains [check], which cannot be stored. Please remove this item before attempting to store \the [O]. As a reminder, any contents of \the [O] will be lost if you store it with contents."))
				return TRUE
		busy_bank = TRUE
		user.visible_message(span_notice("\The [user] begins storing \the [O] in \the [src]."),span_notice("You begin storing \the [O] in \the [src]."))
		icon_state = "item_bank_o"
		om_task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(store_done), done_args = list(user, O), on_fail = PROC_REF(bank_interrupted))
		return TRUE
	else
		to_chat(user, span_warning("You cannot store \the [O]. \The [src] either does not accept that, or it has already been retrieved from storage this shift."))
	return TRUE

/////STORABLE ITEMS AND ALL THAT JAZZ/////
//I am only really intending this to be used for single items. Mostly stuff you got right now, but can't/don't want to use right now.
//It is not at all intended to be a thing that just lets you hold on to stuff forever, but just until it's the right time to use it.
/////LIST OF STUFF WE DON'T WANT PEOPLE STORING/////

/obj/item/pda
	persist_storable = FALSE
/obj/item/communicator
	persist_storable = FALSE
/obj/item/card
	persist_storable = FALSE
/obj/item/holder
	persist_storable = FALSE
/obj/item/radio
	persist_storable = FALSE
/obj/item/encryptionkey
	persist_storable = FALSE
/obj/item/storage			//There are lots of things that have stuff that we may not want people to just have. And this is mostly intended for a single thing.
	persist_storable = FALSE		//And it would be annoying to go through and consider all of them, so default to disabled.
/obj/item/storage/backpack	//But we can enable some where it makes sense. Backpacks and their variants basically never start with anything in them, as an example.
	persist_storable = TRUE
/obj/item/reagent_containers/hypospray/vial
	persist_storable = FALSE
/obj/item/cmo_disk_holder
	persist_storable = FALSE
/obj/item/defib_kit/compact/combat
	persist_storable = FALSE
/obj/item/clothing/glasses/welding/superior
	persist_storable = FALSE
/obj/item/clothing/shoes/magboots/adv
	persist_storable = FALSE
/obj/item/rig
	persist_storable = FALSE
/obj/item/clothing/head/helmet/space/void
	persist_storable = FALSE
/obj/item/clothing/suit/space/void
	persist_storable = FALSE
/obj/item/grab
	persist_storable = FALSE
/obj/item/grenade
	persist_storable = FALSE
/obj/item/hand_tele
	persist_storable = FALSE
/obj/item/paper
	persist_storable = FALSE
/obj/item/backup_implanter
	persist_storable = FALSE
/obj/item/disk/nuclear
	persist_storable = FALSE
/obj/item/gun/energy/locked		//These are guns with security measures on them, so let's say the box won't let you put them in there.
	persist_storable = FALSE			//(otherwise explo will just put their locker/vendor guns into it every round)
/obj/item/retail_scanner
	persist_storable = FALSE
/obj/item/telecube
	persist_storable = FALSE
/obj/item/reagent_containers/glass/bottle/adminordrazine
	persist_storable = FALSE
/obj/item/gun/energy/sizegun/admin
	persist_storable = FALSE
/obj/item/stack
	persist_storable = FALSE
/obj/item/book
	persist_storable = FALSE
/obj/item/melee/cursedblade
	persist_storable = FALSE
/obj/item/circuitboard/mecha/imperion
	persist_storable = FALSE
/obj/item/paicard
	persist_storable = FALSE
/obj/item/organ
	persist_storable = FALSE
/obj/item/soulstone
	persist_storable = FALSE
/obj/item/aicard
	persist_storable = FALSE
/obj/item/mmi
	persist_storable = FALSE
/obj/item/seeds
	persist_storable = FALSE
/obj/item/reagent_containers/food/snacks/grown
	persist_storable = FALSE
/obj/item/stock_parts
	persist_storable = FALSE
/obj/item/rcd
	persist_storable = FALSE
/obj/item/spacecash
	persist_storable = FALSE
/obj/item/spacecasinocash
	persist_storable = FALSE
/obj/item/personal_shield_generator
	persist_storable = FALSE
