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

/datum/protean_power/Destroy()
	QDEL_NULL(button)
	return ..()

/datum/protean_power/proc/try_activate(mob/living/carbon/human/H)
	if(!istype(H))
		return FALSE
	var/datum/component/forms/protean/F = H.GetComponent(/datum/component/forms/protean)
	if(!F)
		to_chat(H, span_warning("You don't have a nanite swarm to do that with."))
		return FALSE
	if(!can_use(H, F))
		return FALSE
	activate(H, F)
	return TRUE

/datum/protean_power/proc/can_use(mob/living/carbon/human/H, datum/component/forms/protean/F)
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

/datum/protean_power/proc/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
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

/obj/effect/protean_power_button/Destroy()
	power = null
	return ..()

/obj/effect/protean_power_button/Click(location, control, params)
	var/list/modifiers = params2list(params)
	var/mob/living/carbon/human/H = usr
	if(!istype(H) || !power)
		return
	if(modifiers["shift"])
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

/datum/protean_power/blobform/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	if(F.is_form(/datum/form/protean_blob))
		if(!do_after(H, 2 SECONDS, target = H))
			to_chat(H, span_warning("You must remain still to reshape yourself!"))
			return
		if(F.form_control_check())
			F.set_form(/datum/form/human)
		return
	if(H.get_equipped_item(SLOT_ID_HANDCUFFED))
		to_chat(H, span_warning("You can't do this while handcuffed!"))
		return
	to_chat(H, span_notice("You begin to disassociate your form."))
	if(!do_after(H, 2 SECONDS, target = H))
		to_chat(H, span_warning("You must remain still to blobform!"))
		return
	if(F.form_control_check())
		F.set_form(/datum/form/protean_blob)

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

/datum/protean_power/change_volume/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	H.set_size()

/// Species inherent verb: pick which species' clothing fit (and sprites) to use.
/mob/living/carbon/human/proc/nano_change_fitting()
	set name = "Change Species Fit"
	set desc = "Tweak your shape to change what suits you fit into (and their sprites!)."
	set category = "Abilities.Protean"

	if(stat)
		to_chat(src, span_warning("You must be awake and standing to perform this action!"))
		return
	var/new_species = tgui_input_list(src, "Please select a species to emulate.", "Shapeshifter Body", list(species?.vanity_base_fit) | species?.get_valid_shapeshifter_forms())
	if(!new_species || stat || !species)
		return
	species.base_species = new_species
	regenerate_icons()

/datum/protean_power/hide_self
	name = "Hide Self"
	desc = "Disperse your mass into a thin veil, making a trap to snatch prey with, or simply hide."
	allowed_forms = FORM_FLAG_PROTEAN_BLOB
	needs_turf = TRUE
	in_stat_panel = FALSE
	verb_path = /mob/living/carbon/human/proc/prot_hide

/datum/protean_power/hide_self/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
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
	if(target.buckled)
		target.buckled.unbuckle_mob(target, force = TRUE)
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

/datum/protean_power/reform_limb/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
	if(!refactory)
		to_chat(H, span_warning("You don't have a working refactory module!"))
		return
	var/choice = tgui_input_list(H, "Pick the bodypart to change:", "Refactor - One Bodypart", H.species.has_limbs)
	if(!choice || !can_use(H, F))
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
	var/manu_choice = tgui_input_list(H, "Which manufacturer do you wish to mimic for this limb?", "Manufacturer for [choice]", usable_manufacturers)
	if(!manu_choice)
		return
	var/obj/item/organ/external/eo = H.organs_by_name[choice]
	if(!eo)
		return
	eo.robotize(manu_choice)
	H.update_icons_body()

/datum/protean_power/reform_limb/proc/regrow_limb(mob/living/carbon/human/H, datum/component/forms/protean/F, obj/item/organ/internal/nano/refactory/refactory, choice)
	if(refactory.get_stored_material(MAT_STEEL) < PER_LIMB_STEEL_COST)
		to_chat(H, span_warning("You're missing that limb, and need to store at least [PER_LIMB_STEEL_COST] steel to regenerate it."))
		return
	if(tgui_alert(H, "That limb is missing, do you want to regenerate it in exchange for [PER_LIMB_STEEL_COST] steel?", "Regenerate limb?", list("Yes", "No")) != "Yes")
		return
	if(!can_use(H, F) || !refactory.use_stored_material(MAT_STEEL, PER_LIMB_STEEL_COST))
		return
	F.set_form(/datum/form/protean_blob)
	H.active_regen = TRUE
	if(do_after(H, 5 SECONDS, target = H))
		var/obj/item/organ/external/oldlimb = H.organs_by_name[choice]
		if(oldlimb)
			oldlimb.removed()
			qdel(oldlimb)
		var/list/limblist = H.species.has_limbs[choice]
		var/limbpath = limblist["path"]
		var/obj/item/organ/external/new_eo = new limbpath(H)
		H.organs_by_name[choice] = new_eo
		new_eo.robotize(H.synthetic ? H.synthetic.company : null)
		new_eo.sync_colour_to_human(H)
		H.regenerate_icons()
	else
		refactory.add_stored_material(MAT_STEEL, PER_LIMB_STEEL_COST)
	H.active_regen = FALSE

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

