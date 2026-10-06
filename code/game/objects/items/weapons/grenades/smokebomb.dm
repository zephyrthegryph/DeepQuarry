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
	op("smoke_color", tool(TOOL_MULTITOOL), wait(0), label("Set smoke colour"),
		asks(/datum/prompt/color, fields = list("title" = "Smoke Color", "question" = "Choose a color for the smoke:", "default" = "smoke_color", "timeout" = 0)),
		then(PROC_REF(smoke_color_chosen)))

/obj/item/grenade/smokebomb/detonate()
	start_effect_sprayer(smoke, smoke_strength, 'sound/effects/smoke.ogg', smoke_color)

/// Old attackby with a multitool: the smoke takes the chosen colour.
/obj/item/grenade/smokebomb/proc/smoke_color_chosen(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(R?.value)
		smoke_color = R.value
	return OP_PASS

/obj/item/grenade/smokebomb/primed
	desc = "A smoke bomb. This one appears to be already activated!"

/obj/item/grenade/smokebomb/primed/Initialize(mapload)
	. = ..()
	activate()
