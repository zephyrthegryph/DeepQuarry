// Protean powers: one registry, one place that decides whether the swarm can
// act. Each power declares its cost, the forms it can be used from and whether
// it works while folded into the control cluster. The acting form is resolved
// once, in try_activate(). Hotkey verbs and the stat panel come from the registry.

#define PER_LIMB_STEEL_COST SHEET_MATERIAL_AMOUNT
#define TOTAL_REBUILD_STEEL_COST 10000

/// Power type -> instance.
/proc/protean_powers()
	var/static/list/powers
	if(powers)
		return powers
	powers = list()
	for(var/power_type in subtypesof(/datum/protean_power))
		powers[power_type] = new power_type()
	return powers

/// Every hotkey verb the registry provides; the forms component grants them.
/proc/protean_power_verbs()
	var/static/list/power_verbs
	if(power_verbs)
		return power_verbs
	power_verbs = list()
	for(var/power_type in protean_powers())
		var/datum/protean_power/P = protean_powers()[power_type]
		if(P.verb_path)
			power_verbs += P.verb_path
	return power_verbs

/mob/living/carbon/human/proc/activate_protean_power(power_type)
	var/datum/protean_power/P = protean_powers()[power_type]
	return P?.try_activate(src)

/datum/protean_power
	var/name = "power"
	var/desc = ""
	var/icon = 'icons/mob/species/protean/protean_powers.dmi'
	var/icon_state
	/// FORM_FLAG_* this power can be used from.
	var/allowed_forms = FORM_FLAG_HUMAN | FORM_FLAG_PROTEAN_BLOB
	/// Usable while folded into the control cluster.
	var/usable_in_rig = FALSE
	/// ONLY usable while folded into the control cluster.
	var/rig_only = FALSE
	/// Needs open space (a turf) around the character.
	var/needs_turf = FALSE
	/// Needs the character awake.
	var/needs_conscious = TRUE
	/// The hotkey verb that triggers this power.
	var/verb_path
	/// Listed in the Protean stat panel.
	var/in_stat_panel = TRUE
	/// Stat panel button (an atom, so the panel can click it).
	var/obj/effect/protean_power_button/button

/datum/protean_power/New()
	..()
	if(in_stat_panel)
		button = new(null, src)

DECLARE_REF(/datum/protean_power, "button", OWNED, null)

/datum/protean_power/proc/try_activate(mob/living/carbon/human/H)
	if(!istype(H))
		return FALSE
	var/datum/forms/protean/F = H.get_protean_forms()
	if(!F)
		to_chat(H, span_warning("You don't have a nanite swarm to do that with."))
		return FALSE
	if(!can_use(H, F))
		return FALSE
	activate(H, F)
	return TRUE

/datum/protean_power/proc/can_use(mob/living/carbon/human/H, datum/forms/protean/F)
	if(F.is_dormant())
		to_chat(H, span_warning("You need to be repaired first before you can act!"))
		return FALSE
	if(needs_conscious && H.stat)
		to_chat(H, span_warning("You must be awake to do that!"))
		return FALSE
	var/folded = F.in_rig()
	if(rig_only && !folded)
		to_chat(H, span_warning("You need to be folded into your control cluster to do that."))
		return FALSE
	if(folded && !usable_in_rig)
		to_chat(H, span_warning("You can't do that while folded into your control cluster."))
		return FALSE
	if(!(F.current.form_flag & allowed_forms))
		to_chat(H, span_warning("You can't do that in your current form."))
		return FALSE
	if(needs_turf && !isturf(H.loc))
		to_chat(H, span_warning("You need more space to perform this action!"))
		return FALSE
	return TRUE

/datum/protean_power/proc/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	return

/obj/effect/protean_power_button
	name = "Activate"
	icon = 'icons/mob/species/protean/protean_powers.dmi'
	var/datum/protean_power/power

