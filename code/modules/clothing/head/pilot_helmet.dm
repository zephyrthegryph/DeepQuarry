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
	flags_inv = HIDEEARS
	min_cold_protection_temperature = HELMET_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = HELMET_MAX_HEAT_PROTECTION_TEMPERATURE
	w_class = ITEMSIZE_NORMAL

	var/tmp/obj/machinery/computer/shuttle_control/web/shuttle_comp
	var/atom/movable/screen/pilot_hud
	var/list/images
	var/list/raw_images
	var/last_status
	resistance_flags = FIRE_PROOF

DECLARE_DEFAULT_CHILD(/obj/item/clothing/head/pilot, "pilot_hud", /atom/movable/screen)

/obj/item/clothing/head/pilot/Initialize(mapload)
	. = ..()

	images = list()
	raw_images = list()

	pilot_hud.screen_loc = "1,1"
	pilot_hud.icon = 'icons/obj/piloting_overlay.dmi'
	pilot_hud.icon_state = "dimmer"
	pilot_hud.layer = SCREEN_LAYER
	pilot_hud.plane = PLANE_FULLSCREEN
	pilot_hud.mouse_opacity = 0
	pilot_hud.alpha = 0

	var/image/I
	I = image(pilot_hud.icon,pilot_hud,"top_bar",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 145
	images["top_bar"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"top_dots",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 200
	images["topdots"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"words_discon",layer=SCREEN_LAYER+1) //words_standby, words_flying, words_spool, words_discon
	I.appearance_flags = RESET_ALPHA
	I.alpha = 200
	images["top_words"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 200
	images["charging"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"left_bar",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 0
	images["left_bar"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"right_bar",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 0
	images["right_bar"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"flyboxes",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 0
	images["flyboxes"] = I
	raw_images += I

	I = image(pilot_hud.icon,pilot_hud,"horizon",layer=SCREEN_LAYER+1)
	I.appearance_flags = RESET_ALPHA
	I.alpha = 0
	images["horizon"] = I
	raw_images += I

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

EXTEND_INTERACTIONS(/obj/item/clothing/head/pilot, \
	INTERACT_VERB("Alter HUD color", PROC_REF(pilot_hud_colors_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Alter HUD color".
/obj/item/clothing/head/pilot/proc/pilot_hud_colors_verb(mob/user, obj/item/held, datum/interaction/interaction)
	om_ask(user, /datum/om/prompt/color, PROC_REF(hud_color_picked), title = "HUD Color", message = "Pick a color!", ask_flags = ASK_CARRIED | ASK_CAPABLE)

/obj/item/clothing/head/pilot/proc/hud_color_picked(datum/om/prompt/color/ask)
	for(var/img in list("top_words","left_bar","right_bar","flyboxes"))
		var/image/I = images[img]
		I.color = ask.picked_color


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

EXTEND_INTERACTIONS(/obj/item/clothing/head/pilot/alt, INTERACT_USE("Toggle visor", PROC_REF(pilot_alt_visor_self)))

/// Old attack_self.
/obj/item/clothing/head/pilot/alt/proc/pilot_alt_visor_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(src.icon_state == initial(icon_state))
		src.icon_state = "[icon_state]up"
		to_chat(user, "You raise the visor on the pilot helmet.")
	else
		src.icon_state = initial(icon_state)
		to_chat(user, "You lower the visor on the pilot helmet.")
	update_clothing_icon() //so our mob-overlays update

//Pilot helmets
/obj/item/clothing/head/pilot_vr
	name = "standard pilot helmet"
	desc = "Standard pilot gear. Protects the head from impacts. This one has a retractable visor"
	icon_state = "pilot1"
	armor_spec = "melee=20;bullet=10;laser=10;energy=5;bomb=10"
	flags_inv = HIDEEARS
	min_cold_protection_temperature = HELMET_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = HELMET_MAX_HEAT_PROTECTION_TEMPERATURE
	w_class = ITEMSIZE_NORMAL
	actions_types = list(/datum/action/item_action/toggle_visor)
	special_handling = TRUE
	resistance_flags = FIRE_PROOF

EXTEND_INTERACTIONS(/obj/item/clothing/head/pilot_vr, INTERACT_USE("Toggle visor", PROC_REF(pilot_vr_visor_self)))

/// Old attack_self.
/obj/item/clothing/head/pilot_vr/proc/pilot_vr_visor_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(src.icon_state == initial(icon_state))
		src.icon_state = "[icon_state]up"
		to_chat(user, "You raise the visor on the pilot helmet.")
	else
		src.icon_state = initial(icon_state)
		to_chat(user, "You lower the visor on the pilot helmet.")
	update_clothing_icon() //so our mob-overlays update

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

/// LC-refs: the shuttle_comp this refers to -- an OM handle (om_handle()), so it reads null once that is deleted.
/obj/item/clothing/head/pilot/proc/shuttle_comp() as /obj/machinery/computer/shuttle_control/web
	return shuttle_comp


