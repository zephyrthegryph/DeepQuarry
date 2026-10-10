/obj/item/fuel_assembly
	name = "fuel rod assembly"
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "fuel_assembly"

	var/material_name

	var/percent_depleted = 1
	var/list/rod_quantities = list() // ALLOW(instance_list): d: filled in New() with the rod's reagent amounts
	var/fuel_type = MAT_COMPOSITE
	var/fuel_colour
	var/const/initial_amount = 3000000
	COOLDOWN_DECLARE(event_cooldown)
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/// Radioactive rods pulse radiation (periodic_step()) for as long as they are radioactive.
/obj/item/fuel_assembly/var/radioactivity = 0
TRACKED(/obj/item/fuel_assembly, radioactivity)
CAPABILITIES(/obj/item/fuel_assembly)
	every(2 SECONDS, then(PROC_REF(fuel_assembly_step)), when = nameof(radioactivity))
	param(nameof(fuel_type), pos = 1)
	param(nameof(fuel_colour), pos = 2)

/obj/item/fuel_assembly/proc/fuel_assembly_step(datum/act/timer/A)
	radiate()

/obj/item/fuel_assembly/proc/radiate()
	if(active)
		return
	if(!COOLDOWN_FINISHED(src, event_cooldown))
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = (radioactivity * 0.5),
		threshold = RAD_HEAVY_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE,
		strength = radioactivity * 0.5
	)
	COOLDOWN_START(src, event_cooldown, 1.5 SECONDS)
	active = FALSE

// ALLOW(init/INSTANCE_STATE): a fuel rod is named, coloured and made radioactive or luminous by its material
/obj/item/fuel_assembly/Initialize(mapload)
	. = ..()
	var/datum/material/material = get_material_by_name(fuel_type)
	if(istype(material))
		name = "[material.use_name] fuel rod assembly"
		desc = "A fuel rod for a fusion reactor. This one is made from [material.use_name]."
		fuel_colour = material.icon_colour
		fuel_type = material.use_name
		// radioactivity / luminescence moved to components on /datum/material.
		var/mat_rad = dq_material_radioactivity(material)
		var/mat_lum = dq_material_luminescence(material)
		if(mat_rad)
			set_radioactivity(mat_rad)
			desc += " It is warm to the touch."
		if(mat_lum)
			set_light(mat_lum, mat_lum, material.icon_colour)
	else
		name = "[fuel_type] fuel rod assembly"
		desc = "A fuel rod for a fusion reactor. This one is made from [fuel_type]."

	changed(src)
	rod_quantities[fuel_type] = initial_amount

// Mapper shorthand.
/obj/item/fuel_assembly/deuterium
	fuel_type = MAT_DEUTERIUM

/obj/item/fuel_assembly/tritium
	fuel_type = MAT_TRITIUM

/obj/item/fuel_assembly/phoron
	fuel_type = MAT_PHORON

/obj/item/fuel_assembly/supermatter
	fuel_type = MAT_SUPERMATTER

// === merged from fuel_assembly_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/fuel_assembly/blitz
	name = "blitz rod"
	desc = "A highly unstable mixture of supermatter and phoron. It's probably not a good idea to try to use this in a reactor..."
	fuel_colour = "#FCE300"
	fuel_type = "blitz"

/obj/item/fuel_assembly/blitz
	fuel_type = "     "

/obj/item/fuel_assembly/blitz/unshielded/Initialize(mapload)
	. = ..()
	name = "unshielded blitz rod"
	desc = "An extremely unstable, raw rod of compressed supermatter and phoron. This seems like a terrible idea."
	fuel_colour = "#FCE300"
	fuel_type = "blitzu"
	rod_glows = TRUE
	changed(src)
	rod_quantities[fuel_type] = initial_amount
	radiation_pulse(
		source = src,
		max_range = 5,
		threshold = RAD_EXTREME_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE,
		strength = 20
	)
	set_light(3, 3, "#FCE300")

/obj/item/fuel_assembly/blitz/throw_impact(atom/hit_atom)
	if(!..())
		visible_message(span_warning("\The [src] loses stability and shatters in a violent explosion!"))
		radiation_pulse(
			source = src,
			max_range = 7,
			threshold = RAD_MEDIUM_INSULATION,
			chance = 100,
			strength = 250
		)
		explosion(src.loc, 1, 2, 4, 6)
		destroyed(src)

CAPABILITIES(/obj/item/fuel_assembly/blitz/unshielded)
	op("unshielded_lead_shell", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), then(PROC_REF(interaction_item)))
	op("pick_up", hand(), label("Pick up"), then(PROC_REF(unshielded_pick_up)))

/// Old attackby.
/obj/item/fuel_assembly/blitz/unshielded/proc/interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	var/obj/item/stack/material/lead/M = I
	if(istype(M))
		if(M.get_amount() > 5)
			to_chat(user,span_notice("You add a lead shell to the blitz rod."))
			consume(src, user)
			var/obj/item/fuel_assembly/blitz/shielded/rod = new(get_turf(user))
			user.put_in_hands(rod)
			return OP_PASS
		else
			to_chat(user,span_warning("You need at least five sheets of lead to add shielding!"))
	return OP_PASS


/// Picking the unshielded rod up irradiates the holder.
/obj/item/fuel_assembly/blitz/unshielded/proc/unshielded_pick_up(datum/act/op/A)
	var/mob/user = A.actor
	. = OP_OK
	pick_up_by_hand(user)

	if(!ishuman(user))
		return

	radiation_pulse(
		source = src,
		max_range = 2,
		threshold = RAD_MEDIUM_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE,
		strength = 5
	)

	var/mob/living/carbon/human/H = user
	var/obj/item/clothing/gloves/G = H.get_equipped_item(SLOT_ID_GLOVES)
	if(istype(G) && ((G.flags & THICKMATERIAL && prob(70)) || istype(G, /obj/item/clothing/gloves/gauntlets)))
		return

	act_message(src, H, others = span_danger("%U% flashes as it scorches %T%'s hand!"))

	if(H.hand)
		H.injure(INJURY_BURN, 7, BP_L_HAND, src)
	else
		H.injure(INJURY_BURN, 7, BP_R_HAND, src)
	H.drop_from_inventory(src, get_turf(H))
	return

/obj/item/fuel_assembly/blitz/shielded
	name = "blitz rod"

/obj/item/fuel_assembly/blitz/shielded/Initialize(mapload)
	. = ..()
	name = "blitz rod"
	desc = "A highly unstable, and highly explosive supermatter and phoron fuel rod with a lead shell, created by someone of questionable sanity. This thing has to violate at least a few intergalactic regulations."
	fuel_colour = "#76888F"
	fuel_type = "blitz"
	rod_glows = TRUE
	changed(src)
	rod_quantities[fuel_type] = initial_amount
	set_light(2, 2, "#FCE300")

/// Whether the rod glows (the blitz rods).
/obj/item/fuel_assembly/var/rod_glows = FALSE

/// The rod in its fuel's colour, its bracket and, for a blitz rod, its glow.
/obj/item/fuel_assembly/draw(datum/look/look)
	..()
	look.state("blank")
	look.overlay(look_overlay_image(icon, "fuel_assembly", color = fuel_colour))
	look.overlay(look_image(icon, "fuel_assembly_bracket"))
	look.overlay(look_image(icon, "glow"), when = rod_glows)
