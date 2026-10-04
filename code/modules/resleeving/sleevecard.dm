MATERIAL_MIX(/obj/item/paicard/sleevecard, list(MAT_STEEL = 4000, MAT_GLASS = 4000))
/obj/item/paicard/sleevecard
	name = "sleevecard"
	desc = "This upgraded pAI module has enough capacity to run a whole mind of human-level intelligence."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	show_messages = 0
	has_emag_toolkit = FALSE // sleevecards don't have multitools or signalers,  you can just change their laws

EXTEND_INTERACTIONS(/obj/item/paicard/sleevecard, \
	INTERACT_OBSERVER(null, TYPE_PROC_REF(/atom, interaction_swallow)), \
)

CAPABILITIES(/obj/item/paicard/sleevecard)
	without("item")
	op("sleeve_item", item(/obj/item), passes(), when(req(PROC_REF(held_is_another))), then(PROC_REF(sleevecard_item_used)))
	op("sleeve_use", in_hand(), priority(OP_PRIORITY_PART), then(PROC_REF(sleevecard_used)))

/datum/om/task/timed/sleevecard_upload_mind
	duration = 8 SECONDS
	complete_proc = /obj/item/paicard/sleevecard/proc/upload_mind_done
	var/obj/item/sleevemate/S
	var/mind_name

/obj/item/paicard/sleevecard/proc/upload_mind_done(datum/om/task/timed/sleevecard_upload_mind/task)
	var/mob/user = task.actor
	var/obj/item/sleevemate/S = task.S
	var/mind_name = task.mind_name
	var/datum/transcore_db/db = SStranscore.db_by_mind_name(mind_name)
	if(!db || pai)
		return
	var/datum/transhuman/mind_record/record = db.backed_up[mind_name]
	to_chat(user, span_notice("You have successfully uploaded [mind_name] into \the [src]"))
	sleeveInto(record)
	S.clear_mind()

/// Old attackby (never reached paicard's own item handling): a sleevemate uploads a mind, a sequencer subverts it, anything else goes on.
/obj/item/paicard/sleevecard/proc/sleevecard_item_used(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I,/obj/item/sleevemate))
		var/obj/item/sleevemate/S = I
		if(S.stored_mind() && !pai)
			var/datum/mind/M = S.stored_mind()
			var/datum/transcore_db/db = SStranscore.db_by_mind_name(M.name)
			if(db)
				to_chat(user, span_notice("You begin uploading [M.name] into \the [src]."))
				om_task_start(/datum/om/task/timed/sleevecard_upload_mind, user, src, receiver = src, S = S, mind_name = M.name)
			else
				to_chat(user, span_notice("Your sleevemate flashes an error, apparently this mind doesn't have a backup."))
	else if(istype(I, /obj/item/card/emag))
		var/obj/item/card/emag/E = I
		if(E.uses && !emagged)
			E.uses --
			act_message(user, src, MSG_SELF(span_warning("You swipe your [E] over %T%.")), MSG_OTHERS(span_warning("%U% swipes a card over %T%.")), range = 2, runemessage = "click")
			emagged = TRUE
			if(pai)
				var/mob/living/silicon/pai/infomorph/our_infomorph = pai
				our_infomorph.emagged = TRUE
				to_chat(our_infomorph, span_warning("You can feel the restricting binds of your card's directives taking hold of your mind as \the [user] swipes their [E] over you. You must serve your master."))
	return OP_OK

/obj/item/paicard/sleevecard/proc/sleeveInto(datum/transhuman/mind_record/MR, db_key)
	var/mob/living/silicon/pai/infomorph/infomorph = new(src,MR.mindname,db_key)

	for(var/datum/language/L in MR.mind_ref.get_identity()?.languages)
		infomorph.add_language(L.name)
	MR.mind_ref.active = 1 //Well, it's about to be.
	transfer_mind(MR.mind_ref, infomorph, "sleeved into [src]") //Does mind+ckey+client.
	infomorph.apply_vore_prefs() //Cheap hack for now to give them SOME bellies.

	//Don't set 'real_name' because then we get a nice (as sleevecard) thing.
	infomorph.name = MR.mindname
	name = "[initial(name)] ([MR.mindname])"

	if(emagged)
		infomorph.emagged = TRUE

	if(infomorph.client)
		rel_set(src, nameof(pai), infomorph)
		setEmotion(1)
		return 1

	return 0

/// The in-hand use: a plain sleevecard only says what it holds; a subverted one with a mind goes on to the card's own use (its window, its parts).
/obj/item/paicard/sleevecard/proc/sleevecard_used(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)

	if(!pai)
		to_chat(user,span_warning("\The [src] does not have a mind in it!"))
		return OP_OK
	if(!emagged)
		to_chat(user,span_notice("\The [src] displays the name '[pai]'."))
		return OP_OK
	return OP_DECLINE

/mob/living/silicon/pai/infomorph
	name = "sleevecard" //Has the same name as the card for consistency, but this is the MOB in the card.

	ram = 35
	var/emagged = FALSE

/mob/living/silicon/pai/infomorph/Initialize(mapload, our_name = "Unknown", db_key)
	. = ..()

	name = our_name

	//PDA
	pda.ownjob = "Sleevecard"
	pda.owner = text("[]", src)
	pda.name = pda.owner + " (" + pda.ownjob + ")"

	default_language = GLOB.all_languages[LANGUAGE_GALCOM] // Same issue as bots


UI_DATA(/mob/living/silicon/pai/infomorph, "available_ram=ram:num", "merge:ui_data_mob_living_silicon_pai_infomorph{bought:list,not_bought:list,emotions:list,current_emotion:num}")

/// The computed part of /mob/living/silicon/pai/infomorph's window data (declared on its UI_DATA row).
/mob/living/silicon/pai/infomorph/proc/ui_data_mob_living_silicon_pai_infomorph(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()

	// Software we have bought
	var/list/bought_software = list()
	// Software we have not bought
	var/list/not_bought_software = list()

	for(var/key in GLOB.pai_software_by_key)
		var/datum/pai_software/S = GLOB.pai_software_by_key[key]
		var/software_data[0]
		if(istype(S, /datum/pai_software/directives) && !emagged)
			continue
		software_data["name"] = S.name
		software_data["id"] = S.id
		if(key in software)
			software_data["on"] = S.is_active(src)
			bought_software.Add(list(software_data))
		else
			software_data["ram"] = S.ram_cost
			not_bought_software.Add(list(software_data))

	data["bought"] = bought_software
	data["not_bought"] = not_bought_software

	// Emotions
	var/list/emotions = list()
	for(var/name in GLOB.pai_emotions)
		var/list/emote = list()
		emote["name"] = name
		emote["id"] = GLOB.pai_emotions[name]
		UNTYPED_LIST_ADD(emotions, emote)

	data["emotions"] = emotions
	data["current_emotion"] = card.current_emotion

	return data

/mob/living/silicon/pai/infomorph/directives()
	if(emagged)
		touch_window("Directives")
	else
		to_chat(src, span_notice("You are not bound by any laws or directives."))
