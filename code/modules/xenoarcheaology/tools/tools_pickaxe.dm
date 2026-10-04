/obj/item/pickaxe/brush
	name = "brush"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick_brush"
	item_state = "syringe_0"
	slot_flags = SLOT_EARS
	digspeed = 20
	force = 0
	throwforce = 0
	desc = "Thick metallic wires for clearing away dust and loose scree (1 centimetre excavation depth)."
	excavation_amount = 1
	drill_sound = SFX_WEAPONS_THUDSWOOSH
	drill_verb = "brushing"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/one_pick
	name = "2cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick1"
	item_state = "syringe_0"
	force = 2
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (2 centimetre excavation depth)."
	excavation_amount = 2
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/two_pick
	name = "4cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick2"
	item_state = "syringe_0"
	force = 2
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (4 centimetre excavation depth)."
	excavation_amount = 4
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/three_pick
	name = "6cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick3"
	item_state = "syringe_0"
	force = 3
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (6 centimetre excavation depth)."
	excavation_amount = 6
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/four_pick
	name = "8cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick4"
	item_state = "syringe_0"
	force = 3
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (8 centimetre excavation depth)."
	excavation_amount = 8
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/five_pick
	name = "10cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick5"
	item_state = "syringe_0"
	force = 5
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (10 centimetre excavation depth)."
	excavation_amount = 10
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/six_pick
	name = "12cm pick"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick6"
	item_state = "syringe_0"
	force = 5
	digspeed = 20
	desc = "A miniature excavation tool for precise digging (12 centimetre excavation depth)."
	excavation_amount = 12
	drill_sound = SFX_ITEMS_SCREWDRIVER
	drill_verb = "delicately picking"
	w_class = ITEMSIZE_SMALL

/obj/item/pickaxe/hand
	name = "hand pickaxe"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "pick_hand"
	item_state = "syringe_0"
	force = 10
	digspeed = 30
	desc = "A smaller, more precise version of the pickaxe (30 centimetre excavation depth)."
	excavation_amount = 30
	drill_sound = SFX_ITEMS_CROWBAR
	drill_verb = "clearing"
	w_class = ITEMSIZE_SMALL

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Pack for holding pickaxes

/obj/item/storage/excavation
	name = "excavation pick set"
	icon = 'icons/obj/storage.dmi'
	icon_state = "excavation"
	desc = "A set of picks for excavation."
	item_state = "syringe_kit"
	storage_slots = 7
	w_class = ITEMSIZE_SMALL
	max_storage_space = ITEMSIZE_COST_SMALL * 9
	use_to_pickup = TRUE


CAPABILITIES(/obj/item/storage/excavation)
	configure(storage(accepts = list(
		/obj/item/pickaxe/brush,
		/obj/item/pickaxe/one_pick,
		/obj/item/pickaxe/two_pick,
		/obj/item/pickaxe/three_pick,
		/obj/item/pickaxe/four_pick,
		/obj/item/pickaxe/five_pick,
		/obj/item/pickaxe/six_pick,
		/obj/item/pickaxe/hand)))

/obj/item/storage/excavation/Initialize(mapload)
	. = ..()
	new /obj/item/pickaxe/brush(src)
	new /obj/item/pickaxe/one_pick(src)
	new /obj/item/pickaxe/two_pick(src)
	new /obj/item/pickaxe/three_pick(src)
	new /obj/item/pickaxe/four_pick(src)
	new /obj/item/pickaxe/five_pick(src)
	new /obj/item/pickaxe/six_pick(src)

/// Picks show smallest first; anything else after them.
/obj/item/storage/excavation/hud_order(list/items)
	var/list/picks = list()
	for(var/obj/item/pickaxe/P in items)
		picks += P
	items -= picks
	return sortTim(picks, GLOBAL_PROC_REF(cmp_excavation_amount)) + items

/proc/cmp_excavation_amount(obj/item/pickaxe/a, obj/item/pickaxe/b)
	return a.excavation_amount - b.excavation_amount

