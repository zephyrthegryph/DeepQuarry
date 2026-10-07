/mob/living/carbon/human/examine(mob/user)
	SHOULD_CALL_PARENT(FALSE) // We build the list ourselves.

	if(alpha <= EFFECTIVE_INVIS)
		return src.loc.examine(user) // Returns messages as if they examined wherever the human was

	var/looks_synth = looksSynthetic()
	var/list/coverage = examine_coverage()
	var/skip_gear = coverage[1]
	var/skip_body = coverage[2]

	//This is what hides what
	var/list/hidden = list(
		BP_GROIN = skip_body & EXAMINE_SKIPGROIN,
		BP_TORSO = skip_body & EXAMINE_SKIPBODY,
		BP_HEAD  = skip_body & EXAMINE_SKIPHEAD,
		BP_L_ARM = skip_body & EXAMINE_SKIPARMS,
		BP_R_ARM = skip_body & EXAMINE_SKIPARMS,
		BP_L_HAND= skip_body & EXAMINE_SKIPHANDS,
		BP_R_HAND= skip_body & EXAMINE_SKIPHANDS,
		BP_L_FOOT= skip_body & EXAMINE_SKIPFEET,
		BP_R_FOOT= skip_body & EXAMINE_SKIPFEET,
		BP_L_LEG = skip_body & EXAMINE_SKIPLEGS,
		BP_R_LEG = skip_body & EXAMINE_SKIPLEGS)

	var/list/msg = list("This is [icon2html(src, user.client)] <EM>[src.name]</EM>[examine_name_ender(skip_gear, skip_body, looks_synth)]")
	msg += examine_gear_lines(user, skip_gear, skip_body)
	msg += examine_status_lines(user, hidden)
	var/list/limb_result = examine_limb_lines(user, hidden, looks_synth)
	msg += limb_result[1]
	var/applying_pressure = limb_result[2]
	msg += examine_diagnosis_lines()
	msg += examine_record_lines(user)
	msg += examine_profile_lines()

	msg = list(span_info(jointext(msg, "<br>")))
	if(applying_pressure)
		msg += applying_pressure

	if(pose)
		if(!findtext(pose, regex("\[.?!]$"))) // Will be zero if the last character is not a member of [.?!]
			pose = addtext(pose,".") //Makes sure all emotes end with a period.
		msg += "<br>[p_They()] [pose]" //<br> intentional, extra gap.

	return msg

