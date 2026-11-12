// The shapeshift panel: every appearance command of a shapeshifter (the Abilities.Shapeshift verbs: body shape, hair, colours, ears, tail,
// wings, gender and the forms) in one TGUI window (console theme), with a preview of how the mob looks now. The commands are the same procs of
// the mob as before; the panel's buttons call them, so what one asks, what it refuses and its cooldown are the proc's own business and are the
// same from the panel and from code. A command is listed while the mob has been granted its proc.

#define SHIFT_SHAPE "shape"
#define SHIFT_GENDER "gender"
#define SHIFT_SKIN "skin"
#define SHIFT_EYES "eyes"
#define SHIFT_OPAQUE "opaque"
#define SHIFT_HAIR "hair"
#define SHIFT_HAIR_COLORS "hair_colors"
#define SHIFT_EARS "ears"
#define SHIFT_EARS2 "ears2"
#define SHIFT_TAIL "tail"
#define SHIFT_WINGS "wings"
#define SHIFT_COPY "copy"
#define SHIFT_REFORM "reform"
#define SHIFT_REGENERATE "regenerate"
#define SHIFT_FORM "form"

/// How many more window refreshes redraw the preview after the look changed (the mob's overlays settle a moment after the change).
#define SHIFT_PREVIEW_SETTLE 2

/// Open panels: mob -> the panel's handle_of (a deleted panel stops resolving).
GLOBAL_ALIST_EMPTY(dq_shapeshift_panels)

/datum/shapeshift_panel
	var/mob/living/shifter
	/// The values the preview was drawn for, and how many more refreshes draw it again.
	var/preview_key
	var/preview_settle = 0
	var/preview_image

/datum/shapeshift_panel/New(mob/living/shifter_mob)
	rel_set(src, nameof(shifter), shifter_mob)

/// Phase 2: leaves the per-mob panel index.
/datum/shapeshift_panel/lifecycle_dematerialize()
	. = ..()
	if(shifter)
		GLOB.dq_shapeshift_panels -= handle_of(shifter)

CAPABILITIES(/datum/shapeshift_panel)
	ref_one(nameof(shifter), /mob/living)
	interface("ShapeshiftPanel", title = "Shapeshift", state = nameof(GLOB.tgui_always_state))
	ui_shape(name = schema_text(), preview = nullable(schema_text()), groups = list_of(row(title = schema_text(), rows = list_of(row(id = schema_text(), label = schema_text(), action = schema_text(), desc = schema_text(), value = nullable(schema_text()), swatch = nullable(schema_text()), enabled = bool(), why = nullable(schema_text()))))))
	op("shift_do", ui_act("shift_do", arg("action", schema_text(32))), then(PROC_REF(ui_act_shift_do)))

/datum/shapeshift_panel/ui_prepare(mob/user, datum/tgui/ui)
	if(!shifter || user != shifter)
		return FALSE
	return TRUE

/// The commands of the panel, by group: id, label, the button's text, what it does and the proc of the mob that grants it.
GLOBAL_LIST_INIT(shapeshift_panel_commands, list(
	list("Body", list(
		list(SHIFT_SHAPE, "Body shape", "Change", "Take the shape of another species.", /mob/living/carbon/human/proc/shapeshifter_select_shape),
		list(SHIFT_GENDER, "Gender", "Change", "Select your gender and identity.", /mob/living/carbon/human/proc/shapeshifter_select_gender),
		list(SHIFT_SKIN, "Body colour", "Pick", "Select a new body colour.", /mob/living/carbon/human/proc/shapeshifter_select_colour),
		list(SHIFT_EYES, "Eye colour", "Pick", "Select a new eye colour.", /mob/living/carbon/human/proc/shapeshifter_select_eye_colour),
		list(SHIFT_OPAQUE, "Transparency", "Toggle", "Toggle how transparent your body is.", /mob/living/carbon/human/proc/promethean_select_opaqueness),
	)),
	list("Hair", list(
		list(SHIFT_HAIR, "Hair style", "Change", "Select a hair style, a gradient and facial hair.", /mob/living/carbon/human/proc/shapeshifter_select_hair),
		list(SHIFT_HAIR_COLORS, "Hair colours", "Pick", "Select the colours of your hair, its gradient and your facial hair.", /mob/living/carbon/human/proc/shapeshifter_select_hair_colors),
	)),
	list("Features", list(
		list(SHIFT_EARS, "Ears", "Change", "Select a pair of ears.", /mob/living/carbon/human/proc/shapeshifter_select_ears),
		list(SHIFT_EARS2, "Secondary ears", "Change", "Select a second pair of ears.", /mob/living/carbon/human/proc/shapeshifter_select_secondary_ears),
		list(SHIFT_TAIL, "Tail", "Change", "Select a tail.", /mob/living/carbon/human/proc/shapeshifter_select_tail),
		list(SHIFT_WINGS, "Wings", "Change", "Select a pair of wings.", /mob/living/carbon/human/proc/shapeshifter_select_wings),
	)),
	list("Forms", list(
		list(SHIFT_COPY, "Copy form", "Copy", "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them (without their name).", /mob/living/carbon/human/proc/shapeshifter_copy_body),
		list(SHIFT_REFORM, "Complete reform", "Reform", "Reform your body completely.", /mob/living/carbon/human/proc/shapeshifter_reassemble),
		list(SHIFT_REGENERATE, "Fully reform", "Reload", "Reload your appearance from whatever character slot you have loaded.", /mob/living/carbon/human/proc/shapeshifter_regenerate),
		list(SHIFT_FORM, "Mob form", "Shift", "Shape shift between set mob forms.", /mob/living/proc/shapeshift_form),
	)),
))

