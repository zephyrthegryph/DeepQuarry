// The protean blob: the character's own mob wearing the nanite swarm's shape.
// Appearance is data (/datum/protean_blob_style); this form holds the
// character's choices (style, colours, per-layer states).

/datum/component/forms/protean
	/// The character's nanosuit control cluster. Per-character, lives here.
	/// There is only ever the one: if it is destroyed, it is gone.
	var/obj/item/rig/protean/rig
	/// world.time of the last form change (form strain).
	var/last_switch_time = 0

/datum/component/forms/protean/get_form_types()
	var/static/list/types = list(/datum/form/human, /datum/form/protean_blob)
	return types

/datum/component/forms/protean/RegisterWithParent()
	. = ..()
	var/mob/living/carbon/human/H = parent
	var/list/power_verbs = protean_power_verbs()
	if(length(power_verbs))
		add_verb(H, power_verbs)

/datum/component/forms/protean/UnregisterFromParent()
	var/mob/living/carbon/human/H = parent
	var/list/power_verbs = protean_power_verbs()
	if(length(power_verbs))
		remove_verb(H, power_verbs)
	return ..()

/datum/component/forms/protean/Destroy(force)
	if(rig)
		if(rig.myprotean == parent)
			rig.myprotean = null
		rig = null
	return ..()

/datum/component/forms/protean/proc/blob_form()
	RETURN_TYPE(/datum/form/protean_blob)
	return forms[/datum/form/protean_blob]

/// Inside our own control cluster (worn or lying about).
/datum/component/forms/protean/proc/in_rig()
	var/mob/living/carbon/human/H = parent
	return rig && H.loc == rig

/datum/component/forms/protean/proc/is_dormant()
	var/mob/living/carbon/human/H = parent
	return !!H.body?.find_affliction(/datum/affliction/core_dormancy)

/// Fold into the control cluster. Collapses into the blob first. Fails if
/// the cluster is gone.
/datum/component/forms/protean/proc/enter_rig()
	var/mob/living/carbon/human/H = parent
	if(!rig)
		to_chat(H, span_warning("Your control cluster is gone. You have nothing to fold into."))
		log_game("FORMS: [key_name(H)] tried to fold into a control cluster they no longer have.")
		return FALSE
	if(in_rig())
		return TRUE
	if(!is_form(/datum/form/protean_blob))
		set_form(/datum/form/protean_blob, silent = TRUE)
	var/turf/T = get_turf(H)
	if(rig.loc == H)
		H.drop_from_inventory(rig, T)
	else if(T && !isturf(rig.loc))
		rig.forceMove(T)
	blob_form().release_everything(H)
	H.forceMove(rig)
	rig.canremove = TRUE
	log_game("FORMS: [key_name(H)] folded into their control cluster at [AREACOORD(rig)]")
	return TRUE

/// Unfold from the control cluster, putting it back on. With `devour`, a host
/// that allows it ends up in the selected belly.
/datum/component/forms/protean/proc/leave_rig(devour = FALSE)
	var/mob/living/carbon/human/H = parent
	if(!in_rig())
		return FALSE
	var/mob/living/wearer = rig.wearer
	if(ismob(rig.loc))
		var/mob/M = rig.loc
		M.drop_from_inventory(rig)
	var/turf/T = get_turf(rig)
	H.forceMove(T)
	if(wearer && devour)
		if(H.can_be_drop_pred && wearer.devourable && wearer.can_be_drop_prey && H.vore_selected)
			H.begin_instant_nom(H, wearer, H, H.vore_selected)
		else
			to_chat(H, span_vwarning("You can't assimilate your current host."))
	rig.forceMove(H)
	H.equip_to_slot_if_possible(rig, slot_back)
	log_game("FORMS: [key_name(H)] unfolded from their control cluster at [AREACOORD(H)]")
	return TRUE


/// Changing shape quickly strains the swarm (form_strain).
/datum/component/forms/protean/set_form(form_type, silent = FALSE)
	var/previous_switch = last_switch_time
	. = ..()
	if(!.)
		return
	last_switch_time = world.time
	if(previous_switch && world.time - previous_switch < NANITE_FORM_SWITCH_GRACE)
		var/mob/living/carbon/human/H = parent
		H.body?.afflict(/datum/affliction/nanite/form_strain, null, NANITE_STRAIN_PER_FAST_SWITCH)
		log_game("FORMS: [key_name(H)] changed form again within [NANITE_FORM_SWITCH_GRACE / 10] seconds; form strain.")