/datum/protean_power/reform_body/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	var/input = tgui_alert(H, {"Do you want to rebuild or reassemble yourself?
	Rebuilding will cost [TOTAL_REBUILD_STEEL_COST] steel and will rebuild all of your limbs as well as repair all damage over a 40s period.
	Reassembling costs no steel and will copy the appearance data of your currently loaded save slot."}, "Reassembly", list("Rebuild", "Reassemble", "Cancel"))
	if(!input || input == "Cancel" || !can_use(H, F))
		return
	if(input == "Rebuild")
		var/obj/item/organ/internal/nano/refactory/refactory = H.nano_get_refactory()
		if(!refactory || refactory.get_stored_material(MAT_STEEL) < TOTAL_REBUILD_STEEL_COST)
			to_chat(H, span_warning("You do not have enough steel stored for this operation."))
			return
		to_chat(H, span_notify("You begin to rebuild. You will need to remain still."))
		if(!do_after(H, 40 SECONDS, target = H))
			return
		refactory = H.nano_get_refactory()
		if(!refactory || !refactory.consume_stored_material(MAT_STEEL, refactory.get_stored_material(MAT_STEEL)))
			return
		H.fully_heal()
		log_game("PROTEAN: [key_name(H)] rebuilt themselves with Total Reassembly.")
		return
	var/flavour = tgui_alert(H, "Include Flavourtext?", "Reassembly", list("Yes", "No", "Cancel"))
	if(!flavour || flavour == "Cancel")
		return
	var/oocnotes = tgui_alert(H, "Include OOC notes?", "Reassembly", list("Yes", "No", "Cancel"))
	if(!oocnotes || oocnotes == "Cancel")
		return
	to_chat(H, span_notify("You begin to reassemble. You will need to remain still."))
	H.visible_message(span_notify("[H] rapidly contorts and shifts!"), span_danger("You begin to reassemble."))
	if(do_after(H, 4 SECONDS, target = H) && H.client?.prefs)
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
	for(var/obj/item/grab/G in H)
		if(G.state >= GRAB_AGGRESSIVE && (!victim || G.affecting == victim))
			return G
	return null

/datum/protean_power/copy_form/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	var/obj/item/grab/G = aggressive_grab_on(H)
	if(!G)
		to_chat(H, span_notice("You need to be aggressively grabbing someone before you can copy their form."))
		return
	var/mob/living/carbon/human/victim = G.affecting
	if(!istype(victim))
		to_chat(H, span_warning("You can only perform this on human mobs!"))
		return
	if(!victim.client)
		to_chat(H, span_notice("The person you try this on must have a client!"))
		return
	to_chat(H, span_notice("Waiting for other person's consent."))
	if(tgui_alert(victim, "Allow [H] to copy what you look like?", "Consent", list("Yes", "No")) != "Yes")
		to_chat(H, span_notice("They declined your request."))
		return
	var/input = tgui_alert(H, "Copy [victim]'s flavourtext?", "Copy Form", list("Yes", "No", "Cancel"))
	if(!input || input == "Cancel")
		return
	if(!aggressive_grab_on(H, victim))
		to_chat(H, span_warning("You lost your grip on [victim]!"))
		return
	to_chat(H, span_notify("You begin to reassemble into [victim]. You will need to remain still."))
	H.visible_message(span_notify("[H] rapidly contorts and shifts!"), span_danger("You begin to reassemble into [victim]."))
	if(!do_after(H, 4 SECONDS, target = H))
		return
	if(!aggressive_grab_on(H, victim))
		to_chat(H, span_warning("You lost your grip on [victim]!"))
		return
	if(H.client)
		H.transform_into_other_human(victim, FALSE, input == "Yes", TRUE, FALSE)
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

/datum/protean_power/metal_nom/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
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
	var/howmuch = tgui_input_number(H, "How much do you want to store? (0-[matstack.get_amount()])", "Select amount", null, matstack.get_amount())
	if(!howmuch || matstack != H.get_active_hand() || howmuch > matstack.get_amount())
		return
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

/datum/protean_power/appearance_switch/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
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

/datum/protean_power/chest_transparency/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
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

/datum/protean_power/transparency/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	H.toggle_limb_transparency(include_head = TRUE)

/mob/living/carbon/human/proc/transparency_toggle()
	set name = "Toggle Transparency"
	set category = "Abilities.Protean"
	activate_protean_power(/datum/protean_power/transparency)

/mob/living/carbon/human/proc/toggle_limb_transparency(include_head)
	if(world.time < last_special)
		return
	last_special = world.time + 5 SECONDS
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

/datum/protean_power/absorb_implant/activate(mob/living/carbon/human/H, datum/component/forms/protean/F)
	if(world.time < H.last_special)
		return
	H.last_special = world.time + 5 SECONDS
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
