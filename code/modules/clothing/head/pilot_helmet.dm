//Pilot

/obj/item/clothing/head/pilot
	name = "pilot helmet"
	desc = "Standard pilot gear. Protects the head from impacts."
	icon_state = "pilot_helmet1"
	item_icons = list(slot_head_str = 'icons/mob/pilot_helmet.dmi')
	sprite_sheets = list(
		SPECIES_TESHARI = 'icons/inventory/head/mob_teshari.dmi'
		)
	flags = THICKMATERIAL
	armor_spec = "melee=20;bullet=10;laser=10;energy=5;bomb=10"
	w_class = ITEMSIZE_NORMAL

	var/tmp/obj/machinery/computer/shuttle_control/web/shuttle_comp
	var/atom/movable/screen/pilot_hud
	var/list/images
	var/list/raw_images
	var/last_status
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/head/pilot)
	configure(item_worn(hides = HIDEEARS))
	configure(item_protection(min_cold = HELMET_MIN_COLD_PROTECTION_TEMPERATURE, max_heat = HELMET_MAX_HEAT_PROTECTION_TEMPERATURE))
	owns_one(nameof(pilot_hud), starts = /atom/movable/screen/pilot_hud)
	derives(nameof(images), PROC_REF(build_hud_images))
	derives(nameof(raw_images), PROC_REF(build_raw_images))
	op("pilot_hud_colors_verb", menu(), label("Alter HUD color"), needs(carried()), then(PROC_REF(pilot_hud_colors_verb)))

/// The helmet's HUD layers over its screen, by name: the bars and boxes stay hidden until the shuttle flies (update_hud()).
/obj/item/clothing/head/pilot/proc/build_hud_images()
	. = list()
	.["top_bar"] = pilot_hud_image("top_bar", 145)
	.["topdots"] = pilot_hud_image("top_dots", 200)
	.["top_words"] = pilot_hud_image("words_discon", 200)
	.["charging"] = pilot_hud_image("", 200)
	.["left_bar"] = pilot_hud_image("left_bar", 0)
	.["right_bar"] = pilot_hud_image("right_bar", 0)
	.["flyboxes"] = pilot_hud_image("flyboxes", 0)
	.["horizon"] = pilot_hud_image("horizon", 0)