/obj/effect/protean_power_button/Initialize(mapload, datum/protean_power/new_power)
	. = ..()
	power = new_power
	name = power.name
	desc = power.desc
	icon = power.icon
	icon_state = power.icon_state

/obj/effect/protean_power_button/Click(location, control, params)
	var/mob/living/carbon/human/H = usr
	if(!istype(H) || !power)
		return
	if(GLOB.input_router.click_is(params, GLOB.input_router.shift_table(), INPUT_ACTION_INSPECT))
		to_chat(H, span_notice(span_bold("[power.name]") + " - [power.desc]"))
		return
	power.try_activate(H)

// --- Form ------------------------------------------------------------------------------

/datum/protean_power/blobform
	name = "Toggle Blobform"
	desc = "Discard your shape entirely, changing to a low-energy blob. You'll consume steel to repair yourself in this form."
	icon_state = "blob"
	needs_turf = TRUE
	verb_path = /mob/living/carbon/human/proc/nano_blobform

/datum/protean_power/blobform/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	if(F.is_form(/datum/form/protean_blob))
		om_task_start(/datum/om/task/timed/blobform_activate_blobform, H, H, F = F)
		return
	if(H.get_equipped_item(SLOT_ID_HANDCUFFED))
		to_chat(H, span_warning("You can't do this while handcuffed!"))
		return
	to_chat(H, span_notice("You begin to disassociate your form."))
	om_task_start(/datum/om/task/timed/blobform_activate_blobform2, H, H, F = F)
	return TRUE

/datum/om/task/timed/blobform_activate_blobform
	duration = 2 SECONDS
	complete_proc = /datum/protean_power/blobform/proc/activate_blobform_done
	cancel_proc = /datum/protean_power/blobform/proc/activate_blobform_failed
	var/datum/forms/protean/F

/datum/protean_power/blobform/proc/activate_blobform_done(datum/om/task/timed/blobform_activate_blobform/task)
	var/datum/forms/protean/F = task.F
	if(F.form_control_check())
		F.set_form(/datum/form/human)
	return

/datum/protean_power/blobform/proc/activate_blobform_failed(datum/om/task/timed/blobform_activate_blobform/task)
	var/mob/living/carbon/human/H = task.actor
	to_chat(H, span_warning("You must remain still to reshape yourself!"))
	return
/datum/om/task/timed/blobform_activate_blobform2
	duration = 2 SECONDS
	complete_proc = /datum/protean_power/blobform/proc/activate_blobform_done2
	cancel_proc = /datum/protean_power/blobform/proc/activate_blobform_failed2
	var/datum/forms/protean/F

/datum/protean_power/blobform/proc/activate_blobform_done2(datum/om/task/timed/blobform_activate_blobform2/task)
	var/datum/forms/protean/F = task.F
	if(F.form_control_check())
		F.set_form(/datum/form/protean_blob)

/datum/protean_power/blobform/proc/activate_blobform_failed2(datum/om/task/timed/blobform_activate_blobform2/task)
	var/mob/living/carbon/human/H = task.actor
	to_chat(H, span_warning("You must remain still to blobform!"))
	return

/mob/living/carbon/human/proc/nano_blobform()
	set name = "Toggle Blobform"
	set desc = "Switch between amorphous and humanoid forms."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/blobform)

/datum/protean_power/change_volume
	name = "Change Volume"
	desc = "Alter your size between 25% and 200%."
	icon_state = "volume"
	allowed_forms = FORM_FLAG_HUMAN | FORM_FLAG_PROTEAN_BLOB

/datum/protean_power/change_volume/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	H.set_size()

/// Species inherent verb: pick which species' clothing fit (and sprites) to use.
/mob/living/carbon/human/proc/nano_change_fitting()
	set name = "Change Species Fit"
	set desc = "Tweak your shape to change what suits you fit into (and their sprites!)."
	set category = "Abilities.Protean"

	if(stat)
		to_chat(src, span_warning("You must be awake and standing to perform this action!"))
		return
	om_ask(src, /datum/om/prompt/choice, PROC_REF(nano_fitting_chosen), message = "Please select a species to emulate.", title = "Shapeshifter Body", choices = list(species?.vanity_base_fit) | species?.get_valid_shapeshifter_forms(), ask_flags = ASK_CONSCIOUS)

