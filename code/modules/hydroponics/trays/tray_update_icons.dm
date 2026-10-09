/// The tray: named for its plant, the plant at its growth stage (dead, frozen, or in its colour), what is ready to pick, the cover, and the alert lights
/// of a mechanical tray (a sick plant, short of water or nutrient, weeds or pests, ready to harvest, frozen). A bioluminescent plant lights it.
/obj/machinery/portable_atmospherics/hydroponics/draw(datum/look/look)
	..()
	// Update name.
	var/shown = initial(name)
	if(seed)
		look.watch(seed)
		shown = mechanical ? "[base_name] ([seed.seed_name])" : "[seed.seed_name]"
	if(labelled)
		shown = "[shown] ([labelled])"
	look.identity(name = shown)

	// Updates the plant overlay.
	if(!isnull(seed))

		if(mechanical && health <= (seed.get_trait(TRAIT_ENDURANCE) / 2))
			look.overlay(tray_alert("over_lowhealth3"))

		if(dead)
			look.overlay(plant_look("[seed.get_trait(TRAIT_PLANT_ICON)]-dead"))
		else
			var/stages = seed.growth_stages || SSplants.plant_sprites[seed.get_trait(TRAIT_PLANT_ICON)]
			if(!stages)
				return
			var/overlay_stage = 1
			if(age >= seed.get_trait(TRAIT_MATURATION))
				overlay_stage = stages
			else
				var/maturation = seed.get_trait(TRAIT_MATURATION) / stages
				if(maturation < 1)
					maturation = 1
				overlay_stage = maturation ? max(1, round(age / maturation)) : 1
			look.overlay(plant_look("[seed.get_trait(TRAIT_PLANT_ICON)]-[overlay_stage]", frozen == 1, seed.get_trait(TRAIT_PLANT_COLOUR)))

			if(harvest && overlay_stage == stages)
				look.overlay(product_look(seed.get_trait(TRAIT_PRODUCT_ICON), seed.get_trait(TRAIT_PRODUCT_COLOUR), seed.get_trait(TRAIT_PLANT_COLOUR)))

	//Draw the cover.
	if(closed_system)
		look.overlay("hydrocover")

	//Updated the various alert icons.
	if(mechanical)
		if(waterlevel <= 10)
			look.overlay(tray_alert("over_lowwater3"))
		if(nutrilevel <= 2)
			look.overlay(tray_alert("over_lownutri3"))
		if(weedlevel >= 5 || pestlevel >= 5 || toxins >= 40)
			look.overlay(tray_alert("over_alert3"))
		if(harvest)
			look.overlay(tray_alert("over_harvest3"))
		if(frozen)
			look.overlay(tray_alert("over_frozen3"))

	// Update bioluminescence.
	if(seed?.get_trait(TRAIT_BIOLUM))
		look.light(round(seed.get_trait(TRAIT_POTENCY) / 10), color = seed.get_trait(TRAIT_BIOLUM_COLOUR) || null)
	else
		look.light_off()

/// An alert light of the tray, above the lighting.
/obj/machinery/portable_atmospherics/hydroponics/proc/tray_alert(state)
	return look_overlay_image(icon, state, plane = PLANE_LIGHTING_ABOVE)

/// The plant of `key` ("[icon]-[stage]" or "[icon]-dead"), in the colour of its seed (frozen or dead plants in theirs), shared by every tray that grows it.
/obj/machinery/portable_atmospherics/hydroponics/proc/plant_look(key, frozen_look = FALSE, colour)
	var/image/plant_overlay = SSplants.plant_icon_cache["[key]-[colour]"]
	if(dead)
		plant_overlay = SSplants.plant_icon_cache[key]
		if(!plant_overlay)
			plant_overlay = image('icons/obj/hydroponics_growing.dmi', "[key]")
			plant_overlay.color = DEAD_PLANT_COLOUR
			SSplants.plant_icon_cache[key] = plant_overlay
		return plant_overlay
	if(frozen_look)
		plant_overlay = image('icons/obj/hydroponics_growing.dmi', "[key]")
		plant_overlay.color = FROZEN_PLANT_COLOUR
		return plant_overlay
	if(!plant_overlay)
		plant_overlay = image('icons/obj/hydroponics_growing.dmi', "[key]")
		plant_overlay.color = colour
		SSplants.plant_icon_cache["[key]-[colour]"] = plant_overlay
	return plant_overlay

/// The ripe product on a grown plant, shared by every tray that grows it.
/obj/machinery/portable_atmospherics/hydroponics/proc/product_look(product_icon, product_colour, plant_colour)
	var/image/harvest_overlay = SSplants.plant_icon_cache["product-[product_icon]-[plant_colour]"]
	if(!harvest_overlay)
		harvest_overlay = image('icons/obj/hydroponics_products.dmi', "[product_icon]")
		harvest_overlay.color = product_colour
		SSplants.plant_icon_cache["product-[product_icon]-[plant_colour]"] = harvest_overlay
	return harvest_overlay