/// What worn gear hides: list(EXAMINE_SKIP* gear flags, EXAMINE_SKIP* body flags).
/mob/living/carbon/human/proc/examine_coverage()
	var/skip_gear = 0
	var/skip_body = 0
	//exosuits and helmets obscure our view and stuff.
	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(suit)
		if(suit.flags_inv & HIDESUITSTORAGE)
			skip_gear |= EXAMINE_SKIPSUITSTORAGE
		if(suit.flags_inv & HIDEJUMPSUIT)
			skip_body |= EXAMINE_SKIPARMS | EXAMINE_SKIPLEGS | EXAMINE_SKIPBODY | EXAMINE_SKIPGROIN
			skip_gear |= EXAMINE_SKIPJUMPSUIT | EXAMINE_SKIPTIE | EXAMINE_SKIPHOLSTER
		else if(suit.flags_inv & HIDETIE)
			skip_gear |= EXAMINE_SKIPTIE | EXAMINE_SKIPHOLSTER
		else if(suit.flags_inv & HIDEHOLSTER)
			skip_gear |= EXAMINE_SKIPHOLSTER
		if(suit.flags_inv & HIDESHOES)
			skip_gear |= EXAMINE_SKIPSHOES
			skip_body |= EXAMINE_SKIPFEET
		if(suit.flags_inv & HIDEGLOVES)
			skip_gear |= EXAMINE_SKIPGLOVES
			skip_body |= EXAMINE_SKIPHANDS

	var/obj/item/uniform = get_equipped_item(SLOT_ID_UNIFORM)
	if(uniform)
		if(uniform.body_parts_covered & LEGS)
			skip_body |= EXAMINE_SKIPLEGS
		if(uniform.body_parts_covered & ARMS)
			skip_body |= EXAMINE_SKIPARMS
		if(uniform.body_parts_covered & UPPER_TORSO)
			skip_body |= EXAMINE_SKIPBODY
		if(uniform.body_parts_covered & LOWER_TORSO)
			skip_body |= EXAMINE_SKIPGROIN

	var/obj/item/gloves = get_equipped_item(SLOT_ID_GLOVES)
	if(gloves && (gloves.body_parts_covered & HANDS))
		skip_body |= EXAMINE_SKIPHANDS

	var/obj/item/shoes = get_equipped_item(SLOT_ID_SHOES)
	if(shoes && (shoes.body_parts_covered & FEET))
		skip_body |= EXAMINE_SKIPFEET

	var/obj/item/head = get_equipped_item(SLOT_ID_HEAD)
	if(head)
		if(head.flags_inv & HIDEMASK)
			skip_gear |= EXAMINE_SKIPMASK
		if(head.flags_inv & HIDEEYES)
			skip_gear |= EXAMINE_SKIPEYEWEAR
			skip_body |= EXAMINE_SKIPEYES
		if(head.flags_inv & HIDEEARS)
			skip_gear |= EXAMINE_SKIPEARS
		if(head.flags_inv & HIDEFACE)
			skip_body |= EXAMINE_SKIPFACE

	var/obj/item/mask = get_equipped_item(SLOT_ID_MASK)
	if(mask && (mask.flags_inv & HIDEFACE))
		skip_body |= EXAMINE_SKIPFACE
	return list(skip_gear, skip_body)

/// ", a <species>" after the name, when the face or uniform shows it.
/mob/living/carbon/human/proc/examine_name_ender(skip_gear, skip_body, looks_synth)
	if((skip_gear & EXAMINE_SKIPJUMPSUIT) && (skip_body & EXAMINE_SKIPFACE))
		return ""
	if(custom_species)
		return ", a " + span_bold("[src.custom_species]")
	if(looks_synth)
		var/use_gender = "a synthetic"
		if(gender == MALE)
			use_gender = "an android"
		else if(gender == FEMALE)
			use_gender = "a gynoid"
		return ", " + span_bold(span_gray("[use_gender]!")) + "[species.get_additional_examine_text(src)]"
	if(species.name != "Human")
		return ", " + span_bold("<font color='[species.get_flesh_colour(src)]'>\a [species.get_examine_name()]!</font>") + "[species.get_additional_examine_text(src)]"
	return ""

/// One worn-item line: "<lead> <icon> <item><where>.<extra>", or a warning when the item is stained.
/mob/living/carbon/human/proc/examine_worn_line(obj/item/I, mob/user, lead, where, extra = "")
	var/link = "<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[I]'>"
	if(I.forensic_data?.has_blooddna())
		var/stain = (dq_get_blood_color(I) != "#030303") ? "blood" : "oil"
		return span_warning("[lead] [icon2html(I, user.client)] [I.gender == PLURAL ? "some" : "a"] [stain]-stained [link][I.name]</a>[where]![extra]")
	return "[lead] [icon2html(I, user.client)] [link]\a [I]</a>[where].[extra]"

/// ". Attached to it is ..." for a garment's visible accessories.
/mob/living/carbon/human/proc/examine_accessory_text(list/accessories, skip_holsters = FALSE, linked = TRUE)
	if(!LAZYLEN(accessories))
		return null
	var/list/accessory_descs = list()
	for(var/obj/item/clothing/accessory/A in accessories)
		if(skip_holsters)
			if(A.show_examine && !istype(A, /obj/item/clothing/accessory/holster)) // If we're supposed to skip holsters, actually skip them
				accessory_descs += "\a [A]"
		else if(!linked || (A.concealed_holster == 0 && A.show_examine))
			accessory_descs += "<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[A]'>\a [A]</a>"
	return ". Attached to it is [lowertext(english_list(accessory_descs))]."

