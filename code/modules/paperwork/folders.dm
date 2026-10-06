/obj/item/folder
	name = "folder"
	desc = "A folder."
	icon = 'icons/obj/bureaucracy.dmi' // Continues using new folder sprite, contrary to YW
	icon_state = "folder"
	w_class = ITEMSIZE_SMALL
	pressure_resistance = 2
	drop_sound = SFX_ITEMS_DROP_PAPER
	pickup_sound = SFX_ITEMS_PICKUP_PAPER
	slot_flags = SLOT_BELT | SLOT_HOLSTER
	/// Card stock: barely slows a fire (containment paths, C2).
	insulation = 0.1

// ---- Containment (C1): one pages slot for paperwork. Destroying the folder
// destroys its pages, as before. C2: the pages are inside the cover, and a
// stab goes straight through it. ----

/datum/om/relation/slot/folder_pages
	holder = /obj/item/folder
	slot_id = CONTAINER_SLOT_PAGES
	name = "pages"
	accepts = /datum/predicate/slot_folder_pages
	drop_policy = SLOT_DROP_DELETE
	exposure = SLOT_EXPOSURE_INTERNAL
	damage_transmission = list(0, 0.5, 1, 0, 0, 0, 0.5, 0, 0, 0, 0, 0)

/datum/predicate/slot_folder_pages
	name = "folder pages"
	spec = list(REQ_BECAUSE(REQ_TAG(PRED_TARGET, TAG_PAPERWORK), "only paper, photos and bundles fit"))

/obj/item/folder/on_slot_changed(slot_id, atom/movable/thing, inserted)
	update_icon()

/obj/item/folder/blue
	desc = "A blue folder."
	icon_state = "folder_blue"

/obj/item/folder/red
	desc = "A red folder."
	icon_state = "folder_red"

/obj/item/folder/yellow
	desc = "A yellow folder."
	icon_state = "folder_yellow"

/obj/item/folder/white
	desc = "A white folder."
	icon_state = "folder_white"

/obj/item/folder/blue_captain
	desc = "A blue folder with " + JOB_SITE_MANAGER + " markings."
	icon_state = "folder_captain"

/obj/item/folder/blue_hop
	desc = "A blue folder with HoP markings."
	icon_state = "folder_hop"

/obj/item/folder/white_cmo
	desc = "A white folder with CMO markings."
	icon_state = "folder_cmo"

/obj/item/folder/white_rd
	desc = "A white folder with RD markings."
	icon_state = "folder_rd"

/obj/item/folder/white_rd/Initialize(mapload)
	. = ..()
	//add some memos
	var/obj/item/paper/P = new()
	P.name = "Memo RE: proper analysis procedure"
	P.info = "<br>We keep test dummies in pens here for a reason"
	move_into(src, null, P)

/obj/item/folder/yellow_ce
	desc = "A yellow folder with CE markings."
	icon_state = "folder_ce"

/obj/item/folder/red_hos
	desc = "A red folder with HoS markings."
	icon_state = "folder_hos"

APPEARANCE_SLOT(/obj/item/folder, CONTAINER_SLOT_PAGES, "folder_paper")

/// Old attackby.
/obj/item/folder/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(HAS_TAG(W, TAG_PAPERWORK))
		var/why = dq_ledger_refusal(W, src, CONTAINER_SLOT_PAGES, user)
		if(why)
			to_chat(user, span_warning("You can't put \the [W] into \the [src]: [why]."))
			return INTERACTION_HANDLED_PASS
		user.drop_item()
		if(move_into(src, CONTAINER_SLOT_PAGES, W, user))
			to_chat(user, span_notice("You put the [W] into \the [src]."))
	else if(istype(W, /obj/item/pen))
		var/_answer_k98 = rerun_ask(user, "k98", PROC_REF(interaction_item), args, /datum/prompt/text, question = "What would you like to label the folder?", title = "Folder Labelling", max_len = MAX_NAME_LEN, encode = FALSE, name_text = ((MAX_NAME_LEN) <= MAX_NAME_LEN))
		if(isnull(_answer_k98))
			return TRUE
		var/n_name = sanitizeSafe(_answer_k98, MAX_NAME_LEN)
		if(in_range(user, src) && user.stat == 0)
			name = "folder[(n_name ? text("- '[n_name]'") : null)]"
	return INTERACTION_HANDLED_PASS