/obj/item/clothing/head/pilot/proc/pilot_hud_image(state, alpha)
	var/image/I = image(pilot_hud.icon, pilot_hud, state, layer = SCREEN_LAYER + 1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = alpha
	return I

/// The same layers as a plain list, in order (the wearer's client shows them).
/obj/item/clothing/head/pilot/proc/build_raw_images()
	. = list()
	for(var/key in images)
		. += images[key]

/// The helmet's screen: a dimmer the HUD layers sit on.
/atom/movable/screen/pilot_hud
	screen_loc = "1,1"
	icon = 'icons/obj/piloting_overlay.dmi'
	icon_state = "dimmer"
	layer = SCREEN_LAYER
	plane = PLANE_FULLSCREEN
	mouse_opacity = 0
	alpha = 0

/obj/item/clothing/head/pilot/proc/update_hud(status)
	if(last_status == status)
		return

	last_status = status

	if(status == SHUTTLE_INTRANSIT)
		var/image/I = images["top_words"]
		I.icon_state = "words_flying"
		I = images["left_bar"]
		I.alpha = 200
		I = images["right_bar"]
		I.alpha = 200
		I = images["flyboxes"]
		I.alpha = 200
		I = images["horizon"]
		I.alpha = 200
		I = images["charging"]
		I.icon_state = ""
		animate(pilot_hud,alpha=255,time=3 SECONDS)

	else if(status == SHUTTLE_IDLE)
		var/image/I = images["top_words"]
		I.icon_state = "words_standby"
		I = images["left_bar"]
		I.alpha = 0
		I = images["right_bar"]
		I.alpha = 0
		I = images["flyboxes"]
		I.alpha = 0
		I = images["horizon"]
		I.alpha = 0
		I = images["charging"]
		I.icon_state = ""
		animate(pilot_hud,alpha=0,time=3 SECONDS)

	else if(status == SHUTTLE_WARMUP)
		var/image/I = images["top_words"]
		I.icon_state = "words_spool"
		I = images["left_bar"]
		I.alpha = 200
		I = images["right_bar"]
		I.alpha = 200
		I = images["flyboxes"]
		I.alpha = 0
		I = images["horizon"]
		I.alpha = 0
		I = images["charging"]
		I.icon_state = "charging"
		animate(pilot_hud,alpha=255,time=3 SECONDS)

	else if(status == "discon")
		var/image/I = images["top_words"]
		I.icon_state = "words_discon"
		I = images["left_bar"]
		I.alpha = 0
		I = images["right_bar"]
		I.alpha = 0
		I = images["flyboxes"]
		I.alpha = 0
		I = images["horizon"]
		I.alpha = 0
		I = images["charging"]
		I.icon_state = ""
		animate(pilot_hud,alpha=0,time=3 SECONDS)

/// Old verb "Alter HUD color".
/obj/item/clothing/head/pilot/proc/pilot_hud_colors_verb(datum/act/op/A)
	var/mob/user = A.actor
	open_request(src, /datum/prompt/color, PROC_REF(hud_color_picked), answerer = user, title = "HUD Color", question = "Pick a color!", ask_flags = ASK_CARRIED | ASK_CAPABLE, timeout = 0)

/obj/item/clothing/head/pilot/proc/hud_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	for(var/img in list("top_words","left_bar","right_bar","flyboxes"))
		var/image/I = images[img]
		I.color = A.answer.value


// its HUD images are detached.
/obj/item/clothing/head/pilot/on_destroy(force)
	for(var/image/I as anything in raw_images)
		image_anchor(I, null)
	..()

/obj/item/clothing/head/pilot/equipped(mob/user,slot)
	. = ..()
	if(slot == SLOT_ID_HEAD && user.client)
		user.client.screen |= pilot_hud
		user.client.images |= raw_images

/obj/item/clothing/head/pilot/dropped(mob/user, equipping, slot)
	. = ..()
	if(user.client)
		user.client.screen -= pilot_hud
		user.client.images -= raw_images

/obj/item/clothing/head/pilot/alt
	name = "pilot helmet"
	desc = "Standard pilot gear. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot_helmet2"
	actions_types = list(/datum/action/item_action/toggle_visor)
	special_handling = TRUE

CAPABILITIES(/obj/item/clothing/head/pilot/alt)
	op("pilot_alt_visor_self", in_hand(), label("Toggle visor"), then(PROC_REF(pilot_alt_visor_self)))

/// Old attack_self.
/obj/item/clothing/head/pilot/alt/proc/pilot_alt_visor_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		src.set_icon_state("[icon_state]up")
		to_chat(user, "You raise the visor on the pilot helmet.")
	else
		src.set_icon_state(initial(icon_state))
		to_chat(user, "You lower the visor on the pilot helmet.")

//Pilot helmets
/obj/item/clothing/head/pilot_vr
	name = "standard pilot helmet"
	desc = "Standard pilot gear. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot1"
	armor_spec = "melee=20;bullet=10;laser=10;energy=5;bomb=10"
	w_class = ITEMSIZE_NORMAL
	actions_types = list(/datum/action/item_action/toggle_visor)
	special_handling = TRUE
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/head/pilot_vr)
	configure(item_worn(hides = HIDEEARS))
	configure(item_protection(min_cold = HELMET_MIN_COLD_PROTECTION_TEMPERATURE, max_heat = HELMET_MAX_HEAT_PROTECTION_TEMPERATURE))
	op("pilot_vr_visor_self", in_hand(), label("Toggle visor"), then(PROC_REF(pilot_vr_visor_self)))

/// Old attack_self.
/obj/item/clothing/head/pilot_vr/proc/pilot_vr_visor_self(datum/act/op/A)
	var/mob/user = A.actor
	if(src.icon_state == initial(icon_state))
		src.set_icon_state("[icon_state]up")
		to_chat(user, "You raise the visor on the pilot helmet.")
	else
		src.set_icon_state(initial(icon_state))
		to_chat(user, "You lower the visor on the pilot helmet.")

/obj/item/clothing/head/pilot_vr/alt
	name = "colored pilot helmet"
	desc = "A colored version of the standard pilot helmet. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot2"
	actions_types = list(/datum/action/item_action/toggle_visor)

//////////Talon Pilot Headgear//////////

/obj/item/clothing/head/pilot_vr/talon
	name = "Talon pilot helmet"
	desc = "An ITV Talon version of the standard pilot helmet. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot3"
	actions_types = list(/datum/action/item_action/toggle_visor)

//////////Major Bill's Pilot Headgear//////////

/obj/item/clothing/head/pilot_vr/mbill
	name = "\improper Major Bill's pilot helmet"
	desc = "An Major Bill's Transportation version of the standard pilot helmet. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot3"
	catalogue_data = list(/datum/category_item/catalogue/information/organization/major_bills)
	actions_types = list(/datum/action/item_action/toggle_visor)

/// the shuttle_comp this refers to (a relation view: null once it is deleted).
/obj/item/clothing/head/pilot/proc/shuttle_comp() as /obj/machinery/computer/shuttle_control/web
	return shuttle_comp


