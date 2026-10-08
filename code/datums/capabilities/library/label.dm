// label() / rename(): a label shown in the holder's name, "[name] ([label])". label() applies the
// text set on a hand labeller; rename() asks for the text when a pen is used. Both offer
// "Remove label". The original name and the label live in the holder's capability data; the first
// label capability a type declares owns it, so label() and rename() on one type share one label.

/datum/capability/label
	data_type = /datum/cap_label_data
	layer_name = CAP_NO_LAYER
	var/max_length = MAX_NAME_LEN

/// The pen variant: its own key so a type can have both.
/datum/capability/label/rename

/datum/cap_label_data
	/// The label text, or null.
	var/label
	/// The name before the label went on.
	var/base_name

/proc/cap_label(max_length = MAX_NAME_LEN, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/label/C = new
	C.max_length = max_length
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/proc/cap_rename(max_length = MAX_NAME_LEN, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME)
	var/datum/capability/label/rename/C = new
	C.max_length = max_length
	return cap_gating(C, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/// Ops: "label" (a click with a hand labeler) or "rename" (a click with a pen), and "remove_label" (ACT_NONE).
/datum/capability/label/interactions(atom/holder)
	return list(adopt_entry(lib_op("Label", GLOBAL_PROC_REF(cap_label_apply), OP_SHAPE_USE_ON, using = /obj/item/hand_labeler, key = "label", works_broken = TRUE, works_unpowered = TRUE)), remove_entry())

/datum/capability/label/rename/interactions(atom/holder)
	return list(adopt_entry(lib_op("Rename", GLOBAL_PROC_REF(cap_label_rename), OP_SHAPE_USE_ON, using = /obj/item/pen, key = "rename", works_broken = TRUE, works_unpowered = TRUE)), remove_entry())

/// ACT_NONE: an empty hand keeps doing the holder's own thing; the Menu, radial and command bar name it.
/datum/capability/label/proc/remove_entry()
	var/datum/interaction/capability/E = adopt_entry(lib_op("Remove label", GLOBAL_PROC_REF(cap_label_remove), OP_SHAPE_HAND, key = "remove_label", action = ACT_NONE, needs = GLOBAL_PROC_REF(cap_label_present), else_say = "it has no label", works_broken = TRUE, works_unpowered = TRUE))
	E.id = "[E.id]:[key]" // cap_label() and cap_rename() on one type each offer their own
	return E

/datum/capability/label/examine(atom/holder, mob/user)
	if(cap_label_cap(holder) != src)
		return null // the owning label capability says it once
	var/label = cap_label_of(holder)
	return label ? list("It has a label reading \"[label]\".") : null

/// The label capability of A (label() or rename()) that owns the label data.
/proc/cap_label_cap(atom/A)
	return cap_of(A, /datum/capability/label)

/// A's label text, or null.
/proc/cap_label_of(atom/A)
	var/datum/capability/label/C = cap_label_cap(A)
	if(!C)
		return null
	var/datum/cap_label_data/D = capability_data(A)?[C.key]
	return D?.label

/// Sets A's label through its name, or clears it with null.
/proc/cap_label_set(atom/A, text)
	var/datum/capability/label/C = cap_label_cap(A)
	var/datum/cap_label_data/D = cap_data(A, C)
	if(text)
		if(isnull(D.base_name))
			D.base_name = A.name
		D.label = text
		A.name = "[D.base_name] ([text])"
	else if(D.label)
		A.name = D.base_name
		D.label = null
		D.base_name = null
	changed(A, CHANGE_CAPABILITY)

/proc/cap_label_present(mob/user, atom/holder, obj/item/held)
	return !isnull(cap_label_of(holder))

/proc/cap_label_apply(atom/holder, mob/user, obj/item/hand_labeler/held)
	var/datum/capability/label/C = cap_label_cap(holder)
	if(!held.mode)
		return refuse(user, "Turn \the [held] on first.")
	if(!held.label)
		return refuse(user, "\The [held] has no label text set.")
	if(held.labels_left <= 0)
		return refuse(user, "\The [held] has no labels left.")
	var/text = copytext(held.label, 1, C.max_length + 1)
	held.labels_left--
	cap_label_set(holder, text)
	act_message(user, holder, self = span_notice("You label %T% as [text]."), others = span_notice("%U% labels %T% as [text]."), item = held)
	return TRUE

/proc/cap_label_rename(atom/holder, mob/user, obj/item/held)
	var/datum/capability/label/C = cap_label_cap(holder)
	var/text = ask_text(user, "What would you like to label it?", "Rename", default = cap_label_of(holder), max_length = C.max_length)
	if(!text)
		return UI_REFUSED
	cap_label_set(holder, text)
	act_message(user, holder, self = span_notice("You label %T% as [text]."), others = span_notice("%U% labels %T% as [text]."), item = held)
	return TRUE

/proc/cap_label_remove(atom/holder, mob/user, obj/item/held)
	cap_label_set(holder, null)
	act_message(user, holder, self = span_notice("You peel the label off %T%."), others = span_notice("%U% peels the label off %T%."))
	return TRUE
