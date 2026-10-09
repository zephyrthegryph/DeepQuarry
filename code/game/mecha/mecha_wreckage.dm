///////////////////////////////////
////////  Mecha wreckage   ////////
///////////////////////////////////


/obj/effect/decal/mecha_wreckage
	name = "Exosuit wreckage"
	desc = "Remains of some unfortunate mecha. Completely unrepairable."
	icon = 'icons/mecha/mecha.dmi'
	density = TRUE
	anchored = FALSE
	opacity = 0
	var/list/welder_salvage = list(/obj/item/stack/material/plasteel,/obj/item/stack/material/steel,/obj/item/stack/rods) // ALLOW(instance_list): d: edited in place per instance (6 writers)
	var/static/list/wirecutters_salvage = list(/obj/item/stack/cable_coil)
	var/list/crowbar_salvage
	var/salvage_num = 5

CAPABILITIES(/obj/effect/decal/mecha_wreckage)
	extend(/datum/act/hit/projectile, instead())
	op("cut", tool(TOOL_WELDER), label("Cut salvage from the wreck"), needs(req(PROC_REF(has_salvage_left), because = MSG(mecha_wreckage/nothing_to_cut_with)), req(PROC_REF(has_welder_salvage), because = MSG(mecha_wreckage/nothing_to_cut))), wait(0), then(PROC_REF(cut_salvage)))
	op("snip", tool(TOOL_WIRECUTTER), label("Cut wiring from the wreck"), needs(req(PROC_REF(has_salvage_left), because = MSG(mecha_wreckage/nothing_to_cut_with))), wait(0), then(PROC_REF(snip_salvage)))
	op("pry", tool(TOOL_CROWBAR), label("Pry something out of the wreck"), needs(req(PROC_REF(has_pry_salvage), because = MSG(mecha_wreckage/nothing_to_pry))), wait(0), then(PROC_REF(pry_salvage)))


// Salvaging with a welder, wirecutters or a crowbar: mecha_wreckage_salvage.dm.

/obj/effect/decal/mecha_wreckage/gygax
	name = "Gygax wreckage"
	icon_state = "gygax-broken"

// ALLOW(init/INSTANCE_STATE): rolls which parts can be salvaged from this wreck
/obj/effect/decal/mecha_wreckage/gygax/Initialize(mapload)
	. = ..()
	var/list/parts = list(/obj/item/mecha_parts/part/gygax_torso,
								/obj/item/mecha_parts/part/gygax_head,
								/obj/item/mecha_parts/part/gygax_left_arm,
								/obj/item/mecha_parts/part/gygax_right_arm,
								/obj/item/mecha_parts/part/gygax_left_leg,
								/obj/item/mecha_parts/part/gygax_right_leg)
	for(var/i=0;i<2;i++)
		if(!isemptylist(parts) && prob(40))
			var/part = pick(parts)
			welder_salvage += part
			parts -= part

/obj/effect/decal/mecha_wreckage/gygax/dark
	name = "Dark Gygax wreckage"
	icon_state = "darkgygax-broken"

/obj/effect/decal/mecha_wreckage/gygax/adv
	name = "Advanced Dark Gygax wreckage"
	icon_state = "darkgygax_adv-broken"

/obj/effect/decal/mecha_wreckage/gygax/medgax
	name = "Medgax wreckage"
	icon_state = "medgax-broken"

/obj/effect/decal/mecha_wreckage/gygax/serenity
	name = "Serenity wreckage"
	icon_state = "medgax-broken"

/obj/effect/decal/mecha_wreckage/marauder
	name = "Marauder wreckage"
	icon_state = "marauder-broken"

/obj/effect/decal/mecha_wreckage/mauler
	name = "Mauler Wreckage"
	icon_state = "mauler-broken"
	desc = "The syndicate won't be very happy about this..."

/obj/effect/decal/mecha_wreckage/seraph
	name = "Seraph wreckage"
	icon_state = "seraph-broken"

/obj/effect/decal/mecha_wreckage/ripley
	name = "Ripley wreckage"
	icon_state = "ripley-broken"

// ALLOW(init/INSTANCE_STATE): rolls which parts can be salvaged from this wreck
/obj/effect/decal/mecha_wreckage/ripley/Initialize(mapload)
	. = ..()
	var/list/parts = list(/obj/item/mecha_parts/part/ripley_torso,
								/obj/item/mecha_parts/part/ripley_left_arm,
								/obj/item/mecha_parts/part/ripley_right_arm,
								/obj/item/mecha_parts/part/ripley_left_leg,
								/obj/item/mecha_parts/part/ripley_right_leg)
	for(var/i=0;i<2;i++)
		if(!isemptylist(parts) && prob(40))
			var/part = pick(parts)
			welder_salvage += part
			parts -= part