/// Upkeep of the swarm's shape and its control cluster.
/datum/component/forms/protean/on_life(mob/living/source)
	SIGNAL_HANDLER
	..()
	if(source.stat == DEAD || is_dormant())
		return
	rig?.recharge_from(source)
	var/shapeless = !is_form(/datum/form/human) || in_rig()
	if(shapeless && world.time - last_switch_time > NANITE_FORM_HOLD_LIMIT)
		source.body?.afflict(/datum/affliction/nanite/form_strain, null, NANITE_STRAIN_PER_HELD_TICK)

/// The orchestrator coordinates a change of shape. A damaged one may fail to:
/// the chance of failure is half its damage's severity. Returns TRUE when the
/// swarm holds together for the change.
/datum/component/forms/protean/proc/form_control_check()
	var/mob/living/carbon/human/H = parent
	var/obj/item/organ/internal/nano/orchestrator/O = H.internal_organs_by_name?[O_ORCH]
	var/datum/affliction/nanite/orchestrator_damage/damage = O && H.body?.find_affliction(/datum/affliction/nanite/orchestrator_damage, O)
	if(!damage || !prob(damage.severity / 2))
		return TRUE
	to_chat(H, span_warning("Your orchestrator loses track of the swarm and the change falls apart!"))
	log_game("FORMS: [key_name(H)] failed a form change to orchestrator damage ([round(damage.severity)]).")
	return FALSE


// --- The blob form -------------------------------------------------------------------

/datum/form/protean_blob
	name = "nanite blob"
	id = "protean_blob"
	form_flag = FORM_FLAG_PROTEAN_BLOB
	draws_body = FALSE
	regeneration = 5
	holder_type = /obj/item/holder/protoblob
	enter_message = "collapses into a gooey blob!"
	/// Id of the /datum/protean_blob_style being worn.
	var/style_id = "puddle1"
	var/color_primary = "#363636"
	var/color_highlight = "#ba3636"
	/// style id -> list of layer states, for layered styles. Lazy.
	var/list/layer_states
	/// style id -> list of layer colours, for layered styles. Lazy.
	var/list/layer_colors
	/// Dispersed into a thin veil (the Hide Self power).
	var/hiding = FALSE

/datum/form/protean_blob/proc/get_style()
	RETURN_TYPE(/datum/protean_blob_style)
	return protean_blob_styles()[style_id] || protean_blob_styles()["puddle1"]

/datum/form/protean_blob/on_enter(datum/component/forms/F, mob/living/carbon/human/H)
	release_everything(H)
	..()
	H.item_state = style_id
	H.vore_capacity = get_style().vore_capacity

/datum/form/protean_blob/on_exit(datum/component/forms/F, mob/living/carbon/human/H)
	if(hiding)
		set_hiding(H, FALSE)
	H.item_state = null
	H.vore_capacity = initial(H.vore_capacity)
	..()
	to_chat(H, span_notice("You rapidly reassemble your form."))

/datum/form/protean_blob/announce_enter(mob/living/carbon/human/H)
	..()
	to_chat(H, span_notice("You rapidly disassociate your form. In this form your nanites repair you from your refactory's steel."))

/datum/form/protean_blob/build_overlays(datum/component/forms/F, mob/living/carbon/human/H)
	if(hiding)
		return list(image('icons/mob/species/protean/protean.dmi', "hide"))
	return get_style().build(src, H)

/// Change style; keeps the holder sprite and belly capacity in step.
/datum/form/protean_blob/proc/set_style(new_style_id, mob/living/carbon/human/H)
	if(!protean_blob_styles()[new_style_id])
		return FALSE
	style_id = new_style_id
	H.vore_capacity = get_style().vore_capacity
	H.item_state = style_id
	if(istype(H.loc, /obj/item/holder/protoblob))
		var/obj/item/holder/protoblob/PB = H.loc
		PB.item_state = style_id
	return TRUE

/// This character's layer states for a layered style, seeded from its defaults.
/datum/form/protean_blob/proc/states_for(datum/protean_blob_style/layered/S)
	LAZYINITLIST(layer_states)
	if(!layer_states[S.id])
		layer_states[S.id] = S.default_states()
	return layer_states[S.id]

/datum/form/protean_blob/proc/colors_for(datum/protean_blob_style/layered/S)
	LAZYINITLIST(layer_colors)
	if(!layer_colors[S.id])
		layer_colors[S.id] = S.default_colors()
	return layer_colors[S.id]