/// Lines for everything worn or held that isn't hidden.
/mob/living/carbon/human/proc/examine_gear_lines(mob/user, skip_gear, skip_body)
	. = list()
	var/obj/item/I

	I = get_equipped_item(SLOT_ID_UNIFORM)
	if(I && !(skip_gear & EXAMINE_SKIPJUMPSUIT) && I.show_examine)
		var/tie_msg
		if(istype(I, /obj/item/clothing/under) && !(skip_gear & EXAMINE_SKIPTIE))
			var/obj/item/clothing/under/U = I
			tie_msg = examine_accessory_text(U.accessories, skip_holsters = (skip_gear & EXAMINE_SKIPHOLSTER))
		. += examine_worn_line(I, user, "[p_Theyre()] wearing", "", tie_msg)

	I = get_equipped_item(SLOT_ID_HEAD)
	if(I && !(skip_gear & EXAMINE_SKIPHELMET) && I.show_examine)
		. += examine_worn_line(I, user, "[p_Theyre()] wearing", " on [p_their()] head")

	var/obj/item/suit = get_equipped_item(SLOT_ID_SUIT)
	if(suit)
		var/tie_msg
		if(istype(suit, /obj/item/clothing/suit))
			var/obj/item/clothing/suit/S = suit
			tie_msg = examine_accessory_text(S.accessories, linked = FALSE)
		. += examine_worn_line(suit, user, "[p_Theyre()] wearing", "", tie_msg)
		I = get_equipped_item(SLOT_ID_SUIT_STORAGE)
		if(I && !(skip_gear & EXAMINE_SKIPSUITSTORAGE) && I.show_examine)
			. += examine_worn_line(I, user, "[p_Theyre()] carrying", " on [p_their()] [suit.name]")

	I = get_equipped_item(SLOT_ID_BACK)
	if(I && !(skip_gear & EXAMINE_SKIPBACKPACK) && I.show_examine)
		. += examine_worn_line(I, user, "[p_They()] [p_have()]", " on [p_their()] back")

	I = get_equipped_item(SLOT_ID_HAND_L)
	if(I && I.show_examine)
		. += examine_worn_line(I, user, "[p_Theyre()] holding", " in [p_their()] left hand")

	I = get_equipped_item(SLOT_ID_HAND_R)
	if(I && I.show_examine)
		. += examine_worn_line(I, user, "[p_Theyre()] holding", " in [p_their()] right hand")

	I = get_equipped_item(SLOT_ID_GLOVES)
	if(I && !(skip_gear & EXAMINE_SKIPGLOVES) && I.show_examine)
		var/gloves_acc_msg
		if(istype(I, /obj/item/clothing/gloves))
			var/obj/item/clothing/gloves/G = I
			gloves_acc_msg = examine_accessory_text(G.accessories, linked = FALSE)
		. += examine_worn_line(I, user, "[p_They()] [p_have()]", " on [p_their()] hands", gloves_acc_msg)
	else if(forensic_data?.has_blooddna() && !(skip_body & EXAMINE_SKIPHANDS))
		. += span_warning("[p_They()] [p_have()] [(hand_blood_color != SYNTH_BLOOD_COLOUR) ? "blood" : "oil"]-stained hands!")

	I = get_equipped_item(SLOT_ID_HANDCUFFED)
	if(I && I.show_examine)
		if(istype(I, /obj/item/handcuffs/cable))
			. += span_warning("[p_Theyre()] [icon2html(I, user.client)] restrained with cable!")
		else
			. += span_warning("[p_Theyre()] [icon2html(I, user.client)] handcuffed!")

	var/atom/buckled_thing = buckled_to()
	if(buckled_thing)
		. += span_warning("[p_Theyre()] [icon2html(buckled_thing, user.client)] buckled to [buckled_thing]!")

	I = get_equipped_item(SLOT_ID_BELT)
	if(I && !(skip_gear & EXAMINE_SKIPBELT) && I.show_examine)
		. += examine_worn_line(I, user, "[p_They()] [p_have()]", " about [p_their()] waist")

	I = get_equipped_item(SLOT_ID_SHOES)
	if(I && !(skip_gear & EXAMINE_SKIPSHOES) && I.show_examine)
		. += examine_worn_line(I, user, "[p_Theyre()] wearing", " on [p_their()] feet")
	else if(feet_blood_DNA && !(skip_body & EXAMINE_SKIPHANDS))
		. += span_warning("[p_They()] [p_have()] [(feet_blood_color != SYNTH_BLOOD_COLOUR) ? "blood" : "oil"]-stained feet!")

	I = get_equipped_item(SLOT_ID_MASK)
	if(I && !(skip_gear & EXAMINE_SKIPMASK) && I.show_examine)
		var/descriptor = " on [p_their()] face"
		if(istype(I, /obj/item/grenade) && check_has_mouth())
			descriptor = " in [p_their()] mouth"
		. += examine_worn_line(I, user, "[p_They()] [p_have()]", descriptor)

	I = get_equipped_item(SLOT_ID_EYES)
	if(I && !(skip_gear & EXAMINE_SKIPEYEWEAR) && I.show_examine)
		. += examine_worn_line(I, user, "[p_They()] [p_have()]", " covering [p_their()] eyes")

	I = get_equipped_item(SLOT_ID_EAR_L)
	if(I && !(skip_gear & EXAMINE_SKIPEARS) && I.show_examine)
		. += "[p_They()] [p_have()] [icon2html(I, user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[I]'>\a [I]</a> on [p_their()] left ear."

	I = get_equipped_item(SLOT_ID_EAR_R)
	if(I && !(skip_gear & EXAMINE_SKIPEARS) && I.show_examine)
		. += "[p_They()] [p_have()] [icon2html(I, user.client)] <a href='byond://?src=\ref[src];lookitem_desc_only=\ref[I]'>\a [I]</a> on [p_their()] right ear."

	I = get_equipped_item(SLOT_ID_ID)
	if(I && I.show_examine)
		. += "[p_Theyre()] wearing [icon2html(I, user.client)]<a href='byond://?src=\ref[src];lookitem_desc_only=\ref[I]'>\a [I]</a>."