/mob/living/carbon/human/proc/nano_fitting_chosen(datum/om/prompt/choice/ask)
	if(!species)
		return
	species.base_species = ask.choice
	regenerate_icons()

/datum/protean_power/hide_self
	name = "Hide Self"
	desc = "Disperse your mass into a thin veil, making a trap to snatch prey with, or simply hide."
	allowed_forms = FORM_FLAG_PROTEAN_BLOB
	needs_turf = TRUE
	in_stat_panel = FALSE
	verb_path = /mob/living/carbon/human/proc/prot_hide

/datum/protean_power/hide_self/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/datum/form/protean_blob/B = F.blob_form()
	if(!B.hiding && H.resting)
		to_chat(H, span_warning("You can't hide while resting."))
		return
	B.set_hiding(H, !B.hiding)
	if(B.hiding || !H.can_be_drop_pred || !H.vore_selected)
		return
	// Springing the trap: engulf something standing on us.
	var/list/potentials = H.living_mobs(0)
	potentials -= H
	if(!length(potentials))
		return
	var/mob/living/target = pick(potentials)
	if(!can_spontaneous_vore(H, target))
		return
	if(target?.buckled_to())
		var/atom/movable/_tmp_buck_18 = target?.buckled_to()
		_tmp_buck_18.unbuckle_mob(target, force = TRUE)
	H.vore_selected.nom_atom(target)
	to_chat(target, span_warning("\The [H] quickly engulfs you, [H.vore_selected.vore_verb]ing you into their [H.vore_selected.get_belly_name()]!"))

/mob/living/carbon/human/proc/prot_hide()
	set name = "Hide Self"
	set desc = "Disperses your mass into a thin veil, making a trap to snatch prey with, or simply hide."
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/hide_self)

// --- Refactory ------------------------------------------------------------------------

/datum/protean_power/reform_limb
	name = "Ref - Single Limb"
	desc = "Rebuild or replace a single limb, assuming you have 2000 steel."
	icon_state = "limb"
	needs_turf = TRUE
	verb_path = /mob/living/carbon/human/proc/nano_partswap

/datum/protean_power/reform_limb/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!refactory)
		to_chat(H, span_warning("You don't have a working refactory module!"))
		return
	om_ask(H, /datum/om/prompt/choice/protean_power, PROC_REF(limb_chosen), message = "Pick the bodypart to change:", title = "Refactor - One Bodypart", choices = H.species.has_limbs, power = src, form = F)

/// A protean power's pick. Re-checked on the answer: the power can still be used.
/datum/om/prompt/choice/protean_power
	var/datum/protean_power/power
	var/datum/forms/protean/form
	/// The limb the pick is about, for the limb refactor.
	var/limb

/datum/om/prompt/choice/protean_power/valid()
	return power.can_use(answerer, form) ? null : "can't use"

/datum/om/prompt/confirm/protean_power
	var/datum/protean_power/power
	var/datum/forms/protean/form
	var/limb

/datum/om/prompt/confirm/protean_power/valid()
	return power.can_use(answerer, form) ? null : "can't use"

