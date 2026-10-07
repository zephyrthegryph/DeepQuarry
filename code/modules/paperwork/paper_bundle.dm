/obj/item/paper_bundle
	name = "paper bundle"
	gender = NEUTER
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "paper"
	item_state = "paper"
	throwforce = 0
	w_class = ITEMSIZE_SMALL
	throw_range = 2
	throw_speed = 1
	plane = MOB_PLANE
	layer = MOB_LAYER
	pressure_resistance = 1
	attack_verb = list("bapped")
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	var/page = 1    // current page
	// ALLOW(instance_list): d: a bundle holds pages
	var/list/pages = list()  // Ordered list of pages as they are to be displayed. Can be different order than src.contents.


/// Old attackby.
/obj/item/paper_bundle/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)

	if (istype(W, /obj/item/paper/carbon))
		var/obj/item/paper/carbon/C = W
		if (!C.iscopy && !C.copied)
			to_chat(user, span_notice("Take off the carbon copy first."))
			add_fingerprint(user)
			return INTERACTION_HANDLED_PASS
	// adding sheets
	if(istype(W, /obj/item/paper) || istype(W, /obj/item/photo))
		insert_sheet_at(user, length(pages)+1, W)

	// burning
	else if(istype(W, /obj/item/flame))
		burnpaper(W, user)

	// merging bundles
	else if(istype(W, /obj/item/paper_bundle))
		user.drop_from_inventory(W)
		for(var/obj/O in W)
			O.forceMove(src)
			O.add_fingerprint(user)
			rel_add(src, nameof(pages), O)

		to_chat(user, span_notice("You add \the [W.name] to [(src.name == "paper bundle") ? "the paper bundle" : src.name]."))
		consume(W, user)
	else
		if(istype(W, /obj/item/tape_roll))
			return INTERACTION_HANDLED_PASS
		if(istype(W, /obj/item/pen))
			// legacy close (TGUI handles paper_bundle now)
			SStgui.close_uis(src)
		var/obj/P = pages[page]
		P.attackby(W, user)

	update_icon()
	attack_self(user) //Update the browsed page.
	add_fingerprint(user)
	return INTERACTION_HANDLED_PASS

/obj/item/paper_bundle/proc/insert_sheet_at(mob/user, index, obj/item/sheet)
	if(!own_bring_in(src, nameof(pages), sheet, null, user, TRUE, null, FALSE))
		return
	if(istype(sheet, /obj/item/paper))
		to_chat(user, span_notice("You add [(sheet.name == "paper") ? "the paper" : sheet.name] to [(src.name == "paper bundle") ? "the paper bundle" : src.name]."))
	else if(istype(sheet, /obj/item/photo))
		to_chat(user, span_notice("You add [(sheet.name == "photo") ? "the photo" : sheet.name] to [(src.name == "paper bundle") ? "the paper bundle" : src.name]."))


	// pages is an ordered relation list: rebuild it in the new order through the accessors.
	var/list/ordered = pages ? pages.Copy() : list()
	ordered.Insert(clamp(index, 1, length(ordered) + 1), sheet)
	rel_clear(src, nameof(pages))
	for(var/obj/item/ordered_sheet as anything in ordered)
		rel_add(src, nameof(pages), ordered_sheet)

	if(index <= page)
		page++

/obj/item/paper_bundle/proc/burnpaper(obj/item/flame/P, mob/user)
	var/class = "warning"

	if(P.lit && !user.restrained())
		if(istype(P, /obj/item/flame/lighter/zippo))
			class = "rose>"
		act_message(user, src, MSG_SELF("<span class='[class]'>You hold %I% up to %T%, burning it slowly.</span>"), \
			MSG_OTHERS("<span class='[class]'>%U% holds %I% up to %T%, it looks like %THEYRE% trying to burn it!</span>"), \
			item = P)

		after(src, 2 SECONDS, PROC_REF(burn_through), with = list(user, P, class), keeps_dead = TRUE)