/// Jitters, splints, vore and size lines, responsiveness, fire and SSD.
/mob/living/carbon/human/proc/examine_status_lines(mob/user, list/hidden)
	. = list()
	var/jitter = status_units(STAT_JITTERY)
	if(jitter >= 300)
		. += span_boldwarning("[p_Theyre()] convulsing violently!")
	else if(jitter >= 200)
		. += span_warning("[p_Theyre()] extremely jittery.")
	else if(jitter >= 100)
		. += span_warning("[p_Theyre()] twitching ever so slightly.")

	for(var/organ in BP_ALL)
		var/obj/item/organ/external/o = get_organ(organ)
		if(o && o.splinted && o.splinted.loc == o)
			. += span_warning("[p_They()] [p_have()] \a [o.splinted] on [p_their()] [o.name]!")

	if(suiciding)
		. += span_warning("[p_They()] appears to have commited suicide... there is no hope of recovery.")

	var/list/vorestrings = list()
	vorestrings += examine_weight()
	vorestrings += examine_nutrition()
	vorestrings += formatted_vore_examine()
	vorestrings += examine_pickup_size()
	vorestrings += examine_step_size()
	vorestrings += examine_nif()
	vorestrings += examine_chimera()
	vorestrings += examine_body_writing(hidden)
	for(var/entry in vorestrings)
		if(entry == "" || entry == null)
			vorestrings -= entry
	. += vorestrings

	if(has_mutation(mSmallsize))
		. += "[p_Theyre()] very short!"

	if(src.stat || (status_flags & FAKEDEATH))
		. += span_warning("[p_Theyre()] not responding to anything around [p_them()] and seems to be asleep.")
		var/obj/item/organ/internal/lungs/L = organ_in(O_LUNGS)
		if(((stat == DEAD || losebreath || !L || (status_flags & FAKEDEATH)) && get_dist(user, src) <= 3))
			. += span_warning("[p_They()] [user.p_do()] not appear to be breathing.")
		if(ishuman(user) && !user.stat && Adjacent(user))
			act_message(user, src, MSG_SELF(span_infoplain("You check %T%'s pulse.")), MSG_OTHERS(span_infoplain(span_bold("%U%") + " checks %T%'s pulse.")))
		after(src, 1.5 SECONDS, PROC_REF(pulse_check_result), with = list(user), keeps_dead = TRUE)

	if(fire_stacks)
		. += "[p_Theyre()] covered in some liquid."
	if(on_fire)
		. += span_warning("[p_Theyre()] on fire!.")

	. += examine_ssd_lines()