/datum/protean_power/reform_limb/proc/limb_chosen(datum/om/prompt/choice/protean_power/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/forms/protean/F = ask.form
	var/choice = ask.choice
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!refactory)
		return
	var/obj/item/organ/external/existing = H.organs_by_name[choice]
	if(!existing || existing.is_stump())
		regrow_limb(H, F, refactory, choice)
		return
	var/list/usable_manufacturers = list()
	for(var/company in GLOB.chargen_robolimbs)
		var/datum/robolimb/M = GLOB.chargen_robolimbs[company]
		if(!(choice in M.parts))
			continue
		if(H.species?.base_species in M.species_cannot_use)
			continue
		if(M.whitelisted_to && !(H.ckey in M.whitelisted_to))
			continue
		usable_manufacturers[company] = M
	if(!length(usable_manufacturers))
		return
	om_ask(H, /datum/om/prompt/choice/protean_power, PROC_REF(manufacturer_chosen), message = "Which manufacturer do you wish to mimic for this limb?", title = "Manufacturer for [choice]", choices = usable_manufacturers, power = src, form = F, limb = choice)

/datum/protean_power/reform_limb/proc/manufacturer_chosen(datum/om/prompt/choice/protean_power/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/obj/item/organ/external/eo = H.organs_by_name[ask.limb]
	if(!eo)
		return
	eo.robotize(ask.choice)
	H.update_icons_body()

/datum/protean_power/reform_limb/proc/regrow_limb(mob/living/carbon/human/H, datum/forms/protean/F, obj/item/organ/internal/nano/refactory/refactory, choice)
	if(refactory.get_stored_material(MAT_STEEL) < PER_LIMB_STEEL_COST)
		to_chat(H, span_warning("You're missing that limb, and need to store at least [PER_LIMB_STEEL_COST] steel to regenerate it."))
		return
	om_ask(H, /datum/om/prompt/confirm/protean_power, PROC_REF(regrow_limb_confirmed), message = "That limb is missing, do you want to regenerate it in exchange for [PER_LIMB_STEEL_COST] steel?", title = "Regenerate limb?", power = src, form = F, limb = choice)

/datum/protean_power/reform_limb/proc/regrow_limb_confirmed(datum/om/prompt/confirm/protean_power/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/datum/forms/protean/F = ask.form
	var/choice = ask.limb
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!refactory || !refactory.use_stored_material(MAT_STEEL, PER_LIMB_STEEL_COST))
		return
	F.set_form(/datum/form/protean_blob)
	H.active_regen = TRUE
	om_task_start(/datum/om/task/timed/reform_limb_regrow_limb_reform_limb, H, H, refactory = refactory, choice = choice)
	H.active_regen = FALSE

/datum/om/task/timed/reform_limb_regrow_limb_reform_limb
	duration = 5 SECONDS
	complete_proc = /datum/protean_power/reform_limb/proc/regrow_limb_reform_limb_done
	cancel_proc = /datum/protean_power/reform_limb/proc/regrow_limb_reform_limb_failed
	var/obj/item/organ/internal/nano/refactory/refactory
	var/choice

/datum/protean_power/reform_limb/proc/regrow_limb_reform_limb_done(datum/om/task/timed/reform_limb_regrow_limb_reform_limb/task)
	var/mob/living/carbon/human/H = task.actor
	var/choice = task.choice
	var/obj/item/organ/external/oldlimb = H.organs_by_name[choice]
	if(oldlimb)
		oldlimb.removed()
		qdel(oldlimb)
	var/list/limblist = H.species.has_limbs[choice]
	var/limbpath = limblist["path"]
	var/obj/item/organ/external/new_eo = new limbpath(H) // joins onto its parent limb
	new_eo.robotize(H.synthetic ? H.synthetic.company : null)
	new_eo.sync_colour_to_human(H)
	H.regenerate_icons()

/datum/protean_power/reform_limb/proc/regrow_limb_reform_limb_failed(datum/om/task/timed/reform_limb_regrow_limb_reform_limb/task)
	var/obj/item/organ/internal/nano/refactory/refactory = task.refactory
	refactory.add_stored_material(MAT_STEEL, PER_LIMB_STEEL_COST)

/mob/living/carbon/human/proc/nano_partswap()
	set name = "Ref - Single Limb"
	set desc = "Allows you to replace and reshape your limbs as you see fit."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/reform_limb)

