
// Light Replacer (LR)
//
// ABOUT THE DEVICE
//
// This is a device supposedly to be used by Janitors and Janitor Cyborgs which will
// allow them to easily replace lights. This was mostly designed for Janitor Cyborgs since
// they don't have hands or a way to replace lightbulbs.
//
// HOW IT WORKS
//
// You attack a light fixture with it, if the light fixture is broken it will replace the
// light fixture with a working light; the broken light is then placed on the floor for the
// user to then pickup with a trash bag. If it's empty then it will just place a light in the fixture.
//
// HOW TO REFILL THE DEVICE
//
// It can be manually refilled or by clicking on a storage item containing lights.
// If it's part of a robot module, it will charge when the Robot is inside a Recharge Station.
//
// EMAGGED FEATURES
//
// NOTICE: The Cyborg cannot use the emagged Light Replacer and the light's explosion was nerfed. It cannot create holes in the station anymore.
//
// I'm not sure everyone will react the emag's features so please say what your opinions are of it.
//
// When emagged it will rig every light it replaces, which will explode when the light is on.
// This is VERY noticable, even the device's name changes when you emag it so if anyone
// examines you when you're holding it in your hand, you will be discovered.
// It will also be very obvious who is setting all these lights off, since only Janitor Borgs and Janitors have easy
// access to them, and only one of them can emag their device.
//
// The explosion cannot insta-kill anyone with 30% or more health.

/obj/item/lightreplacer

	name = "light replacer"
	desc = "A device to automatically replace lights. Refill with working lightbulbs or sheets of glass."
	force = 8
	icon = 'icons/obj/janitor.dmi'
	icon_state = "lightreplacer0"
	slot_flags = SLOT_BELT

	var/max_uses = 32
	var/uses = 32
	var/emagged = 0
	var/failmsg = ""
	var/charge = 0
	var/selected_color = LIGHT_COLOR_INCANDESCENT_TUBE //Default color!

	// Eating used bulbs gives us bulb shards
	var/bulb_shards = 0
	// when we get this many shards, we get a free bulb.
	var/shards_required = 4
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

	///For attack_self chain
	var/special_handling = FALSE

/obj/item/lightreplacer/Initialize(mapload)
	. = ..()
	failmsg = "The [name]'s refill light blinks red."

/obj/item/lightreplacer/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		. += "It has [uses] lights remaining."

/// The replacer is declared (doc/rewrite/conversion_guide.md): glass and lights fill it, a light fixture is its target, an emag card
/// turns it on and off. Using it in the hand asks for a colour through the legacy prompt until the prompt kinds land.
TRACKED(/obj/item/lightreplacer, emagged)
TRACKED(/obj/item/lightreplacer, uses)
TRACKED(/obj/item/lightreplacer, max_uses)
TRACKED(/obj/item/lightpainter, resetmode)

CAPABILITIES(/obj/item/lightreplacer)
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	op("add_glass", inputs(stack(/obj/item/stack/material/glass, 1), stack(/obj/item/stack/material/cyborg/glass, 1)), wait(0),
		needs(req(PROC_REF(plain_glass), because = MSG(lightreplacer/bad_glass)), req(PROC_REF(has_room), because = MSG(lightreplacer/full))), then(PROC_REF(glass_in)))
	op("add_light", item(/obj/item/light), wait(0), then(PROC_REF(light_in)))
	op("fill_from_box", item(/obj/item/storage), wait(0), then(PROC_REF(fill_from_box)))
	op("replace", at_target(/obj/machinery/light), wait(0), then(PROC_REF(replace_light_at)))
	op("colour", in_hand(), when(PROC_REF(say_uses)), wait(0), asks(/datum/prompt/color, fields = list("question" = "Choose a color to set the light to! (Default is [LIGHT_COLOR_INCANDESCENT_TUBE])", "default" = nameof(selected_color))), then(PROC_REF(colour_asked)))

MSG_DEF_SELF(lightreplacer/bad_glass, "That is not glass.")
MSG_DEF_SELF(lightreplacer/full, "The light replacer is full.")

/// Old attackby never called ..() regardless of item type, so every click was swallowed.
/obj/item/lightreplacer/draw(datum/look/look)
	..()
	look.state("lightreplacer[emagged]")

/// Reinforced glass is no glass for the replacer.
/obj/item/lightreplacer/proc/plain_glass(datum/act/op/A)
	return (!istype(A.held, /obj/item/stack/material/glass/reinforced)) ? null : MSG(lightreplacer/bad_glass)