/// Sleep-disorder, AFK and disconnect lines.
/mob/living/carbon/human/proc/examine_ssd_lines()
	. = list()
	var/ssd_msg = species.get_ssd(src)
	if(!ssd_msg || (should_have_organ(O_BRAIN) && !has_brain()) || stat == DEAD || (status_flags & FAKEDEATH))
		return
	if(!key)
		. += span_deadsay("[p_Theyre()] [ssd_msg]. It doesn't look like [p_theyre()] waking up anytime soon.")
	else if(!client)
		. += span_deadsay("[p_Theyre()] [ssd_msg].")
	if(client && away_from_keyboard && manual_afk)
		. += "\[Away From Keyboard for [round((client.inactivity/10)/60)] minutes\]"
	else if(client && ((client.inactivity / 10) / 60 > 10)) //10 Minutes
		. += "\[Inactive for [round((client.inactivity/10)/60)] minutes\]"
	else if(disconnect_time)
		. += "\[Disconnected/ghosted [round(((world.realtime - disconnect_time)/10)/60)] minutes ago\]"

/// Visible limb state: missing limbs and stumps, prostheses, wounds, dislocations, fractures,
/// necrosis, bleeding and protruding implants. Infection is not read here: it reaches examine
/// as the glance diagnosis' signs. Returns list(lines, applying-pressure line).
/mob/living/carbon/human/proc/examine_limb_lines(mob/user, list/hidden, looks_synth)
	var/list/wound_flavor_text = list()
	var/list/is_bleeding = list()
	var/applying_pressure = ""

	for(var/organ_tag in species.has_limbs)
		var/list/organ_data = species.has_limbs[organ_tag]
		var/organ_descriptor = organ_data["descriptor"]
		var/obj/item/organ/external/E = organs_by_name[organ_tag]
		if(!E)
			wound_flavor_text["[organ_descriptor]"] = span_boldwarning("[p_Theyre()] missing [p_their()] [organ_descriptor].")
		else if(E.is_stump())
			wound_flavor_text["[organ_descriptor]"] = span_boldwarning("[p_They()] [p_have()] a stump where [p_their()] [organ_descriptor] should be.")

	for(var/obj/item/organ/external/temp in organs)
		if((temp.organ_tag in hidden) && hidden[temp.organ_tag])
			continue //Organ is hidden, don't talk about it
		if(temp.status & ORGAN_DESTROYED)
			wound_flavor_text["[temp.name]"] = span_boldwarning("[p_Theyre()] missing [p_their()] [temp.name].")
			continue

		if(!looks_synth && temp.robotic == ORGAN_ROBOT)
			if(!(temp.get_trauma() + temp.get_burn()))
				wound_flavor_text["[temp.name]"] = "[p_They()] [p_have()] a [temp.name]."
			else
				wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] a [temp.name] with [temp.get_wounds_desc()]!")
			continue
		else if(length(temp.get_wounds()) || temp.open)
			if(temp.is_stump() && temp.parent_organ && organs_by_name[temp.parent_organ])
				var/obj/item/organ/external/parent = organs_by_name[temp.parent_organ]
				wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] [temp.get_wounds_desc()] on [p_their()] [parent.name].")
			else
				wound_flavor_text["[temp.name]"] = span_warning("[p_They()] [p_have()] [temp.get_wounds_desc()] on [p_their()] [temp.name].")
		else
			wound_flavor_text["[temp.name]"] = ""
		if(temp.dislocated == 1)
			wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.joint] is dislocated!")
		if(temp.get_trauma() > temp.min_broken_damage || temp.is_fractured() || (temp.status & ORGAN_MUTATED))
			wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.name] is dented and swollen!")
		if(temp.status & ORGAN_DEAD)
			wound_flavor_text["[temp.name]"] += span_warning("[p_Their()] [temp.name] looks rotten!")
		if(temp.status & ORGAN_BLEEDING)
			is_bleeding["[temp.name]"] += span_danger("[p_Their()] [temp.name] is bleeding!")
		if(temp.applied_pressure == src)
			applying_pressure = span_info("[p_They()] is applying pressure to [p_their()] [temp.name].")

	var/list/lines = list()
	for(var/limb in wound_flavor_text)
		if(wound_flavor_text[limb])
			lines += wound_flavor_text[limb]
	for(var/limb in is_bleeding)
		if(is_bleeding[limb])
			lines += is_bleeding[limb]
	for(var/implant in get_visible_implants(0))
		lines += span_danger("[src] [user.p_have()] \a [implant] sticking out of [p_their()] flesh!")
	if(digitalcamo)
		lines += "[p_Theyre()] repulsively uncanny!"
	return list(lines, applying_pressure)