/datum/protean_power/reform_body
	name = "Total Reassembly"
	desc = "Fully repair yourself or reload your appearance from whatever character slot you have loaded."
	icon_state = "body"
	verb_path = /mob/living/carbon/human/proc/nano_regenerate

/datum/protean_power/reform_body/proc/rebuild_done(mob/living/carbon/human/H)
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	var/datum/body/humanoid/nanoform/B = H.body
	if(!refactory || !istype(B) || !refactory.consume_stored_material(MAT_STEEL, TOTAL_REBUILD_STEEL_COST))
		return
	var/repaired = B.total_reassembly(TOTAL_REBUILD_STEEL_COST)
	log_game("PROTEAN: [key_name(H)] rebuilt themselves with Total Reassembly ([TOTAL_REBUILD_STEEL_COST] steel, [repaired] points repaired).")

/datum/protean_power/reform_body/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/question = {"Do you want to rebuild or reassemble yourself?
	Rebuilding will cost [TOTAL_REBUILD_STEEL_COST] steel and will rebuild all of your limbs and your cohesion, and spend the steel repairing your plating and wiring over a 40s period.
	Reassembling costs no steel and will copy the appearance data of your currently loaded save slot."}
	om_ask(H, /datum/om/prompt/choice/protean_power, PROC_REF(reform_chosen), power = src, form = F, title = "Reassembly", choices = list("Rebuild", "Reassemble", "Cancel"), buttons = TRUE, message = question)

/// Whether to include flavour text / OOC notes in a reassembly; carries the flavour answer.
/datum/om/prompt/choice/protean_power/reassemble_include
	title = "Reassembly"
	choices = list("Yes", "No", "Cancel")
	buttons = TRUE
	var/flavour

/datum/protean_power/reform_body/proc/reform_chosen(datum/om/prompt/choice/protean_power/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/input = ask.choice
	if(input == "Cancel")
		return
	if(input == "Rebuild")
		var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
		if(!refactory || refactory.get_stored_material(MAT_STEEL) < TOTAL_REBUILD_STEEL_COST)
			to_chat(H, span_warning("You do not have enough steel stored for this operation."))
			return
		to_chat(H, span_notify("You begin to rebuild. You will need to remain still."))
		om_do_after(H, 40 SECONDS, target = H, receiver = src, on_done = PROC_REF(rebuild_done), done_args = list(H))
		return
	om_ask(H, /datum/om/prompt/choice/protean_power/reassemble_include, PROC_REF(reassemble_flavour_chosen), message = "Include Flavourtext?", power = src, form = ask.form)

/datum/protean_power/reform_body/proc/reassemble_flavour_chosen(datum/om/prompt/choice/protean_power/reassemble_include/ask)
	if(ask.choice == "Cancel")
		return
	om_ask(ask.answerer, /datum/om/prompt/choice/protean_power/reassemble_include, PROC_REF(reassemble_answered), message = "Include OOC notes?", power = src, form = ask.form, flavour = ask.choice)

/datum/protean_power/reform_body/proc/reassemble_answered(datum/om/prompt/choice/protean_power/reassemble_include/ask)
	if(ask.choice == "Cancel")
		return
	var/mob/living/carbon/human/H = ask.answerer
	var/flavour = ask.flavour
	var/oocnotes = ask.choice
	to_chat(H, span_notify("You begin to reassemble. You will need to remain still."))
	H.visible_message(span_notify("[H] rapidly contorts and shifts!"), span_danger("You begin to reassemble."))
	om_task_start(/datum/om/task/timed/reform_body_activate_reform_body, H, H, flavour = flavour, oocnotes = oocnotes)

/datum/om/task/timed/reform_body_activate_reform_body
	duration = 4 SECONDS
	complete_proc = /datum/protean_power/reform_body/proc/activate_reform_body_done3
	var/flavour
	var/oocnotes

/datum/protean_power/reform_body/proc/activate_reform_body_done3(datum/om/task/timed/reform_body_activate_reform_body/task)
	var/mob/living/carbon/human/H = task.actor
	var/flavour = task.flavour
	var/oocnotes = task.oocnotes
	if(!(H.client?.prefs))
		return
	H.client.prefs.vanity_copy_to(H, FALSE, flavour == "Yes", oocnotes == "Yes", TRUE, FALSE)
	H.visible_message(span_notify("[H] adopts a new form!"), span_danger("You have reassembled."))

/mob/living/carbon/human/proc/nano_regenerate()
	set name = "Total Reassembly"
	set desc = "Fully repair yourself or reload your appearance from whatever character slot you have loaded."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/reform_body)

/datum/protean_power/copy_form
	name = "Copy Form"
	desc = "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them. (Without their name)."
	icon_state = "copy_form"
	verb_path = /mob/living/carbon/human/proc/nano_copy_body

/datum/protean_power/copy_form/proc/aggressive_grab_on(mob/living/carbon/human/H, mob/living/victim)
	for(var/obj/item/grab/G in contents_of(H))
		if(G.state >= GRAB_AGGRESSIVE && (!victim || G?.grab_target() == victim))
			return G
	return null

/datum/protean_power/copy_form/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/obj/item/grab/G = aggressive_grab_on(H)
	if(!G)
		to_chat(H, span_notice("You need to be aggressively grabbing someone before you can copy their form."))
		return
	var/mob/living/carbon/human/victim = G?.grab_target()
	if(!istype(victim))
		to_chat(H, span_warning("You can only perform this on human mobs!"))
		return
	if(!victim.client)
		to_chat(H, span_notice("The person you try this on must have a client!"))
		return
	to_chat(H, span_notice("Waiting for other person's consent."))
	om_flow_start(/datum/om/flow/protean_copy_form, H, victim, power = src)
	return TRUE

/// The victim consents, then the protean chooses whether to copy their flavour text.
/datum/om/flow/protean_copy_form
	var/datum/protean_power/copy_form/power
	var/consented = FALSE

/datum/om/flow/protean_copy_form/ended(reason)
	if(actor && !consented && (reason == "declined" || reason == "cancelled"))
		to_chat(actor, span_notice("They declined your request."))

/datum/om/flow/protean_copy_form/start()
	om_ask(target, /datum/om/prompt/confirm/copy_body_consent, PROC_REF(consent_given))

/datum/om/flow/protean_copy_form/proc/consent_given(datum/om/prompt/confirm/ask)
	consented = TRUE
	om_ask(actor, /datum/om/prompt/choice, PROC_REF(flavour_chosen), message = "Copy [target]'s flavourtext?", title = "Copy Form", choices = list("Yes", "No", "Cancel"), buttons = TRUE)

/datum/om/flow/protean_copy_form/proc/flavour_chosen(datum/om/prompt/choice/ask)
	if(ask.choice == "Cancel")
		return
	power.copy_agreed(actor, target, ask.choice)

/datum/protean_power/copy_form/proc/copy_agreed(mob/living/carbon/human/H, mob/living/carbon/human/victim, input)
	if(!aggressive_grab_on(H, victim))
		to_chat(H, span_warning("You lost your grip on [victim]!"))
		return
	to_chat(H, span_notify("You begin to reassemble into [victim]. You will need to remain still."))
	H.visible_message(span_notify("[H] rapidly contorts and shifts!"), span_danger("You begin to reassemble into [victim]."))
	om_task_start(/datum/om/task/timed/copy_form_activate_copy_form, H, H, victim = victim, input = input)
	return TRUE

/datum/om/task/timed/copy_form_activate_copy_form
	duration = 4 SECONDS
	complete_proc = /datum/protean_power/copy_form/proc/activate_copy_form_done4
	var/mob/living/carbon/human/victim
	var/input

/datum/protean_power/copy_form/proc/activate_copy_form_done4(datum/om/task/timed/copy_form_activate_copy_form/task)
	var/mob/living/carbon/human/H = task.actor
	var/mob/living/carbon/human/victim = task.victim
	var/input = task.input
	if(!aggressive_grab_on(H, victim))
		to_chat(H, span_warning("You lost your grip on [victim]!"))
		return
	if(H.client)
		H.transform_into_other_human(victim, new /datum/human_transform_options(copy_flavour = (input == "Yes"), convert_to_prosthetics = TRUE, apply_bloodtype = FALSE))
		H.visible_message(span_notify("[H] adopts the form of [victim]!"), span_danger("You have reassembled into [victim]."))

/mob/living/carbon/human/proc/nano_copy_body()
	set name = "Copy Form"
	set desc = "If you are aggressively grabbing someone, with their consent, you can turn into a copy of them. (Without their name)."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/copy_form)