/obj/item/paper_bundle/examine(mob/user)
	. = ..()
	if(Adjacent(user))
		show_content(user)
	else
		. += span_notice("It is too far away.")

// TGUI migration. attack_self opens PaperBundle.tsx;
// Topic page-flip and remove move to tgui_act. Photo image embedding via
// browse_rsc is not yet wired through TGUI assets; photo pages show name
// + scribble only.
/obj/item/paper_bundle/proc/show_content(mob/user)
	tgui_interact(user)

DECLARE_INTERACTIONS(/obj/item/paper_bundle, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
	INTERACT_VERB("Rename bundle", PROC_REF(paper_bundle_verb_rename), REQ_IN_INVENTORY), \
	INTERACT_VERB("Loose bundle", PROC_REF(paper_bundle_verb_loosen), REQ_IN_INVENTORY), \
)

/// Old attack_self.
/obj/item/paper_bundle/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	update_icon()
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/item/paper_bundle)
	interface("PaperBundle")
	without("ui_open")
	op("next_page", ui_act("next_page"), then(PROC_REF(ui_act_next_page)))
	op("prev_page", ui_act("prev_page"), then(PROC_REF(ui_act_prev_page)))
	op("remove", ui_act("remove"), then(PROC_REF(ui_act_remove)))

/obj/item/paper_bundle/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["page"] = page
	var/list/merged_1 = ui_data_obj_item_paper_bundle(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/paper_bundle's window data.
/obj/item/paper_bundle/proc/ui_data_obj_item_paper_bundle(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	data["total_pages"] = length(pages)
	data["scribble"] = ""
	if(length(pages))
		var/obj/item/W = pages[page]
		data["page_name"] = W.name
		if(istype(W, /obj/item/paper))
			var/obj/item/paper/P = W
			data["page_kind"] = "paper"
			var/info = (ishuman(user) || isobserver(user) || issilicon(user)) ? P.info : stars(P.info)
			data["page_info"] = "[info][P.stamps]"
		else if(istype(W, /obj/item/photo))
			var/obj/item/photo/P = W
			data["page_kind"] = "photo"
			data["page_info"] = ""
			data["scribble"] = P.scribble || ""
		else
			data["page_kind"] = "paper"
			data["page_info"] = ""
	else
		data["page_name"] = name
		data["page_kind"] = "paper"
		data["page_info"] = ""
	return data

/obj/item/paper_bundle/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(!((src?.loc == user) || (istype(src.loc, /obj/item/folder) && (src.loc.loc == user))))
		to_chat(user, span_notice("You need to hold it in hands!"))
		return FALSE
	user.set_machine(src)
	return TRUE

/obj/item/paper_bundle/proc/ui_act_next_page(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/in_hand = user.get_active_hand()
	if(in_hand && (istype(in_hand, /obj/item/paper) || istype(in_hand, /obj/item/photo)))
		insert_sheet_at(user, page + 1, in_hand)
	else if(page != length(pages))
		page++
		play_sfx(src, SFX_PAGETURN)
	return TRUE

/obj/item/paper_bundle/proc/ui_act_prev_page(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/in_hand = user.get_active_hand()
	if(in_hand && (istype(in_hand, /obj/item/paper) || istype(in_hand, /obj/item/photo)))
		insert_sheet_at(user, page, in_hand)
	else if(page > 1)
		page--
		play_sfx(src, SFX_PAGETURN)
	return TRUE

/obj/item/paper_bundle/proc/ui_act_remove(datum/act/op/A)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	if(!length(pages))
		return TRUE
	var/obj/item/W = pages[page]
	user.put_in_hands(W)
	rel_remove(src, nameof(pages), pages[page])
	to_chat(user, span_notice("You remove the [W.name] from the bundle."))
	if(length(pages) <= 1)
		var/obj/item/paper/P = pages[1]
		user.drop_from_inventory(src)
		user.put_in_hands(P)
		spent(src)
		return TRUE
	if(page > length(pages))
		page = length(pages)
	update_icon()
	return TRUE

/// Old Rename bundle verb.
/obj/item/paper_bundle/proc/paper_bundle_verb_rename(mob/user, obj/item/held, datum/interaction/interaction)
	return paper_bundle_label_stage(user, held, interaction)

/obj/item/paper_bundle/proc/paper_bundle_label_stage(mob/user, obj/item/held, datum/interaction/interaction, paper_answer, paper_answer_ready = FALSE)
	if(!paper_answer_ready)
		open_request(src, /datum/prompt/text/paper_rename_review, PROC_REF(paper_bundle_label_answered), answerer = user, paper_operator = user, paper_held = held, paper_interaction = interaction, question = "What would you like to label the bundle?", title = "Bundle Labelling", max_len = MAX_NAME_LEN, encode = FALSE, name_text = TRUE)
		return
	var/_answer_k189 = paper_answer
	if(isnull(_answer_k189))
		return
	var/n_name = sanitizeSafe(_answer_k189, MAX_NAME_LEN)
	if((loc == user || loc.loc && loc.loc == user) && user.stat == 0)
		name = "[(n_name ? text("[n_name]") : "paper")]"
	add_fingerprint(user)
	return


/// Old Loose bundle verb.
/obj/item/paper_bundle/proc/paper_bundle_verb_loosen(mob/user, obj/item/held, datum/interaction/interaction)
	to_chat(user, span_notice("You loosen the bundle."))
	for(var/obj/O in contents_of(src))
		O.forceMove(user.loc)
		O.layer = initial(O.layer)
		O.add_fingerprint(user)
	consume(src, user)
	return


DECLARE_APPEARANCE_PROC(/obj/item/paper_bundle, TYPE_PROC_REF(/atom, appearance_overlays), list())
/obj/item/paper_bundle/appearance_overlays()
	. = list()
	var/obj/item/paper/P = pages[1]
	icon_state = P.icon_state
	. += P.overlays
	underlays = 0
	var/i = 0
	var/photo
	for(var/obj/O in contents_of(src))
		var/image/img = image('icons/obj/bureaucracy.dmi')
		if(istype(O, /obj/item/paper))
			img.icon_state = O.icon_state
			img.pixel_x -= min(1*i, 2)
			img.pixel_y -= min(1*i, 2)
			pixel_x = min(0.5*i, 1)
			pixel_y = min(  1*i, 2)
			underlays += img
			i++
		else if(istype(O, /obj/item/photo))
			var/obj/item/photo/Ph = O
			img = Ph.tiny
			photo = 1
			. += img
	if(i>1)
		desc =  "[i] papers clipped to each other."
	else
		desc = "A single sheet of paper."
	if(photo)
		desc += "\nThere is a photo attached to it."
	. += image('icons/obj/bureaucracy.dmi', "clip")
	return .

/obj/item/paper_bundle/proc/burn_through(mob/user, obj/item/flame/P, class)
	if(user && P && get_dist(src, user) < 2 && user.get_active_hand() == P && P.lit)
		act_message(user, src, MSG_SELF("<span class='[class]'>You burn right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.</span>"), \
			MSG_OTHERS("<span class='[class]'>%U% burns right through %T%, turning it to ash. It flutters through the air before settling on the floor in a heap.</span>"))

		if(user.get_inactive_hand() == src)
			user.drop_from_inventory(src)

		replace_with(src, /obj/effect/decal/cleanable/ash)

	else
		to_chat(user, span_red("You must hold \the [P] steady to burn \the [src]."))

/obj/item/paper_bundle/proc/paper_bundle_label_answered(datum/act/request/A)
	if(!A.answer)
		return
	. = paper_bundle_label_apply(A)
	SStgui.update_uis(src)

/obj/item/paper_bundle/proc/paper_bundle_label_apply(datum/act/request/A)
	var/datum/prompt/text/paper_rename_review/ask = A.answer
	return paper_bundle_label_stage(ask.paper_operator, ask.paper_held, ask.paper_interaction, ask.value, TRUE)