/// What the naked eye sees: the glance diagnosis profile's signs (bleeding, pallor, blue lips,
/// laboured breathing, visible infection). Patient-only sensations (pain, dizziness) stay hidden.
/mob/living/carbon/human/proc/examine_diagnosis_lines()
	. = list()
	var/datum/diagnosis/glance = diagnose(/datum/diagnostic_profile/glance)
	for(var/line in glance?.examine_lines())
		. += span_warning(line)
	for(var/datum/diagnosis_finding/F as anything in glance?.findings_of(DIAG_FINDING_CONDITION))
		if(F.location && ispath(F.source_type, /datum/affliction/wound_infection) && _dq_band_rank(F.band) >= _dq_band_rank(DIAG_BAND_MODERATE))
			. += span_warning("[p_Their()] [F.location] looks very infected!")
	spent(glance)

/// The name records are filed under: the worn ID's, else ours.
/mob/living/carbon/human/proc/examine_record_name()
	var/obj/item/worn_id = get_equipped_item(SLOT_ID_ID)
	if(istype(worn_id, /obj/item/card/id))
		var/obj/item/card/id/I = worn_id
		return I.registered_name
	if(istype(worn_id, /obj/item/pda))
		var/obj/item/pda/P = worn_id
		return P.owner
	return name

/// Security, medical and employment record links for HUD wearers.
/mob/living/carbon/human/proc/examine_record_lines(mob/user)
	. = list()
	if(hasHUD(user,"security"))
		var/perpname = examine_record_name()
		var/criminal = "None"
		for(var/datum/data/record/R in GLOB.data_core.security)
			if(R.fields["name"] == perpname)
				criminal = R.fields["criminal"]
		. += "Criminal status: <a href='byond://?src=\ref[src];criminal=1'>\[[criminal]\]</a>"
		. += "Security records: <a href='byond://?src=\ref[src];secrecord=`'>\[View\]</a>  <a href='byond://?src=\ref[src];secrecordadd=`'>\[Add comment\]</a>"

	if(hasHUD(user,"medical"))
		var/perpname = examine_record_name()
		var/medical = "None"
		for(var/datum/data/record/R in GLOB.data_core.medical)
			if(R.fields["name"] == perpname)
				medical = R.fields["p_stat"]
		. += "Physical status: <a href='byond://?src=\ref[src];medical=1'>\[[medical]\]</a>"
		. += "Medical records: <a href='byond://?src=\ref[src];medrecord=`'>\[View\]</a> <a href='byond://?src=\ref[src];medrecordadd=`'>\[Add comment\]</a>"

	if(hasHUD(user,"best"))
		. += "Employment records: <a href='byond://?src=\ref[src];emprecord=`'>\[View\]</a> <a href='byond://?src=\ref[src];emprecordadd=`'>\[Add comment\]</a>"