/obj/effect/decal/mecha_wreckage/ripley/firefighter
	name = "Firefighter wreckage"
	icon_state = "firefighter-broken"

// ALLOW(init/INSTANCE_STATE): rolls which parts can be salvaged from this wreck
/obj/effect/decal/mecha_wreckage/ripley/firefighter/Initialize(mapload)
	. = ..()
	var/list/parts = list(/obj/item/mecha_parts/part/ripley_torso,
								/obj/item/mecha_parts/part/ripley_left_arm,
								/obj/item/mecha_parts/part/ripley_right_arm,
								/obj/item/mecha_parts/part/ripley_left_leg,
								/obj/item/mecha_parts/part/ripley_right_leg,
								/obj/item/clothing/suit/fire)
	for(var/i=0;i<2;i++)
		if(!isemptylist(parts) && prob(40))
			var/part = pick(parts)
			welder_salvage += part
			parts -= part

/obj/effect/decal/mecha_wreckage/ripley/deathripley
	name = "Death-Ripley wreckage"
	icon_state = "deathripley-broken"

/obj/effect/decal/mecha_wreckage/durand
	name = "Durand wreckage"
	icon_state = "durand-broken"

// ALLOW(init/INSTANCE_STATE): rolls which parts can be salvaged from this wreck
/obj/effect/decal/mecha_wreckage/durand/Initialize(mapload)
	. = ..()
	var/list/parts = list(
								/obj/item/mecha_parts/part/durand_torso,
								/obj/item/mecha_parts/part/durand_head,
								/obj/item/mecha_parts/part/durand_left_arm,
								/obj/item/mecha_parts/part/durand_right_arm,
								/obj/item/mecha_parts/part/durand_left_leg,
								/obj/item/mecha_parts/part/durand_right_leg)
	for(var/i=0;i<2;i++)
		if(!isemptylist(parts) && prob(40))
			var/part = pick(parts)
			welder_salvage += part
			parts -= part

/obj/effect/decal/mecha_wreckage/phazon
	name = "Phazon wreckage"
	icon_state = "phazon-broken"


/obj/effect/decal/mecha_wreckage/odysseus
	name = "Odysseus wreckage"
	icon_state = "odysseus-broken"

// ALLOW(init/INSTANCE_STATE): rolls which parts can be salvaged from this wreck
/obj/effect/decal/mecha_wreckage/odysseus/Initialize(mapload)
	. = ..()
	var/list/parts = list(
								/obj/item/mecha_parts/part/odysseus_torso,
								/obj/item/mecha_parts/part/odysseus_head,
								/obj/item/mecha_parts/part/odysseus_left_arm,
								/obj/item/mecha_parts/part/odysseus_right_arm,
								/obj/item/mecha_parts/part/odysseus_left_leg,
								/obj/item/mecha_parts/part/odysseus_right_leg)
	for(var/i=0;i<2;i++)
		if(!isemptylist(parts) && prob(40))
			var/part = pick(parts)
			welder_salvage += part
			parts -= part

/obj/effect/decal/mecha_wreckage/odysseus/murdysseus
	icon_state = "murdysseus-broken"

/obj/effect/decal/mecha_wreckage/hoverpod
	name = "Hover pod wreckage"
	icon_state = "engineering_pod-broken"

/obj/effect/decal/mecha_wreckage/janus
	name = "Janus wreckage"
	icon_state = "janus-broken"

/obj/effect/decal/mecha_wreckage/shuttlecraft
	name = "Shuttlecraft wreckage"
	desc = "Remains of some unfortunate shuttlecraft. Completely unrepairable."
	icon = 'icons/mecha/mecha64x64.dmi'
	icon_state = "shuttle_standard-broken"
	bound_width = 64
	bound_height = 64


/obj/effect/decal/mecha_wreckage/scarab
	name = "Scarab Wreckage"
	icon = 'icons/mecha/mecha_ch.dmi'
	icon_state = "scarab_militia-broken"
	desc = "Wasn't fast enough..."

	welder_salvage = list(
								/obj/item/mecha_parts/part/scarab_torso,
								/obj/item/mecha_parts/part/scarab_head,
								/obj/item/mecha_parts/part/scarab_left_arm,
								/obj/item/mecha_parts/part/scarab_right_arm,
								/obj/item/mecha_parts/part/scarab_left_legs,
								/obj/item/mecha_parts/part/scarab_right_legs,
								/obj/item/stack/material/plasteel,
								/obj/item/stack/material/steel,
								/obj/item/stack/rods)