/datum/protean_power/metal_nom
	name = "Ref - Store Metals"
	desc = "Store the metal you're holding. Your refactory can only store steel."
	icon_state = "metal"
	verb_path = /mob/living/carbon/human/proc/nano_metalnom

/datum/protean_power/metal_nom/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!refactory)
		to_chat(H, span_warning("You don't have a working refactory module!"))
		return
	var/obj/item/stack/material/matstack = H.get_active_hand()
	if(!istype(matstack))
		to_chat(H, span_warning("You aren't holding a stack of materials in your active hand!"))
		return
	var/substance = matstack.material.name
	if(!(substance in PROTEAN_EDIBLE_MATERIALS))
		to_chat(H, span_warning("You can't process [substance]!"))
		return
	om_ask(H, /datum/om/prompt/number/protean_store, PROC_REF(store_amount_chosen), message = "How much do you want to store? (0-[matstack.get_amount()])", max = matstack.get_amount(), stack = matstack)

/// How much of the held stack to store. Re-checked on the answer: the stack is still in the
/// active hand and has that much.
/datum/om/prompt/number/protean_store
	title = "Select amount"
	var/obj/item/stack/material/stack

/datum/om/prompt/number/protean_store/valid()
	if(stack != answerer.get_active_hand() || number > stack.get_amount())
		return "stack changed"
	return null