/datum/form/protean_blob/proc/set_hiding(mob/living/carbon/human/H, new_hiding)
	if(hiding == new_hiding)
		return
	hiding = new_hiding
	if(hiding)
		H.mouse_opacity = MOUSE_OPACITY_TRANSPARENT
		RegisterSignal(H, COMSIG_MOVABLE_PRE_MOVE, PROC_REF(block_move))
	else
		H.mouse_opacity = MOUSE_OPACITY_ICON
		UnregisterSignal(H, COMSIG_MOVABLE_PRE_MOVE)
	H.get_forms()?.refresh_appearance()

/datum/form/protean_blob/proc/block_move(atom/movable/source)
	SIGNAL_HANDLER
	return COMPONENT_MOVABLE_BLOCK_PRE_MOVE


// --- Blob styles: appearance as data ---------------------------------------------------

/// id -> /datum/protean_blob_style, in radial-menu order.
/proc/protean_blob_styles()
	var/static/list/styles
	if(styles)
		return styles
	styles = list()
	for(var/style_type in subtypesof(/datum/protean_blob_style))
		var/datum/protean_blob_style/S = style_type
		if(!initial(S.id))
			continue
		S = new style_type()
		styles[S.id] = S
	return styles

/// A single-sprite style: a body tinted with the primary colour and eyes
/// tinted with the highlight colour.
/datum/protean_blob_style
	var/id
	var/name
	var/icon = 'icons/mob/species/protean/protean.dmi'
	/// Horizontal offset of wide sprites.
	var/pixel_x = 0
	var/vore_capacity = 1
	/// Radial preview.
	var/preview_icon
	var/preview_state

/datum/protean_blob_style/proc/radial_image()
	return image(icon = preview_icon || icon, icon_state = preview_state || id, pixel_x = pixel_x)

/datum/protean_blob_style/proc/build(datum/form/protean_blob/B, mob/living/carbon/human/H)
	var/fullness = min(H.vore_fullness, vore_capacity)
	var/rest = H.resting ? "_rest" : ""
	. = list()
	var/image/body = image(icon, "[id][rest][fullness ? "-[fullness]" : ""]", pixel_x = pixel_x)
	body.color = B.color_primary
	body.appearance_flags |= (RESET_COLOR | PIXEL_SCALE)
	. += body
	var/image/eyes = image(icon, "[id][rest]-eyes", pixel_x = pixel_x)
	eyes.color = B.color_highlight
	eyes.appearance_flags |= (RESET_COLOR | PIXEL_SCALE)
	eyes.plane = PLANE_LIGHTING_ABOVE
	. += eyes

/datum/protean_blob_style/puddle1
	id = "puddle1"
	preview_icon = 'icons/mob/species/protean/protean_powers.dmi'
	preview_state = "blob"
/datum/protean_blob_style/puddle0
	id = "puddle0"
	preview_state = "puddle"
/datum/protean_blob_style/shadow
	id = "shadow"
/datum/protean_blob_style/clean
	id = "clean"
/datum/protean_blob_style/swarm
	id = "swarm"
/datum/protean_blob_style/slime
	id = "slime"
/datum/protean_blob_style/chaos
	id = "chaos"
/datum/protean_blob_style/cloud
	id = "cloud"
/datum/protean_blob_style/catslug
	id = "catslug"
/datum/protean_blob_style/cat
	id = "cat"
/datum/protean_blob_style/mouse
	id = "mouse"
/datum/protean_blob_style/rabbit
	id = "rabbit"
/datum/protean_blob_style/bear
	id = "bear"
/datum/protean_blob_style/fen
	id = "fen"
/datum/protean_blob_style/fox
	id = "fox"
/datum/protean_blob_style/raptor
	id = "raptor"
/datum/protean_blob_style/rat
	id = "rat"
	icon = 'icons/mob/species/protean/protean64x32.dmi'
	pixel_x = -16
/datum/protean_blob_style/lizard
	id = "lizard"
	icon = 'icons/mob/species/protean/protean64x32.dmi'
	pixel_x = -16
/datum/protean_blob_style/wolf
	id = "wolf"
	icon = 'icons/mob/species/protean/protean64x32.dmi'
	pixel_x = -16
/datum/protean_blob_style/teppi
	id = "teppi"
	icon = 'icons/mob/species/protean/protean64x64.dmi'
	pixel_x = -16
/datum/protean_blob_style/panther
	id = "panther"
	icon = 'icons/mob/species/protean/protean64x64.dmi'
	pixel_x = -16
