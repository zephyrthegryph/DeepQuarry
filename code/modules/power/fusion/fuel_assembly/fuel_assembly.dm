/obj/item/fuel_assembly
	name = "fuel rod assembly"
	icon = 'icons/obj/machines/power/fusion.dmi'
	icon_state = "fuel_assembly"

	var/material_name

	var/percent_depleted = 1
	var/list/rod_quantities = list()
	var/fuel_type = MAT_COMPOSITE
	var/fuel_colour
	var/radioactivity = 0
	var/const/initial_amount = 3000000
	var/last_event = 0
	/// Mutex to prevent infinite recursion when propagating radiation pulses
	var/active = null

/obj/item/fuel_assembly/process()
	radiate()

/obj/item/fuel_assembly/proc/radiate()
	SIGNAL_HANDLER
	if(active)
		return
	if(world.time <= last_event + 1.5 SECONDS)
		return
	active = TRUE
	radiation_pulse(
		src,
		max_range = (radioactivity * 0.5),
		threshold = RAD_HEAVY_INSULATION,
		chance = DEFAULT_RADIATION_CHANCE,
		strength = radioactivity * 0.5
	)
	last_event = world.time
	active = FALSE

/obj/item/fuel_assembly/Destroy()
	STOP_PROCESSING(SSobj, src)
	return ..()


/obj/item/fuel_assembly/Initialize(mapload, _material, _colour)
	. = ..()
	fuel_type = _material
	fuel_colour = _colour
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
			radioactivity = mat_rad
			desc += " It is warm to the touch."
			START_PROCESSING(SSobj, src)
		if(mat_lum)
			set_light(mat_lum, mat_lum, material.icon_colour)
	else
		name = "[fuel_type] fuel rod assembly"
		desc = "A fuel rod for a fusion reactor. This one is made from [fuel_type]."

	icon_state = "blank"
	var/image/I = image(icon, "fuel_assembly")
	I.color = fuel_colour
	add_overlay(list(I, image(icon, "fuel_assembly_bracket")))
	rod_quantities[fuel_type] = initial_amount

// Mapper shorthand.
/obj/item/fuel_assembly/deuterium/Initialize(mapload)
	. = ..(mapload, MAT_DEUTERIUM)

/obj/item/fuel_assembly/tritium/Initialize(mapload)
	. = ..(mapload, MAT_TRITIUM)

/obj/item/fuel_assembly/phoron/Initialize(mapload)
	. = ..(mapload, MAT_PHORON)

/obj/item/fuel_assembly/supermatter/Initialize(mapload)
	. = ..(mapload, MAT_SUPERMATTER)


// === merged from fuel_assembly_ch.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/fuel_assembly/blitz
	name = "blitz rod"
	desc = "A highly unstable mixture of supermatter and phoron. It's probably not a good idea to try to use this in a reactor..."
	fuel_colour = "#FCE300"
	fuel_type = "blitz"

/obj/item/fuel_assembly/blitz/Initialize(mapload)
	. = ..(mapload, "blitz")

/obj/item/fuel_assembly/blitz/unshielded/Initialize(mapload)
	. = ..()
	name = "unshielded blitz rod"
	desc = "An extremely unstable, raw rod of compressed supermatter and phoron. This seems like a terrible idea."
	fuel_colour = "#FCE300"
	fuel_type = "blitzu"
	icon_state = "blank"
	var/image/I = image(icon, "fuel_assembly")
	I.color = "#FCE300"
	overlays += list(I, image(icon, "fuel_assembly_bracket"),image(icon,"glow"))
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
		qdel(src)

/obj/item/fuel_assembly/blitz/unshielded/attackby(obj/item/I, mob/user as mob)
	..()
	var/obj/item/stack/material/lead/M = I
	if(istype(M))
		if(M.get_amount() > 5)
			to_chat(user,span_notice("You add a lead shell to the blitz rod."))
			qdel(src)
			var/obj/item/fuel_assembly/blitz/shielded/rod = new(get_turf(user))
			user.put_in_hands(rod)
			return
		else
			to_chat(user,span_warning("You need at least five sheets of lead to add shielding!"))

/obj/item/fuel_assembly/blitz/unshielded/attack_hand(mob/user)
	. = ..()

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
	var/obj/item/clothing/gloves/G = H.gloves
	if(istype(G) && ((G.flags & THICKMATERIAL && prob(70)) || istype(G, /obj/item/clothing/gloves/gauntlets)))
		return

	H.visible_message(span_danger("\The [src] flashes as it scorches [H]'s hand!"))

	if(H.hand)
		H.apply_damage(7, BURN, "l_hand", used_weapon="Blitz Rod")
	else
		H.apply_damage(7, BURN, "r_hand", used_weapon="Blitz Rod")
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
	icon_state = "blank"
	var/image/I = image(icon, "fuel_assembly")
	I.color = "#76888F"
	overlays += list(I, image(icon, "fuel_assembly_bracket"),image(icon,"glow"))
	rod_quantities[fuel_type] = initial_amount
	set_light(2, 2, "#FCE300")