/datum/protean_power/metal_nom/proc/store_amount_chosen(datum/om/prompt/number/protean_store/ask)
	var/mob/living/carbon/human/H = ask.answerer
	var/obj/item/stack/material/matstack = ask.stack
	var/howmuch = ask.number
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!howmuch || !refactory)
		return
	var/substance = matstack.material.name
	var/actually_added = refactory.add_stored_material(substance, howmuch * matstack.perunit)
	matstack.use(CEILING((actually_added / matstack.perunit), 1))
	if(actually_added && actually_added < howmuch)
		to_chat(H, span_warning("Your refactory module is now full, so only [actually_added] units were stored."))
		H.visible_message(span_notice("[H] nibbles some of the [substance] right off the stack!"))
	else if(actually_added)
		to_chat(H, span_notice("You store [actually_added] units of [substance]."))
		H.visible_message(span_notice("[H] devours some of the [substance] right off the stack!"))
	else
		to_chat(H, span_notice("You're completely capped out on [substance]!"))

/mob/living/carbon/human/proc/nano_metalnom()
	set name = "Ref - Store Metals"
	set desc = "If you're holding a stack of material, you can consume some and store it for later."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/metal_nom)

// --- Appearance ------------------------------------------------------------------------

/datum/protean_power/appearance_switch
	name = "Blob Appearance"
	desc = "Toggle your blob appearance. Also affects your worn appearance."
	icon_state = "switch"
	usable_in_rig = TRUE
	verb_path = /mob/living/carbon/human/proc/appearance_switch

/datum/protean_power/appearance_switch/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	var/datum/form/protean_blob/B = F.blob_form()
	if(B.edit_appearance(H) && F.current == B)
		F.refresh_appearance()

