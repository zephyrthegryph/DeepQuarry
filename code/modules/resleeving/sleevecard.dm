MATERIAL_MIX(/obj/item/paicard/sleevecard, list(MAT_STEEL = 4000, MAT_GLASS = 4000))
/obj/item/paicard/sleevecard
	name = "sleevecard"
	desc = "This upgraded pAI module has enough capacity to run a whole mind of human-level intelligence."
	catalogue_data = list(/datum/category_item/catalogue/technology/resleeving)
	show_messages = 0
	has_emag_toolkit = FALSE // sleevecards don't have multitools or signalers,  you can just change their laws
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/paicard/sleevecard, \
	INTERACT_OBSERVER(null, TYPE_PROC_REF(/atom, interaction_swallow)), \
	INTERACT_ITEM(null, PROC_REF(sleevecard_interaction_item)), \
)

/datum/task/timed/sleevecard_upload_mind
	duration = 8 SECONDS
	complete_proc = /obj/item/paicard/sleevecard/proc/upload_mind_done
	var/obj/item/sleevemate/S
	var/mind_name

/obj/item/paicard/sleevecard/proc/upload_mind_done(datum/task/timed/sleevecard_upload_mind/task)
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

/// Old attackby (never reached paicard's own item handling).
/obj/item/paicard/sleevecard/proc/sleevecard_interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	. = INTERACTION_HANDLED_PASS
	if(istype(I,/obj/item/sleevemate))
		var/obj/item/sleevemate/S = I
		if(S.stored_mind() && !pai)
			var/datum/mind/M = S.stored_mind()
			var/datum/transcore_db/db = SStranscore.db_by_mind_name(M.name)
			if(db)
				to_chat(user, span_notice("You begin uploading [M.name] into \the [src]."))
				task_start(/datum/task/timed/sleevecard_upload_mind, user, src, receiver = src, S = S, mind_name = M.name)
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

/obj/item/paicard/sleevecard/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)

	if(!pai)
		to_chat(user,span_warning("\The [src] does not have a mind in it!"))
	else
		if(!emagged)
			to_chat(user,span_notice("\The [src] displays the name '[pai]'."))
		else ..(user, TRUE)

/mob/living/silicon/pai/infomorph
	name = "sleevecard" //Has the same name as the card for consistency, but this is the MOB in the card.

	ram = 35
	var/emagged = FALSE

CAPABILITIES(/mob/living/silicon/pai/infomorph)
	param(nameof(name), pos = 1, default = "Unknown")

// ALLOW(init/INSTANCE_STATE): an infomorph names its PDA after itself and speaks Galactic Common
/mob/living/silicon/pai/infomorph/Initialize(mapload)
	. = ..()

	//PDA
	pda.ownjob = "Sleevecard"
	pda.owner = text("[]", src)
	pda.name = pda.owner + " (" + pda.ownjob + ")"

	default_language = GLOB.all_languages[LANGUAGE_GALCOM] // Same issue as bots


/mob/living/silicon/pai/infomorph/ui_data(datum/act/eval/A)
	var/list/data = ..()
	data["available_ram"] = ram
	var/list/merged_1 = ui_data_mob_living_silicon_pai_infomorph(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /mob/living/silicon/pai/infomorph's window data.
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