/// Flavour text, custom link, OOC notes and vore preference links.
/mob/living/carbon/human/proc/examine_profile_lines()
	. = list()
	var/flavor_text = print_flavor_text()
	if(flavor_text)
		flavor_text = replacetext(flavor_text, "||", "")
		. += "[flavor_text]"
	if(custom_link)
		. += "Custom link: " + span_linkify("[custom_link]")
	if(identity().ooc_notes)
		. += "OOC Notes: <a href='byond://?src=\ref[src];ooc_notes=1'>\[View\]</a> - <a href='byond://?src=\ref[src];print_ooc_notes_chat=1'>\[Print\]</a>"
	. += "<a href='byond://?src=\ref[src];vore_prefs=1'>\[Mechanical Vore Preferences\]</a>"

//Helper procedure. Called by /mob/living/carbon/human/examine() and /mob/living/carbon/human/Topic() to determine HUD access to security and medical records.
/proc/hasHUD(mob/M as mob, hudtype)
	if(ishuman(M))
		var/mob/living/carbon/human/H = M
		if(hasHUD_vr(H,hudtype)) return 1 //Added records access for certain modes of omni-hud glasses
		switch(hudtype)
			if("security")
				return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/security) || istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/sunglasses/sechud)
			if("medical")
				return istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/hud/health)
	else if(isrobot(M))
		var/mob/living/silicon/robot/R = M
		return R.sensor_type //Borgo sensors are now binary so just have them on or off


/mob/living/carbon/human/proc/examine_weight()
	if(!show_pudge() || !weight_message_visible) //Some clothing or equipment can hide this.
		return ""
	var/message = ""
	var/weight_examine = round(weight)
	switch(weight_examine)
		if(0 to 74)
			message = weight_messages[1]
		if(75 to 99)
			message = weight_messages[2]
		if(100 to 124)
			message = weight_messages[3]
		if(125 to 174)
			message = weight_messages[4]
		if(175 to 224)
			message = weight_messages[5]
		if(225 to 274)
			message = weight_messages[6]
		if(275 to 325)
			message = weight_messages[7]
		if(325 to 374)
			message = weight_messages[8]
		if(375 to 474)
			message = weight_messages[9]
		else
			message = weight_messages[10]
	if(message)
		message = span_notice("[message]")
	return message //Credit to Aronai for helping me actually get this working!

/mob/living/carbon/human/proc/examine_nutrition()
	if(!show_pudge() || !nutrition_message_visible) //Some clothing or equipment can hide this.
		return ""
	if(nutrition_hidden) // Chomp Edit
		return ""
	var/message = ""
	var/nutrition_examine = round(nutrition)
	switch(nutrition_examine)
		if(0 to 49)
			message = nutrition_messages[1]
		if(50 to 99)
			message = nutrition_messages[2]
		if(100 to 499)
			message = nutrition_messages[3]
		if(500 to 999) // Fat.
			message = nutrition_messages[4]
		if(1000 to 1399)
			message = nutrition_messages[5]
		if(1400 to 1934) // One person fully digested.
			message = nutrition_messages[6]
		if(1935 to 3004) // Two people.
			message = nutrition_messages[7]
		if(3005 to 4074) // Three people.
			message = nutrition_messages[8]
		if(4075 to 5124) // Four people.
			message = nutrition_messages[9]
		if(5125 to INFINITY) // More.
			message = nutrition_messages[10]
	if(message)
		message = span_notice("[message]")
	return message