/datum/protean_blob_style/robodrgn
	id = "robodrgn"
	icon = 'icons/mob/species/protean/protean128x64.dmi'
	pixel_x = -48


/// A multi-layer style: every layer picks a state from its options and a colour.
/datum/protean_blob_style/layered
	/// Radial label icon for the layer menu.
	var/label_icon
	/// /datum/protean_blob_layer instances, in draw order.
	var/list/layers

/datum/protean_blob_style/layered/New()
	..()
	layers = list()
	for(var/list/spec as anything in layer_specs())
		layers += new /datum/protean_blob_layer(arglist(spec))

/// Constructor arguments for each layer, in draw order.
/datum/protean_blob_style/layered/proc/layer_specs()
	return list()

/datum/protean_blob_style/layered/proc/default_states()
	. = list()
	for(var/datum/protean_blob_layer/L as anything in layers)
		. += L.default_state

/datum/protean_blob_style/layered/proc/default_colors()
	. = list()
	for(var/datum/protean_blob_layer/L as anything in layers)
		. += "#FFFFFF"

/// Keep layers that follow other layers in step after a change.
/datum/protean_blob_style/layered/proc/derive_states(list/states)
	return

/// Options for a layer this character may use.
/datum/protean_blob_style/layered/proc/layer_options(datum/protean_blob_layer/L, mob/living/carbon/human/H)
	return L.options.Copy()

/datum/protean_blob_style/layered/build(datum/form/protean_blob/B, mob/living/carbon/human/H)
	var/list/states = B.states_for(src)
	var/list/colors = B.colors_for(src)
	var/fullness = min(H.vore_fullness, vore_capacity)
	. = list()
	for(var/i in 1 to length(layers))
		var/datum/protean_blob_layer/L = layers[i]
		var/suffix = ""
		if(H.resting)
			suffix = "-rest"
		else if(fullness && L.shows_fullness)
			suffix = "-[fullness]"
		var/image/I = image(icon, "[states[i]][suffix]", pixel_x = pixel_x)
		I.color = colors[i]
		I.appearance_flags |= (RESET_COLOR | PIXEL_SCALE)
		if(L.glows)
			I.plane = PLANE_LIGHTING_ABOVE
		. += I

/// Serialise the layered choices: "state;color;state;color;...".
/datum/protean_blob_style/layered/proc/export_string(datum/form/protean_blob/B)
	var/list/states = B.states_for(src)
	var/list/colors = B.colors_for(src)
	var/list/parts = list()
	for(var/i in 1 to length(layers))
		parts += states[i]
		parts += colors[i]
	return jointext(parts, ";")

/// Load a string written by export_string(). Every field is validated
/// against its own layer; invalid fields are skipped. Returns fields applied.
/datum/protean_blob_style/layered/proc/import_string(datum/form/protean_blob/B, mob/living/carbon/human/H, text)
	var/list/parts = splittext(text, ";")
	if(length(parts) != 2 * length(layers))
		return 0
	var/list/states = B.states_for(src)
	var/list/colors = B.colors_for(src)
	. = 0
	for(var/i in 1 to length(layers))
		var/datum/protean_blob_layer/L = layers[i]
		var/new_state = parts[2 * i - 1]
		var/new_color = parts[2 * i]
		if(!L.editable)
			continue
		if(new_state in layer_options(L, H))
			states[i] = new_state
			.++
		var/clean_color = sanitize_hexcolor(new_color, null)
		if(L.colorable && clean_color)
			colors[i] = clean_color
			.++
	derive_states(states)

/datum/protean_blob_layer
	/// Radial label (a state in the style's label_icon).
	var/label
	var/list/options
	var/default_state
	/// The colour can be picked; otherwise it stays white.
	var/colorable = TRUE
	/// Players choose this layer; FALSE for layers derived from others.
	var/editable = TRUE
	/// Draw the belly-fullness variant.
	var/shows_fullness = TRUE
	/// Draw above lighting (eyes).
	var/glows = FALSE
	/// Radial preview placement.
	var/preview_dir = SOUTH
	var/preview_pixel_x = 0
	var/preview_pixel_y = 0

/datum/protean_blob_layer/New(label, list/options, default_state, colorable = TRUE, editable = TRUE, shows_fullness = TRUE, glows = FALSE, preview_dir = SOUTH, preview_pixel_x = 0, preview_pixel_y = 0)
	src.label = label
	src.options = options
	src.default_state = default_state
	src.colorable = colorable
	src.editable = editable
	src.shows_fullness = shows_fullness
	src.glows = glows
	src.preview_dir = preview_dir
	src.preview_pixel_x = preview_pixel_x
	src.preview_pixel_y = preview_pixel_y

