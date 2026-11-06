/obj/item/clothing/accessory/collar
	icon_state = "collar_blk"
	var/writtenon = 0
	var/icon_previous_override
	special_handling = TRUE
	///Var for attack_self chain
	var/special_collar = FALSE

//Forces different sprite sheet on equip
/obj/item/clothing/accessory/collar/on_materialize()
	icon_previous_override = icon_override
	. = ..()

/obj/item/clothing/accessory/collar/equipped() //Solution for race-specific sprites for an accessory which is also a suit. Suit icons break if you don't use icon override which then also overrides race-specific sprites.
	..()
	setUniqueSpeciesSprite()

/obj/item/clothing/accessory/collar/proc/setUniqueSpeciesSprite()
	var/mob/living/carbon/human/H = loc
	if(!istype(H) && istype(has_suit(), /obj/item/clothing) && ishuman(has_suit().loc))
		H = has_suit().loc
	if(sprite_sheets && istype(H) && H.species.get_bodytype(H) && (H.species.get_bodytype(H) in sprite_sheets))
		set_icon_override(sprite_sheets[H.species.get_bodytype(H)])

/obj/item/clothing/accessory/collar/on_attached(obj/item/clothing/S, mob/user)
	if(!istype(S))
		return
	rel_set(src, nameof(has_suit), S)
	setUniqueSpeciesSprite()
	..(S, user)

/obj/item/clothing/accessory/collar/dropped(mob/user, equipping, slot)
	..()
	set_icon_override(icon_previous_override)

/obj/item/clothing/accessory/collar/silver
	name = "Silver tag collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_blk"
	item_state = "collar_blk"
	overlay_state = "collar_blk"

/obj/item/clothing/accessory/collar/gold
	name = "Golden tag collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_gld"
	item_state = "collar_gld"
	overlay_state = "collar_gld"

/obj/item/clothing/accessory/collar/spike
	name = "Spiked collar"
	desc = "A collar with spikes that look as sharp as your teeth."
	icon_state = "collar_spik"
	item_state = "collar_spik"
	overlay_state = "collar_spik"

/obj/item/clothing/accessory/collar/pink
	name = "Pink collar"
	desc = "This collar will make your pets look FA-BU-LOUS."
	icon_state = "collar_pnk"
	item_state = "collar_pnk"
	overlay_state = "collar_pnk"

/obj/item/clothing/accessory/collar/cowbell
	name = "cowbell collar"
	desc = "A collar for your little pets... or the big ones."
	icon_state = "collar_cowbell"
	item_state = "collar_cowbell_overlay"
	overlay_state = "collar_cowbell_overlay"

/obj/item/clothing/accessory/collar/collarplanet_earth
	name = "planet collar"
	desc = "A collar featuring a surprisingly detailed replica of a earth-like planet surrounded by a weak battery powered force shield. There is a button to turn it off."
	icon_state = "collarplanet_earth"
	item_state = "collarplanet_earth"
	overlay_state = "collarplanet_earth"

/obj/item/clothing/accessory/collar/holo
	name = "Holo-collar"
	desc = "An expensive holo-collar for the modern day pet."
	icon_state = "collar_holo"
	item_state = "collar_holo"
	overlay_state = "collar_holo"
	MATERIAL_BULK(MAT_STEEL, 50)

/obj/item/clothing/accessory/collar/holo/indigestible
	desc = "A special variety of the holo-collar that seems to be made of a very durable fabric that fits around the neck."

//Make indigestible
/obj/item/clothing/accessory/collar/holo/indigestible/digest_act(atom/movable/item_storage = null)
	return FALSE

CAPABILITIES(/obj/item/clothing/accessory/collar)
	configure(item_worn(slots = SLOT_TIE | SLOT_OCLOTHING, worn_icon = INV_ACCESSORIES_DEF_ICON))
	op("collar_tag_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Collar tag self"), then(PROC_REF(collar_tag_self)))
	op("collar_tag_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Collar tag item"), then(PROC_REF(collar_tag_item)))

