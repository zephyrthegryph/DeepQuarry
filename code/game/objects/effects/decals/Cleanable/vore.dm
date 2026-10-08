/obj/effect/decal/cleanable/blood/reagent //Yes, we are using the blood system for this
	name = "liquid"
	dryname = "dried liquid"
	desc = "It's a liquid, how boring and bland."
	drydesc = "It's dry and crusty and boring and bland."
	basecolor = "#FFFFFF"
	var/ckey_source = null		//The person the liquid came from
	var/ckey_spawner = null		//The person who extracted the reagent

	var/custombasename = null
	var/custombasedesc = null
	var/custombasecolor = null

CAPABILITIES(/obj/effect/decal/cleanable/blood/reagent)
	param(nameof(spill_name), pos = 1)
	param(nameof(spill_color), pos = 2)
	param(nameof(spill_reagentid), pos = 3)
	param(nameof(amount), pos = 4)
	param(nameof(ckey_spawner), pos = 5)
	param(nameof(ckey_source), pos = 6)

/// The reagent spilled, its colour and id (its constructor params).
/obj/effect/decal/cleanable/blood/reagent/var/spill_name
/obj/effect/decal/cleanable/blood/reagent/var/spill_color
/obj/effect/decal/cleanable/blood/reagent/var/spill_reagentid

// ALLOW(init/INSTANCE_STATE): a spilled reagent's puddle takes the reagent's name and colour (blood and water keep their own)
/obj/effect/decal/cleanable/blood/reagent/Initialize(mapload)
	. = ..()
	switch(spill_reagentid)	//To ensure that if people spill some liquids, it wont cause issues with spawning, like spilling blood. Also allow for spilling of certain things to
		if("blood")
			return
		if("water")		//Dont recall if we have a water puddle system, but keeping this blacklisted, would be silly with dried water puddles.
			return

	name = "[spill_name]"
	dryname = "dried [spill_name]"
	desc = "It's a puddle of [spill_name]"
	drydesc = "It's a dried puddle of [spill_name]"
	set_basecolor(spill_color)

	custombasename = "[spill_name]"
	custombasedesc = "It's a puddle of [spill_name]"
	custombasecolor = basecolor

/// A puddle of a reagent other than blood or water is drawn in the reagent's colour, under its name; blood and water keep the blood's own look.
/obj/effect/decal/cleanable/blood/reagent/cleanable_look(datum/look/look)
	if(isnull(custombasename))
		return ..()
	look.set_color(dried ? adjust_brightness(custombasecolor, -50) : custombasecolor)
	if(dried)
		dried_look(look)
	else
		look.identity(name = custombasename, desc = custombasedesc)
	janitor_hud(look)

/obj/effect/decal/cleanable/blood/reagent/Crossed(mob/living/carbon/human/perp)
	//Nothing, we dont wanna spread our mess all over, at least not until people want that