//For OmniHUD records access for appropriate models
/proc/hasHUD_vr(mob/living/carbon/human/H, hudtype)
	if(H.nif)
		switch(hudtype)
			if("security")
				if(H.nif.flag_check(NIF_V_AR_SECURITY,NIF_FLAGS_VISION))
					return TRUE
			if("medical")
				if(H.nif.flag_check(NIF_V_AR_MEDICAL,NIF_FLAGS_VISION))
					return TRUE

	if(istype(H.get_equipped_item(SLOT_ID_EYES), /obj/item/clothing/glasses/omnihud))
		var/obj/item/clothing/glasses/omnihud/omni = H.get_equipped_item(SLOT_ID_EYES)
		switch(hudtype)
			if("security")
				if(omni.mode == "sec" || omni.mode == "best")
					return TRUE
			if("medical")
				if(omni.mode == "med" || omni.mode == "best")
					return TRUE
			if("best")
				if(omni.mode == "best")
					return TRUE

	return FALSE

/mob/living/carbon/human/proc/examine_pickup_size(mob/living/H)
	var/message = ""
	if(istype(H) && (H.get_effective_size(FALSE) - src.get_effective_size(TRUE)) >= 0.50)
		message = span_blue("They are small enough that you could easily pick them up!")
	return message

/mob/living/carbon/human/proc/examine_step_size(mob/living/H)
	var/message = ""
	if(istype(H) && (H.get_effective_size(FALSE) - src.get_effective_size(TRUE)) >= 0.75)
		message = span_red("They are small enough that you could easily trample them!")
	return message

/mob/living/carbon/human/proc/examine_nif(mob/living/carbon/human/H)
	if(nif && nif.examine_msg) //If you have one set, anyway.
		return span_notice("[nif.examine_msg]")

/mob/living/carbon/human/proc/examine_chimera(mob/living/carbon/human/H)
	var/t_He 	= "It" //capitalised for use at the start of each line.
	var/t_his 	= "its"
	var/t_His 	= "Its"
	var/t_appear 	= "appears"
	var/t_has 	= "has"
	switch(identifying_gender) //Gender is their "real" gender. Identifying_gender is their "chosen" gender.
		if(MALE)
			t_He 	= "He"
			t_His 	= "His"
			t_his 	= "his"
		if(FEMALE)
			t_He 	= "She"
			t_His 	= "Her"
			t_his 	= "her"
		if(PLURAL)
			t_He	= "They"
			t_His 	= "Their"
			t_his 	= "their"
			t_appear 	= "appear"
			t_has 	= "have"
		if(NEUTER)
			t_He 	= "It"
			t_His 	= "Its"
			t_his 	= "its"
		if(HERM)
			t_He 	= "Shi"
			t_His 	= "Hir"
			t_his 	= "hir"
	var/datum/xenochimera/xc = get_xenochimera_state()
	if(xc)
		if((xc.revive_ready == REVIVING_NOW || xc.revive_ready == REVIVING_DONE))
			if(stat == DEAD)
				return span_warning("[t_His] body is twitching subtly.")
			else
				return span_notice("[t_He] [t_appear] to be in some sort of torpor.")
		else if(xc.feral)
			return span_warning("[t_He] [t_has] a crazed, wild look in [t_his] eyes!")

/mob/living/carbon/human/proc/examine_body_writing(list/hidden)
	. = list()

	for(var/bodypart in hidden)
		var/is_hidden = hidden[bodypart]
		if(is_hidden)
			continue

		var/writing = LAZYACCESS(body_writing, bodypart)
		if(writing)
			var/obj/item/organ/external/affecting = get_organ(bodypart)
			if(!affecting || affecting.is_stump())
				LAZYREMOVE(body_writing, bodypart)
				continue

			. += span_notice("[p_They()] [p_have()] \"[writing]\" written on [p_their()] [parse_zone(bodypart)].")

/// The result of a pulse check started from examine, a moment later.
/mob/living/carbon/human/proc/pulse_check_result(mob/user)
	if(user && (isobserver(user) || (Adjacent(user) && !user.stat))) // If you're a corpse then you can't exactly check their pulse, but ghosts can see anything
		if(pulse == PULSE_NONE)
			to_chat(user, span_deadsay("[p_They()] [p_have()] no pulse[src.client ? "" : " and [p_their()] soul has departed"]..."))
		else
			to_chat(user, span_deadsay("[p_They()] [p_have()] a pulse!"))
