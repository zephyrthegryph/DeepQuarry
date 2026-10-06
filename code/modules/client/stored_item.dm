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

TRACKED(/obj/machinery/item_bank, busy_bank)

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

CAPABILITIES(/obj/machinery/item_bank)
	op("use", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_use)))
	op("store", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Store"), needs(req(PROC_REF(can_store_holds), because = PROC_REF(can_store_refusal))), then(PROC_REF(interaction_store)))

/// Requirement (was REQ_* can_store): the legacy check answers TRUE to pass.
/obj/machinery/item_bank/proc/can_store_holds(datum/act/op/A)
	var/answer = can_store(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_store_holds refuses: the legacy check's text, else the clause's own reason.
/obj/machinery/item_bank/proc/can_store_refusal(datum/act/op/A)
	var/answer = can_store(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/**
 * Old attack_hand: `. = ..()` but never checked `.` before continuing, so the gate never
 * actually stopped it; approximated here as ungated with its own !operable()/panel_open
 * checks, which is what the gate would otherwise have caught. Any message or side effect
 * the base gated attack_hand used to produce is no longer shown; note in the I7 report.
 */
/obj/machinery/item_bank/proc/interaction_use(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!ishuman(user))
		return OP_OK
	if(istype(user) && Adjacent(user))
		if(!operable() || panel_open)
			to_chat(user, span_warning("\The [src] seems to be nonfunctional..."))
		else
			start_using(user)
	return OP_OK

/// The questions re-run this proc; the bank is only taken (busy) once the retrieval starts.
/obj/machinery/item_bank/proc/start_using(mob/living/user)
	return retrieval_stage(user, list())

/obj/machinery/item_bank/proc/retrieval_stage(mob/living/user, list/retrieval_answers)
	if(!ishuman(user))
		return
	if(busy_bank)
		to_chat(user, span_warning("\The [src] is already in use."))
		return
	var/I = persist_item_savefile_load(user, "type")
	var/Iname = persist_item_savefile_load(user, "name")
	var/choice = retrieval_answers["choice"]
	if(isnull(choice))
		open_request(src, /datum/prompt/choice/item_bank_retrieval, PROC_REF(retrieval_answered), answerer = user, captured = retrieval_answers.Copy(), step_name = "choice", question = "What would you like to do [src]?", title = "[src]", choices = list("Check contents", "Retrieve item", "Info", "Cancel"))
		return
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
		choice = retrieval_answers["retrieve"]
		if(isnull(choice))
			open_request(src, /datum/prompt/choice/item_bank_retrieval, PROC_REF(retrieval_answered), answerer = user, captured = retrieval_answers.Copy(), step_name = "retrieve", question = "If you remove this item from the bank, it will be unable to be stored again. Do you still want to remove it?", title = "[src]", choices = list("No", "Yes"))
			return
		if(!choice || choice == "No" || !Adjacent(user) || !operable() || panel_open || busy_bank)
			return
		set_busy_bank(TRUE)
		icon_state = "item_bank_o"
		task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(retrieve_done), done_args = list(user, I), on_fail = PROC_REF(bank_interrupted))
		return
	else if(choice == "Info")
		to_chat(user, span_notice("\The [src] can store a single item for you between shifts! Anything that has been retrieved from the bank cannot be stored again in the same shift. Anyone can withdraw from the bank one time per shift. Some items are not able to be accepted by the bank."))
		return
	else if(!I)
		to_chat(user, span_warning("\The [src] doesn't seem to have anything for you..."))

/// Only the retrieval caller's two scalar answers are retained across its questions.
/datum/prompt/choice/item_bank_retrieval
	buttons = TRUE
	timeout = 10 SECONDS
	recheck_on_open = TRUE

/datum/prompt/choice/item_bank_retrieval/normalize(given)
	return given

/datum/prompt/choice/item_bank_retrieval/refusal(given)
	return null

/datum/prompt/choice/item_bank_retrieval/recheck_extra()
	if(!owner || QDELETED(owner) || !answerer || QDELETED(answerer))
		return "gone"
	return null

/obj/machinery/item_bank/proc/retrieval_answered(datum/act/request/A)
	if(!A || !A.answer || A.answer != A.request)
		return
	var/datum/prompt/choice/item_bank_retrieval/completed = A.request
	if(!istype(completed) || completed.owner != src || !istype(completed.answerer, /mob/living) || QDELETED(completed.answerer) || completed.handler != PROC_REF(retrieval_answered) || completed.is_open() || completed.outcome != REQ_ANSWERED || QDELETED(completed) || isnull(completed.value) || !islist(completed.captured))
		return
	if(completed.step_name == "choice")
		if(length(completed.captured))
			return
	else if(completed.step_name == "retrieve")
		if(length(completed.captured) != 1 || completed.captured["choice"] != "Retrieve item")
			return
	else
		return
	var/list/retrieval_answers = completed.captured.Copy()
	retrieval_answers[completed.step_name] = completed.value
	SStgui.update_uis(src)
	world.push_usr(completed.answerer, new /datum/callback(src, PROC_REF(retrieval_stage)), completed.answerer, retrieval_answers)

/obj/machinery/item_bank/proc/bank_interrupted()
	set_busy_bank(FALSE)
	icon_state = "item_bank"

/obj/machinery/item_bank/proc/retrieve_done(mob/living/user, I)
	if(!operable())
		bank_interrupted()
		return
	var/obj/item/N = new I(get_turf(src))
	log_admin("[key_name_admin(user)] retrieved [N] from the item bank.")
	act_message(src, user, others = span_notice("%U% dispenses the [N] to %T%."))
	user.put_in_hands(N)
	N.persist_storable = FALSE
	var/path = src.persist_item_savefile_path(user)
	var/savefile/F = new /savefile(src.persist_item_savefile_path(user))
	F["persist item"] << null
	F["persist name"] << null
	fdel(path)
	item_takers += user.ckey
	set_busy_bank(FALSE)
	icon_state = "item_bank"

/// Requirement: TRUE, or why nothing can be stored right now (a non-human is refused silently by the effect).
/obj/machinery/item_bank/proc/can_store(mob/living/user, atom/target, obj/item/held)
	if(!ishuman(user))
		return TRUE
	if(busy_bank)
		return "\The [src] is already in use"
	return TRUE

/obj/machinery/item_bank/proc/store_done(mob/living/user, obj/item/O)
	if(!operable())
		bank_interrupted()
		return
	src.persist_item_savefile_save(user, O)
	act_message(user, src, MSG_SELF(span_notice("You stored %I% in %T%.")), MSG_OTHERS(span_notice("%U% stores %I% in %T%.")), item = O)
	log_admin("[key_name_admin(user)] stored [O] in the item bank.")
	consume(O, user)
	set_busy_bank(FALSE)
	icon_state = "item_bank"

/obj/machinery/item_bank/proc/interaction_store(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/O = A.held
	if(!ishuman(user))
		return OP_OK
	if(busy_bank) // re-entered after the confirm prompt (rerun_ask): the bank may have been claimed meanwhile
		return OP_OK
	var/I = persist_item_savefile_load(user, "type")
	if(!istool(O) && O.persist_storable)
		if(ispath(I))
			to_chat(user, span_warning("You cannot store \the [O]. You already have something stored."))
			return OP_OK
		var/choice = rerun_ask(user, "store", PROC_REF(interaction_store), args, /datum/prompt/choice, question = "If you store \the [O], anything it contains may be lost to \the [src]. Are you sure?", title = "[src]", choices = list("Store", "Cancel"), timeout = 10 SECONDS, buttons = TRUE)
		if(!choice || choice == "Cancel" || !Adjacent(user) || !operable() || panel_open || busy_bank || O.loc != user)
			return OP_OK
		for(var/obj/item/check in contents_of(O))
			if(!check.persist_storable || check?.tether_host())
				to_chat(user, span_warning("\The [src] buzzes. \The [O] contains [check], which cannot be stored. Please remove this item before attempting to store \the [O]. As a reminder, any contents of \the [O] will be lost if you store it with contents."))
				return OP_OK
		set_busy_bank(TRUE)
		act_message(user, src, MSG_SELF(span_notice("You begin storing %I% in %T%.")), MSG_OTHERS(span_notice("%U% begins storing %I% in %T%.")), item = O)
		icon_state = "item_bank_o"
		task_timed(user, 10 SECONDS, target = src, receiver = src, on_done = PROC_REF(store_done), done_args = list(user, O), on_fail = PROC_REF(bank_interrupted))
		return OP_OK
	else
		to_chat(user, span_warning("You cannot store \the [O]. \The [src] either does not accept that, or it has already been retrieved from storage this shift."))
	return OP_OK

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