/datum/protean_blob_style/layered/dragon
	id = "dragon"
	name = "Dragon"
	icon = 'icons/mob/vore128x64.dmi'
	pixel_x = -48
	vore_capacity = 2
	preview_icon = 'icons/mob/bigdragon_small.dmi'
	preview_state = "dragon_small"
	label_icon = 'icons/effects/bigdragon_labels.dmi'

/datum/protean_blob_style/layered/dragon/radial_image()
	return image(icon = preview_icon, icon_state = preview_state)

/datum/protean_blob_style/layered/dragon/layer_specs()
	return list(
		list("Underbelly", list("dragon_underSmooth", "dragon_underPlated"), "dragon_underSmooth", TRUE, TRUE, TRUE, FALSE, EAST, -48, 0),
		list("Body", list("dragon_bodySmooth", "dragon_bodyScaled"), "dragon_bodySmooth", TRUE, TRUE, FALSE, FALSE, EAST, -48, 0),
		list("Ears", list("dragon_earsNormal"), "dragon_earsNormal", TRUE, TRUE, FALSE, FALSE, EAST, -76, -50),
		list("Mane", list("dragon_maneNone", "dragon_maneShaggy", "dragon_maneDorsalfin"), "dragon_maneShaggy", TRUE, TRUE, FALSE, FALSE, EAST, -76, -50),
		list("Horns", list("dragon_hornsPointy", "dragon_hornsCurved", "dragon_hornsCurved2", "dragon_hornsJagged", "dragon_hornsCrown", "dragon_hornsSkull"), "dragon_hornsPointy", TRUE, TRUE, FALSE, FALSE, EAST, -86, -50),
		list("Eyes", list("dragon_eyesNormal"), "dragon_eyesNormal", TRUE, TRUE, FALSE, TRUE, SOUTH, -48, -50),
	)

/datum/protean_blob_style/layered/dullahan
	id = "dullahan"
	name = "Dullahan"
	icon = 'icons/mob/robot/dullahan/v1/Dullahanprotean64x64.dmi'
	pixel_x = -16
	preview_icon = 'icons/mob/robot/dullahan/v1/dullahanicon.dmi'
	preview_state = "proticon"
	label_icon = 'icons/mob/robot/dullahan/v1/dullahansigns.dmi'

/datum/protean_blob_style/layered/dullahan/radial_image()
	return image(icon = preview_icon, icon_state = preview_state)

/datum/protean_blob_style/layered/dullahan/layer_specs()
	return list(
		list("Body", list("dullahanbody"), "dullahanbody", FALSE, FALSE),
		list("Eyes", list("dullahaneyes"), "dullahaneyes", TRUE, TRUE, TRUE, FALSE, SOUTH, -16, 0),
		list("Metalshell", list("dullahanmetal", "dullahanmetal2", "dullahancommand"), "dullahanmetal", TRUE, TRUE, TRUE, FALSE, SOUTH, -16, 0),
		list("Head", list("dullahanhead", "dullahanhead2"), "dullahanhead", FALSE, TRUE, TRUE, FALSE, SOUTH, -16, -16),
		list("Lights", list("dullahanlightsempty", "dullahanlights", "dullahanwings", "dullahanlights2", "dullahanwings2", "dullahanwings3"), "dullahanlightsempty", TRUE, TRUE, TRUE, FALSE, SOUTH, -16, -16),
		list("Breastplate", list("dullahanextendedoff", "dullahanextendedon"), "dullahanextendedoff", FALSE, FALSE),
		list("Clothes", list("dullahanclothesempty", "dullahanclothes", "dullahanclothes2", "dullahanengibreastplate"), "dullahanclothesempty", FALSE, TRUE, TRUE, FALSE, SOUTH, -16, -16),
	)

/// The command shell is reserved for command staff.
/datum/protean_blob_style/layered/dullahan/layer_options(datum/protean_blob_layer/L, mob/living/carbon/human/H)
	. = ..()
	if(L.label == "Metalshell" && !(H.mind?.assigned_role in GLOB.command_positions))
		. -= "dullahancommand"

/// The extended breastplate follows the second metal shell.
/datum/protean_blob_style/layered/dullahan/derive_states(list/states)
	states[6] = (states[3] == "dullahanmetal2") ? "dullahanextendedon" : "dullahanextendedoff"