/obj/item/lightreplacer/proc/has_room(datum/act/op/A)
	return (uses < max_uses) ? null : MSG(lightreplacer/full)

/// A sheet of glass makes sixteen lights.
/obj/item/lightreplacer/proc/glass_in(datum/act/op/A)
	add_uses(16) //Autolathe converts 1 sheet into 16 lights.
	to_chat(A.actor, span_notice("You insert a piece of glass into \the [src.name]. You have [uses] light\s remaining."))
	return OP_OK

/// A light goes in: a working one is a light, a broken or burned one is glass for the shards.
/obj/item/lightreplacer/proc/light_in(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/light/L = A.held
	var/new_bulbs = 0
	if(L.status == LIGHT_OK)
		if(uses < max_uses)
			if(!user.unEquip(L))
				return OP_OK
			add_uses(1)
			consume(L, user)
	else
		if(!user.unEquip(L))
			return OP_OK
		new_bulbs += AddShards(1)
		consume(L, user)
	if(new_bulbs != 0)
		play_sfx(src, SFX_MACHINES_DING)
	to_chat(user, "You insert \the [L.name] into \the [src.name]. You have [uses] light\s remaining.")
	return OP_OK

/// A box of lights refills it from the lights in the box.
/obj/item/lightreplacer/proc/fill_from_box(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/storage/S = A.held
	var/found_lightbulbs = FALSE
	var/replaced_something = TRUE

	S.latent_materialize_all() // a walk needs real things (C5)
	for(var/obj/item/I in contents_of(S)) // ALLOW(latent): the contents were materialized by an earlier latent_materialize_all() in this proc, so this scan sees real objects
		if(istype(I,/obj/item/light))
			var/obj/item/light/L = I
			found_lightbulbs = TRUE
			if(src.uses >= max_uses)
				break
			if(L.status == LIGHT_OK)
				replaced_something = TRUE
				add_uses(1)
				consume(L, user)

			else if(L.status == LIGHT_BROKEN || L.status == LIGHT_BURNED)
				replaced_something = TRUE
				AddShards(1)
				consume(L, user)

	if(!found_lightbulbs)
		to_chat(user, span_warning("\The [S] contains no bulbs."))
		return OP_OK

	if(!replaced_something && src.uses == max_uses)
		to_chat(user, span_warning("\The [src] is full!"))
		return OP_OK

	to_chat(user, span_notice("You fill \the [src] with lights from \the [S]."))
	return OP_OK

/// The replacer used on a fixture.
/obj/item/lightreplacer/proc/replace_light_at(datum/act/op/A)
	if(isliving(A.actor))
		ReplaceLight(A.target, A.actor)
	return OP_OK

/// Using it in the hand says how many lights it has and asks for the colour of the lights it makes.
/obj/item/lightreplacer/proc/colour_asked(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(R?.value)
		selected_color = R.value
		to_chat(A.actor, "The light color has been changed.")
	return OP_OK

/obj/item/lightreplacer/proc/say_uses(datum/act/op/A)
	return !special_handling

/// The cyborg variant (dogborg/dog_modules.dm) says what its own use in the hand does: it asks for the reserves or the colour instead.

/obj/item/lightreplacer/proc/Use(mob/user)

	play_sfx(src, SFX_MACHINES_CLICK)
	add_uses(-1)
	return 1

// Negative numbers will subtract
/obj/item/lightreplacer/proc/add_uses(amount = 1)
	set_uses(min(max(uses + amount, 0), max_uses))

/obj/item/lightreplacer/proc/AddShards(amount = 1)
	bulb_shards += amount
	var/new_bulbs = round(bulb_shards / shards_required)
	if(new_bulbs > 0)
		add_uses(new_bulbs)
	bulb_shards = bulb_shards % shards_required
	return new_bulbs

/obj/item/lightreplacer/proc/Charge(mob/user, amount = 1)
	charge += amount
	if(charge > 6)
		add_uses(1)
		charge = 0

/obj/item/lightreplacer/proc/ReplaceLight(obj/machinery/light/target, mob/living/U)

	if(target.status != LIGHT_OK)
		if(CanUse(U))
			if(!Use(U)) return
			to_chat(U, span_notice("You replace the [target.get_fitting_name()] with the [src]."))

			if(target.status != LIGHT_EMPTY)
				var/new_bulbs = AddShards(1)
				if(new_bulbs != 0)
					to_chat(U, span_notice("\The [src] has fabricated a new bulb from the broken bulbs it has stored. It now has [uses] uses."))
					play_sfx(src, SFX_MACHINES_DING)
				target.set_status(LIGHT_EMPTY)
				rel_clear(target, nameof(target.installed_light)) //Remove the light! (its glass went into the shards)
				target.latent_bulb = FALSE
				target.refresh_light()

			var/obj/item/light/L2 = new target.light_type()
			L2.brightness_color = selected_color
			target.insert_bulb(L2) //Call the insertion proc.
			target.refresh_light()

			if(target.on && target.rigged)
				target.explode()
			return

		else
			to_chat(U, failmsg)
			return
	else
		to_chat(U, "There is a working [target.get_fitting_name()] already inserted.")
		return

/// The emag card turns the replacer on and off.
/obj/item/lightreplacer/proc/on_emag(datum/act/op/A)
	set_emagged(!emagged)
	play_sfx(src, SFX_SPARKS, 2)
	return OP_OK

//Can you use it?

/obj/item/lightreplacer/proc/CanUse(mob/living/user)
	src.add_fingerprint(user)
	//Not sure what else to check for. Maybe if clumsy?
	if(uses > 0)
		return 1
	else
		return 0

// Light Painter.

MATERIAL_MIX(/obj/item/lightpainter, list(MAT_STEEL = 5000,MAT_GLASS = 1500))
/obj/item/lightpainter
	name = "light painter"
	desc = "A device to configure the emission color of lighting fixtures. Use this device in-hand to set/reset the color. Use the device on a light fixture to assign the color."
	icon = 'icons/obj/janitor.dmi'
	icon_state = "lightreplacer0"
	color = "#bbbbff"
	slot_flags = SLOT_BELT


	var/static/dcolor = "#e0eff0"
	var/static/dnightcolor = "#efcc86"
	//set color values.
	var/setcolor = "#e0eff0"
	var/setnightcolor = "#efcc86"
	var/resetmode = 1

	var/dimming = 0.7 // multiply value to dim lights from setcolor to nightcolor

/obj/item/lightpainter/examine(mob/user)
	. = ..()
	if(get_dist(user, src) <= 2)
		if(resetmode)
			. += "It is currently resetting light colors."
		else
			. += "It is currently coloring lights."

CAPABILITIES(/obj/item/lightpainter)
	op("paint", at_target(/obj/machinery/light), wait(0), then(PROC_REF(paint_light)))
	op("use", in_hand(), wait(0), asks(/datum/prompt/color, fields = list("question" = "Choose Light Color", "default" = nameof(setcolor)), when = PROC_REF(not_painting)), then(PROC_REF(used_in_hand)))

/// The painter used on a fixture.
/obj/item/lightpainter/proc/paint_light(datum/act/op/A)
	if(isliving(A.actor))
		ColorLight(A.target, A.actor)
	return OP_OK

/// Using the painter in the hand: while it paints it goes back to reset mode; in reset mode it asks for the colour it paints.
/obj/item/lightpainter/proc/not_painting(datum/act/A)
	return !!resetmode

/obj/item/lightpainter/proc/used_in_hand(datum/act/op/A)
	var/datum/prompt/R = A.answer
	if(!R)
		set_resetmode(1)
		to_chat(A.actor, span_infoplain("Painter reset."))
		return OP_OK
	if(!R.value)
		return OP_OK
	setcolor = sanitize_hexcolor(R.value)
	var/list/setcolorRGB = hex2rgb(setcolor)
	var/setcolorR = num2hex(setcolorRGB[1] * dimming, 2)
	var/setcolorG = num2hex(setcolorRGB[2] * dimming, 2)
	var/setcolorB = num2hex(setcolorRGB[3] * dimming, 2)
	setnightcolor = addtext("#", setcolorR, setcolorG, setcolorB)
	set_resetmode(0)
	to_chat(A.actor, span_infoplain("Painter color set."))
	return OP_OK

/obj/item/lightpainter/proc/ColorLight(obj/machinery/light/target, mob/living/U)

	src.add_fingerprint(U)

	if(resetmode)
		to_chat(U, span_notice("You reset the color of the [target.get_fitting_name()]."))
		target.brightness_color = dcolor
		target.brightness_color_ns = dnightcolor
	else
		to_chat(U, span_notice("You set the color of the [target.get_fitting_name()]."))

		target.brightness_color = setcolor
		target.brightness_color_ns = setnightcolor

	if(target.nightshift_enabled)
		target.light_color = target.brightness_color_ns
	else
		target.light_color = target.brightness_color

	target.set_light(0)
	target.refresh_light()