/mob/living/carbon/human/proc/appearance_switch()
	set name = "Switch Blob Appearance"
	set desc = "Allows a protean blob to switch its outwards appearance."
	set hidden = TRUE
	activate_protean_power(/datum/protean_power/appearance_switch)

/datum/protean_power/chest_transparency
	name = "body transparency toggle (All but head)"
	desc = "Makes everything but your head transparent!"
	icon = 'icons/obj/slimeborg/slimecore.dmi'
	icon_state = "core"
	allowed_forms = FORM_FLAG_HUMAN
	verb_path = /mob/living/carbon/human/proc/chest_transparency_toggle

/datum/protean_power/chest_transparency/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	H.toggle_limb_transparency(include_head = FALSE)

/mob/living/carbon/human/proc/chest_transparency_toggle()
	set name = "transparency toggle (chest only)"
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/chest_transparency)

/datum/protean_power/transparency
	name = "Toggle Transparency"
	desc = "transparency toggle for your entire body"
	icon = 'icons/obj/slimeborg/slimecore.dmi'
	icon_state = "core"
	allowed_forms = FORM_FLAG_HUMAN
	verb_path = /mob/living/carbon/human/proc/transparency_toggle

/datum/protean_power/transparency/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	H.toggle_limb_transparency(include_head = TRUE)

/mob/living/carbon/human/proc/transparency_toggle()
	set name = "Toggle Transparency"
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/transparency)

/mob/living/carbon/human/proc/toggle_limb_transparency(include_head)
	if(!COOLDOWN_FINISHED(src, last_special))
		return
	COOLDOWN_START(src, last_special, 5 SECONDS)
	for(var/obj/item/organ/external/limb as anything in organs)
		if(!include_head && limb.organ_tag == BP_HEAD)
			continue
		limb.transparent = !limb.transparent
	visible_message(span_notice("\The [src]'s internal composition seems to change."))
	update_icons_body()
	update_hair()

/datum/protean_power/absorb_implant
	name = "Absorb Implant"
	desc = "Absorb an implant into your system."
	icon = 'icons/obj/surgery.dmi'
	icon_state = "heart-on"
	allowed_forms = FORM_FLAG_HUMAN
	verb_path = /mob/living/carbon/human/proc/absorb_implant

/datum/protean_power/absorb_implant/activate(mob/living/carbon/human/H, datum/forms/protean/F)
	if(!COOLDOWN_FINISHED(H, last_special))
		return
	COOLDOWN_START(H, last_special, 5 SECONDS)
	var/obj/item/organ/internal/augment/A = H.get_active_hand()
	if(!istype(A))
		to_chat(H, span_danger("You cannot integrate this into your body."))
		return
	if(!(ORGAN_NANOFORM in A.target_parent_classes))
		to_chat(H, span_danger("This implant is incompatible with our nanoform."))
		return
	var/obj/item/organ/external/target_organ = H.get_organ(H.zone_sel.selecting)
	if(!istype(target_organ) || target_organ.is_stump())
		to_chat(H, span_danger("Your [target_organ] is currently unsuitable for implants."))
		return
	if(target_organ.organ_tag != A.parent_organ)
		to_chat(H, span_danger("[A] does not go in [target_organ]."))
		return
	if(!H.unEquip(A))
		to_chat(H, span_danger("[A] is stuck to your hand."))
		return
	A.replaced(H, target_organ)
	to_chat(H, span_notice("You absorb [A] into your [target_organ]."))
	log_admin("[key_name(H)] protean self-implanted [A].")

/mob/living/carbon/human/proc/absorb_implant()
	set name = "Absorb Implant"
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/absorb_implant)

#undef PER_LIMB_STEEL_COST
#undef TOTAL_REBUILD_STEEL_COST

DECLARE_REF(/obj/effect/protean_power_button, "power", BACK, "button")
