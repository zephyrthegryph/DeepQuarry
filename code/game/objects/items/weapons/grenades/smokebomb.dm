/obj/item/grenade/smokebomb
	desc = "It is set to detonate in 2 seconds. These high-tech grenades can have their color adapted on the fly with a multitool!"
	name = "smoke bomb"
	icon = 'icons/obj/grenade.dmi'
	icon_state = "flashbang"
	det_time = 20
	item_state = "flashbang"
	slot_flags = SLOT_BELT
	hud_state = "grenade_smoke"
	var/datum/effect/effect/system/smoke_spread/bad/smoke
	var/smoke_color
	var/smoke_strength = 8

/obj/item/grenade/smokebomb/Initialize(mapload)
	. = ..()
	smoke.attach(src)

CAPABILITIES(/obj/item/grenade/smokebomb)
	owns_one(nameof(smoke), /datum/effect/effect/system/smoke_spread/bad, starts = /datum/effect/effect/system/smoke_spread/bad)

/obj/item/grenade/smokebomb/detonate()
	start_effect_sprayer(smoke, smoke_strength, 'sound/effects/smoke.ogg', smoke_color)

DECLARE_INTERACTIONS(/obj/item/grenade/smokebomb, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/grenade/smokebomb/proc/interaction_item(mob/user, obj/item/I, datum/interaction/interaction)
	if(I.has_tool_quality(TOOL_MULTITOOL))
		om_ask(user, /datum/om/prompt/color, PROC_REF(smoke_color_chosen), title = "Smoke Color", message = "Choose a color for the smoke:", default = smoke_color, ask_flags = ASK_NEAR_SUBJECT | ASK_CAPABLE)

/obj/item/grenade/smokebomb/proc/smoke_color_chosen(datum/om/prompt/color/ask)
	if(ask.picked_color)
		smoke_color = ask.picked_color
	return INTERACTION_HANDLED_PASS

/obj/item/grenade/smokebomb/primed
	desc = "A smoke bomb. This one appears to be already activated!"

/obj/item/grenade/smokebomb/primed/Initialize(mapload)
	. = ..()
	activate()
