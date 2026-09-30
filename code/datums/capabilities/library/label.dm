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

/proc/cap_label(max_length = MAX_NAME_LEN, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME, layer = CAP_NO_LAYER)
	var/datum/capability/label/C = new
	C.max_length = max_length
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/proc/cap_rename(max_length = MAX_NAME_LEN, behind = NONE, blocked_by = NONE, locked_by = NONE, needs, else_say, works_broken = TRUE, works_unpowered = TRUE, log = LOG_GAME, layer = CAP_NO_LAYER)
	var/datum/capability/label/rename/C = new
	C.max_length = max_length
	C.layer_name = layer
	return cap_gating(C, behind = behind, blocked_by = blocked_by, locked_by = locked_by, needs = needs, else_say = else_say, works_broken = works_broken, works_unpowered = works_unpowered, log = log)

/datum/capability/label/interactions(atom/holder)
	return list(adopt_entry(cap_use_on("Label", /obj/item/hand_labeler, TYPE_PROC_REF(/atom, cap_label_apply), works_broken = TRUE, works_unpowered = TRUE)), remove_entry())

/datum/capability/label/rename/interactions(atom/holder)
	return list(adopt_entry(cap_use_on("Rename", /obj/item/pen, TYPE_PROC_REF(/atom, cap_label_rename), works_broken = TRUE, works_unpowered = TRUE)), remove_entry())

/datum/capability/label/proc/remove_entry()
	var/datum/interaction/capability/E = adopt_entry(cap_hand("Remove label", TYPE_PROC_REF(/atom, cap_label_remove), needs = TYPE_PROC_REF(/atom, cap_label_present), else_say = "it has no label", works_broken = TRUE, works_unpowered = TRUE))
	E.id = "[E.id]:[key]" // cap_label() and cap_rename() on one type each offer their own
	E.default_action = null // Menu only: an empty hand keeps doing the holder's own thing
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
	var/datum/cap_label_data/D = A.cap_data?[C.key]
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

/atom/proc/cap_label_present(mob/user, obj/item/held)
	return !isnull(cap_label_of(src))

/atom/proc/cap_label_apply(mob/user, obj/item/hand_labeler/held)
	var/datum/capability/label/C = cap_label_cap(src)
	if(!held.mode)
		return refuse(user, "Turn \the [held] on first.")
	if(!held.label)
		return refuse(user, "\The [held] has no label text set.")
	if(held.labels_left <= 0)
		return refuse(user, "\The [held] has no labels left.")
	var/text = copytext(held.label, 1, C.max_length + 1)
	held.labels_left--
	cap_label_set(src, text)
	act_message(user, src, self = span_notice("You label %T% as [text]."), others = span_notice("%U% labels %T% as [text]."), item = held)
	return TRUE

/atom/proc/cap_label_rename(mob/user, obj/item/held)
	var/datum/capability/label/C = cap_label_cap(src)
	var/text = ask_text(user, "What would you like to label it?", "Rename", default = cap_label_of(src), max_length = C.max_length)
	if(!text)
		return UI_REFUSED
	cap_label_set(src, text)
	act_message(user, src, self = span_notice("You label %T% as [text]."), others = span_notice("%U% labels %T% as [text]."), item = held)
	return TRUE

/atom/proc/cap_label_remove(mob/user, obj/item/held)
	cap_label_set(src, null)
	act_message(user, src, self = span_notice("You peel the label off %T%."), others = span_notice("%U% peels the label off %T%."))
	return TRUE