/obj/item/folder/afterattack(turf/T as turf, mob/user as mob)
	for(var/obj/item/paper/P in turf_contents_of_type(T, /obj/item/paper))
		if(move_into(src, CONTAINER_SLOT_PAGES, P, user))
			to_chat(user, span_notice("You tuck the [P] into \the [src]."))

// TGUI migration. attack_self opens Folder.tsx; the Topic
// remove/rename/read/look/browse actions move to tgui_act. Reading a
// paper/photo chains to that item's TGUI viewer (Paper.tsx / Photo.tsx).
DECLARE_INTERACTIONS(/obj/item/folder, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/folder/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	add_fingerprint(user)
	tgui_interact(user)
	return TRUE

CAPABILITIES(/obj/item/folder)
	interface("Folder")
	without("ui_open")
	op("remove", ui_act("remove", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_remove)))
	op("rename", ui_act("rename", arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_rename)))
	op("open", ui_act("open", arg("kind", schema_text(4096)), arg("ref", schema_ref(/obj/item))), then(PROC_REF(ui_act_open)))

/obj/item/folder/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["folder_name"] = name
	var/list/merged_1 = ui_data_obj_item_folder(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/folder's window data.
/obj/item/folder/proc/ui_data_obj_item_folder(mob/user, datum/tgui/ui, datum/tgui_state/state)
	var/list/data = list()
	var/list/items = list()
	FOR_REAL_CONTENTS(var/obj/item/paper/P, src)
		items += list(list("ref" = "\ref[P]", "name" = P.name, "kind" = "paper"))
	FOR_REAL_CONTENTS(var/obj/item/photo/Ph, src)
		items += list(list("ref" = "\ref[Ph]", "name" = Ph.name, "kind" = "photo"))
	FOR_REAL_CONTENTS(var/obj/item/paper_bundle/Pb, src)
		items += list(list("ref" = "\ref[Pb]", "name" = Pb.name, "kind" = "bundle"))
	data["items"] = items
	return data

/obj/item/folder/proc/ui_gate(datum/act/op/A)
	var/mob/user = A.actor
	if(user.stat || user.restrained())
		return FALSE
	if(loc != user)
		return FALSE
	return TRUE

/obj/item/folder/proc/ui_act_remove(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return FALSE
	if(slot_remove(O, user.loc, user))
		user.put_in_hands(O)
	return TRUE

/obj/item/folder/proc/ui_act_rename(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return FALSE
	if(istype(O, /obj/item/paper))
		var/obj/item/paper/p = O
		p.paper_verb_rename(user)
	else if(istype(O, /obj/item/photo))
		var/obj/item/photo/ph = O
		ph.photo_verb_rename(user)
	else if(istype(O, /obj/item/paper_bundle))
		var/obj/item/paper_bundle/pb = O
		pb.paper_bundle_verb_rename(user)
	return TRUE

/obj/item/folder/proc/ui_act_open(datum/act/op/A, kind, ref)
	var/mob/user = A.actor
	if(!ui_gate(A))
		return FALSE
	var/obj/item/O = ref
	if(!O || O.loc != src)
		return FALSE
	switch(kind)
		if("paper")
			var/obj/item/paper/p = O
			p.show_content(user)
		if("photo")
			var/obj/item/photo/ph = O
			ph.show(user)
		if("bundle")
			var/obj/item/paper_bundle/pb = O
			pb.attack_self(user)
	return TRUE