/// Old attack_self: set the tag. Returns FALSE where the old body returned nothing, so subtypes'
/// legacy attack_self bodies that ran after ..() still run.
/obj/item/clothing/accessory/collar/proc/collar_tag_self(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/held = A.held
	if(special_collar)
		return OP_DECLINE
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		to_chat(user,span_notice("[name]'s interface is projected onto your hand."))
	else
		if(writtenon)
			to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			return OP_DECLINE
		to_chat(user,span_notice("You adjust the [name]'s tag."))

	open_collar_tag(user, held)
	return OP_OK

/obj/item/clothing/accessory/collar/proc/open_collar_tag(mob/user, obj/item/held, tool_edit = FALSE, erasemethod, erasing, writemethod)
	var/original_client_ckey
	if(istype(user, /client))
		var/client/C = user
		original_client_ckey = C.ckey
		user = C.mob
	if(!ismob(user) || QDELETED(user))
		return
	open_request(src, /datum/prompt/text/collar_tag, PROC_REF(collar_tag_entered), answerer = user, captured_item = held, item_expected = !isnull(held), original_client_ckey = original_client_ckey, tool_edit = tool_edit, erasemethod = erasemethod, erasing = erasing, writemethod = writemethod)

/obj/item/clothing/accessory/collar/proc/collar_tag_entered(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	if(request.captures_gone())
		return
	if(!A.answer)
		if(request.outcome == REQ_CANCELLED && !isnull(request.value))
			if(!request.tool_edit && !special_collar && !istype(src, /obj/item/clothing/accessory/collar/holo) && writtenon)
				to_chat(request.user_value(), span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			SStgui.update_uis(src)
		return
	var/datum/result/result = safe_call(request.tool_edit ? PROC_REF(apply_tool_tag) : PROC_REF(apply_self_tag), A)
	if(!result.ok)
		stack_trace("Collar tag request: [result.error]")
	SStgui.update_uis(src)

/obj/item/clothing/accessory/collar/proc/apply_self_tag(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	var/mob/user = request.user_value()
	if(special_collar)
		return FALSE
	if(istype(src, /obj/item/clothing/accessory/collar/holo))
		to_chat(user, span_notice("[name]'s interface is projected onto your hand."))
	else
		if(writtenon)
			to_chat(user, span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
			return FALSE
		to_chat(user, span_notice("You adjust the [name]'s tag."))
	var/_answer_a1 = A.answer.value
	var/str = copytext(reject_bad_text(_answer_a1),1,MAX_NAME_LEN)

	if(!str || !length(str))
		to_chat(user,span_notice("[name]'s tag set to be blank."))
		name = initial(name)
		desc = initial(desc)
	else
		to_chat(user,span_notice("You set the [name]'s tag to '[str]'."))
		initialize_tag(str)
	return FALSE

/obj/item/clothing/accessory/collar/proc/initialize_tag(tag)
		name = initial(name) + " ([tag])"
		desc = initial(desc) + " \"[tag]\" has been engraved on the tag."
		writtenon = 1

/obj/item/clothing/accessory/collar/holo/initialize_tag(tag)
		..()
		desc = initial(desc) + " The tag says \"[tag]\"."

/// Old attackby: edit the tag with a pen or screwdriver. Never fell through to the clothing attackby.
/obj/item/clothing/accessory/collar/proc/collar_tag_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(src,/obj/item/clothing/accessory/collar/holo))
		return OP_PASS

	if(I.has_tool_quality(TOOL_SCREWDRIVER))
		update_collartag(user, I, "scratched out", "scratch out", "engraved")
		return OP_PASS

	if(istype(I,/obj/item/pen))
		update_collartag(user, I, "crossed out", "cross out", "written")
		return OP_PASS

	to_chat(user,span_notice("You need a pen or a screwdriver to edit the tag on this collar."))
	return OP_PASS

/obj/item/clothing/accessory/collar/proc/update_collartag(mob/user, obj/item/I, erasemethod, erasing, writemethod)
	if(!(istype(user.get_active_hand(),I)) || !(istype(user.get_inactive_hand(),src)) || (user.stat))
		return

	open_collar_tag(user, I, TRUE, erasemethod, erasing, writemethod)

/obj/item/clothing/accessory/collar/proc/apply_tool_tag(datum/act/request/A)
	var/datum/prompt/text/collar_tag/request = A.request
	var/mob/user = request.user_value()
	var/obj/item/I = request.captured_item
	var/erasemethod = request.erasemethod
	var/erasing = request.erasing
	var/writemethod = request.writemethod
	if(!(istype(user.get_active_hand(),I)) || !(istype(user.get_inactive_hand(),src)) || user.stat)
		return
	var/_answer_a2 = A.answer.value
	var/str = copytext(reject_bad_text(_answer_a2),1,MAX_NAME_LEN)

	if(!str || !length(str))
		if(!writtenon)
			to_chat(user,span_notice("You don't write anything."))
		else
			to_chat(user,span_notice("You [erasing] the words with the [I]."))
			name = initial(name)
			desc = initial(desc) + " The tag has had the words [erasemethod]."
	else
		if(!writtenon)
			to_chat(user,span_notice("You write '[str]' on the tag with the [I]."))
			name = initial(name) + " ([str])"
			desc = initial(desc) + " \"[str]\" has been [writemethod] on the tag."
			writtenon = 1
		else
			to_chat(user,span_notice("You [erasing] the words on the tag with the [I], and write '[str]'."))
			name = initial(name) + " ([str])"
			desc = initial(desc) + " Something has been [erasemethod] on the tag, and it now has \"[str]\" [writemethod] on it."

//Casino Sentient Prize Collar

/obj/item/clothing/accessory/collar/casinosentientprize
	name = "disabled Sentient Prize Collar"
	desc = "A collar worn by sentient prizes registered to a SPASM. Although the red text on it shows its disconnected and nonfunctional."

	icon_state = "casinoslave"
	item_state = "casinoslave"
	overlay_state = "casinoslave"

	var/sentientprizename = null	//Name for system to put on collar description
	var/ownername = null	//Name for system to put on collar description
	var/sentientprizeckey = null	//Ckey for system to check who is the person and ensure no abuse of system or errors
	var/sentientprizeflavor = null	//Description to show on the SPASM
	var/sentientprizeooc = null		//OOC text to show on the SPASM
	var/sentientprizeitemtf = FALSE	//Whether the person opted in to allowing themselves to be item TF'd as a prize
	special_handling = TRUE
	special_collar = TRUE

//keeping self-use blank so people don't tag and reset collar status
CAPABILITIES(/obj/item/clothing/accessory/collar/casinosentientprize)
	op("swallow", in_hand(), priority(OP_PRIORITY_DEFAULT), label("Interaction swallow"), then(TYPE_PROC_REF(/atom, op_swallow)))

/obj/item/clothing/accessory/collar/casinosentientprize_fake
	name = "Sentient Prize Collar"
	desc = "A collar worn by sentient prizes registered to a SPASM. This one has been disconnected from the system and is now an accessory!"

	icon_state = "casinoslave_owned"
	item_state = "casinoslave_owned"
	overlay_state = "casinoslave_owned"

/obj/item/clothing/accessory/collar/casinoslave
	name = "a disabled Sentient Prize Collar"
	desc = "A collar worn by sentient prizes on the Golden Goose Casino. Although the red text on it shows its disconnected and nonfunctional."
	icon = 'icons/obj/clothing/ties_ch.dmi'
	icon_override = 'icons/mob/ties_ch.dmi'

	icon_state = "casinoslave"
	item_state = "casinoslave"
	overlay_state = "casinoslave"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_ch_teshari.dmi')

	var/ownername = null	//Name for system to put on collar description
	special_collar = TRUE

/obj/item/clothing/accessory/collar/holo/casinoslave_fake
	name = "a Sentient Prize Collar"
	desc = "A collar worn by sentient prizes on the Golden Goose Casino. This one has been disconnected from the system and is now an accessory!"
	icon = 'icons/obj/clothing/ties_ch.dmi'
	icon_override = 'icons/mob/ties_ch.dmi'

	icon_state = "casinoslave_owned"
	item_state = "casinoslave_owned"
	overlay_state = "casinoslave_owned"
	sprite_sheets = list(SPECIES_TESHARI = 'icons/inventory/accessory/mob_ch_teshari.dmi')