/// Has the mob been granted the proc of this command (a row of a group of GLOB.shapeshift_panel_commands)?
/mob/living/proc/shapeshift_command_granted(list/command)
	var/wanted = "[command[5]]"
	for(var/granted_verb in verbs)
		if("[granted_verb]" == wanted)
			return TRUE
	return FALSE

/// Does this mob have any shapeshift command granted? (The Abilities panel lists the Shapeshift command for those that do.)
/mob/living/proc/shapeshift_panel_listed(id)
	for(var/list/group as anything in GLOB.shapeshift_panel_commands)
		for(var/list/command as anything in group[2])
			if(shapeshift_command_granted(command))
				return TRUE
	return FALSE

/// What a command's setting is now, as the window shows it (a text, or null for a command with no setting).
/datum/shapeshift_panel/proc/command_value(id)
	var/mob/living/carbon/human/H = shifter
	if(!istype(H))
		return null
	switch(id)
		if(SHIFT_SHAPE)
			return "[H.wrapped_bodytype()]"
		if(SHIFT_GENDER)
			return "[H.gender]"
		if(SHIFT_HAIR)
			return "[H.looks.hair_style] / [H.looks.facial_style]"
		if(SHIFT_EARS)
			return H.ear_style ? "[H.ear_style.name]" : "Normal"
		if(SHIFT_EARS2)
			return H.ear_secondary_style ? "[H.ear_secondary_style.name]" : "Normal"
		if(SHIFT_TAIL)
			return H.tail_style ? "[H.tail_style.name]" : "Normal"
		if(SHIFT_WINGS)
			return H.wing_style ? "[H.wing_style.name]" : "None"
		if(SHIFT_SKIN)
			return "[H.looks.skin_color]"
		if(SHIFT_EYES)
			return "[H.looks.eyes_color]"
		if(SHIFT_HAIR_COLORS)
			return "[H.looks.hair_color]"
	return null

/// The colour a command's setting shows as a swatch, or null.
/datum/shapeshift_panel/proc/command_swatch(id)
	var/mob/living/carbon/human/H = shifter
	if(!istype(H))
		return null
	switch(id)
		if(SHIFT_SKIN)
			return H.looks.skin_color
		if(SHIFT_EYES)
			return H.looks.eyes_color
		if(SHIFT_HAIR_COLORS)
			return H.looks.hair_color
	return null

/// Why the commands cannot be used now, or null.
/datum/shapeshift_panel/proc/refusal()
	if(shifter.stat)
		return "You cannot do that while you are not conscious."
	return null

/// The preview of how the mob looks: drawn again when what the window shows changed, and a couple of refreshes after (the overlays settle after a change).
/datum/shapeshift_panel/proc/preview(key)
	if(key != preview_key)
		set_preview_key(key)
		set_preview_settle(SHIFT_PREVIEW_SETTLE)
	if(preview_settle > 0 || isnull(preview_image))
		if(preview_settle > 0)
			set_preview_settle(preview_settle - 1)
		// The shared portrait cache renders it off the tick; the last picture stays up until the new one lands (preview_landed).
		var/datum/portrait/P = portrait_request(shifter, SOUTH, src, PROC_REF(preview_landed))
		if(P?.b64)
			set_preview_image(P.b64)
	return preview_image

/// The mob's new portrait landed: the open window shows it in place.
/datum/shapeshift_panel/proc/preview_landed(datum/portrait/P)
	if(!shifter || !(shifter.appearance in P.appearances))
		return
	set_preview_image(P.b64)
	SStgui.update_uis(src)

/// /datum/shapeshift_panel's window data.
/datum/shapeshift_panel/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["groups"] = list()
	data["preview"] = null
	data["name"] = ""
	if(!shifter)
		return data
	data["name"] = "[shifter.name]"
	var/why = refusal()
	var/list/groups = list()
	var/list/signature = list()
	for(var/list/group as anything in GLOB.shapeshift_panel_commands)
		var/list/rows = list()
		for(var/list/command as anything in group[2])
			if(!shifter.shapeshift_command_granted(command))
				continue
			var/value = command_value(command[1])
			signature += value
			rows += list(list("id" = command[1], "label" = command[2], "action" = command[3], "desc" = command[4], "value" = value, "swatch" = command_swatch(command[1]), "enabled" = isnull(why), "why" = why))
		if(length(rows))
			groups += list(list("title" = group[1], "rows" = rows))
	data["groups"] = groups
	data["preview"] = preview(jointext(signature, "|"))
	return data

/datum/shapeshift_panel/proc/ui_act_shift_do(datum/act/op/A, action)
	return run_action(A.actor, action)

/// Runs one command for the mob that pressed it; FALSE when it is not this panel's mob, the command is not granted or refused, or unknown.
/datum/shapeshift_panel/proc/run_action(mob/user, action)
	if(!shifter || user != shifter || refusal())
		return FALSE
	for(var/list/group as anything in GLOB.shapeshift_panel_commands)
		for(var/list/command as anything in group[2])
			if(command[1] != action)
				continue
			if(!shifter.shapeshift_command_granted(command))
				return FALSE
			call(shifter, command[5])()
			set_preview_settle(SHIFT_PREVIEW_SETTLE)
			SStgui.update_uis(src)
			return TRUE
	return FALSE

/// Opens the shapeshift window of this mob.
/mob/living/proc/open_shapeshift_panel()
	var/key = handle_of(src)
	var/datum/shapeshift_panel/panel = handle_get(ALAZYACCESS(GLOB.dq_shapeshift_panels, key))
	if(!panel)
		panel = new(src)
		GLOB.dq_shapeshift_panels[key] = handle_of(panel)
	panel.tgui_interact(src)