/obj/item/pickaxe/excavationdrill
	name = "excavation drill"
	icon = 'icons/obj/xenoarchaeology.dmi'
	icon_state = "excavationdrill2"
	item_state = "syringe_0"
	excavation_amount = 15
	digspeed = 10
	desc = "Advanced archaeological drill combining ultrasonic excitation and bluespace manipulation to provide extreme precision. The tip is adjustable from 1 to 30 cm."
	drill_sound = SFX_WEAPONS_THUDSWOOSH
	drill_verb = "drilling"
	force = 5
	w_class = ITEMSIZE_SMALL
	attack_verb = list("drilled")

DECLARE_INTERACTIONS(/obj/item/pickaxe/excavationdrill, INTERACT_USE(null, PROC_REF(interaction_self)))

/// Old attack_self.
/obj/item/pickaxe/excavationdrill/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	open_request(src, /datum/prompt/number/excavation_depth, PROC_REF(excavation_depth_entered), answerer = user, captured_item = held, captured_interaction = interaction, item_expected = !isnull(held), interaction_expected = !isnull(interaction), question = "Put the desired depth (1-60 centimeters).", title = "Set Depth", default = excavation_amount, max_value = 60, min_value = 1, timeout = 0)
	return TRUE

/obj/item/pickaxe/excavationdrill/proc/excavation_depth_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/datum/prompt/number/excavation_depth/request = A.request
	if(request.captures_gone())
		return
	var/datum/result/result = safe_call(PROC_REF(apply_excavation_depth), A.request.answerer, A.answer.answer_value)
	if(!result.ok)
		stack_trace("[type] request: [result.error]")
	. = result.value
	SStgui.update_uis(src)

/obj/item/pickaxe/excavationdrill/proc/apply_excavation_depth(mob/user, depth)
	if(isnull(depth))
		return TRUE
	if(depth>60 || depth<1)
		to_chat(user, span_notice("Invalid depth."))
		return TRUE
	excavation_amount = depth
	to_chat(user, span_notice("You set the depth to [depth]cm."))
	switch(depth)
		if(1 to 5)
			icon_state = "excavationdrill0"
		if(6 to 10)
			icon_state = "excavationdrill1"
		if(11 to 15)
			icon_state = "excavationdrill2"
		if(16 to 20)
			icon_state = "excavationdrill3"
		if(21 to 25)
			icon_state = "excavationdrill4"
		if(26 to 60)
			icon_state = "excavationdrill5" //The other 2 sprites are comically long. Let's just cut it at 5.
	return TRUE

/obj/item/pickaxe/excavationdrill/examine(mob/user)
	. = ..()
	. += span_info("It is currently set at [excavation_amount]cms.")


/obj/item/pickaxe/brush
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/one_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/two_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/three_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/four_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/five_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/six_pick
	icon = 'icons/obj/xenoarchaeology.dmi'

/obj/item/pickaxe/hand
	icon = 'icons/obj/xenoarchaeology.dmi'

/datum/prompt/number/excavation_depth
	var/obj/item/captured_item
	var/datum/interaction/captured_interaction
	var/item_expected = FALSE
	var/interaction_expected = FALSE

CAPABILITIES(/datum/prompt/number/excavation_depth)
	ref_one(nameof(captured_item), /obj/item)
	ref_one(nameof(captured_interaction), /datum/interaction)

/datum/prompt/number/excavation_depth/prepare(datum/act/A)
	. = ..()
	var/obj/item/item = captured_item
	var/datum/interaction/interaction = captured_interaction
	rel_clear(src, nameof(captured_item))
	rel_clear(src, nameof(captured_interaction))
	rel_set(src, nameof(captured_item), item)
	rel_set(src, nameof(captured_interaction), interaction)

/datum/prompt/number/excavation_depth/proc/captures_gone()
	return QDELETED(answerer) || (item_expected && QDELETED(captured_item)) || (interaction_expected && QDELETED(captured_interaction))

/datum/prompt/number/excavation_depth/recheck_extra()
	. = ..()
	if(.)
		return
	if(captures_gone())
		return "gone"
	return null
