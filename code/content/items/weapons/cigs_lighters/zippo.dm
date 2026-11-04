/////////
//ZIPPO//
/////////
/obj/item/flame/lighter/zippo
	name = "\improper Zippo lighter"
	desc = "The zippo."
	icon_state = "zippo"
	item_state = "zippo"
	activation_sound = SFX_ITEMS_ZIPPO_ON
	deactivation_sound = SFX_ITEMS_ZIPPO_OFF
	special_variant = TRUE
	cheap_look = FALSE

CAPABILITIES(/obj/item/flame/lighter/zippo)
	configure(atom_rules(price_tag = 5, description_fluff = "Still going after all these years."))

/// A zippo flips open and shut with its own states.
/obj/item/flame/lighter/zippo/toggled(datum/act/op/A)
	var/mob/living/user = A.actor
	if(detonator_mode)
		return OP_DECLINE
	if(!base_state)
		base_state = icon_state
	if(!lit)
		set_lit(TRUE)
		set_icon_state("[base_state]on")
		set_item_state("[base_state]on")
		playsound(src, activation_sound, 75, 1)
		act_message(user, src, others = span_notice(span_rose("Without even breaking stride, %U% flips open and lights %T% in one smooth movement.")))

		set_glow(src, GLOW(2, 0.5, "#FF9933"))
	else
		set_lit(FALSE)
		set_icon_state("[base_state]")
		set_item_state("[base_state]")
		playsound(src, deactivation_sound, 75, 1)
		act_message(user, src, others = span_notice(span_rose("You hear a quiet click, as %U% shuts off %T% without even looking at what they're doing.")))

		set_glow(src, GLOW(0, null, null))
	return OP_OK

//Here we add Zippo skins.

/obj/item/flame/lighter/zippo/black
	name = "\improper holy Zippo lighter"
	desc = "Only in regards to Christianity, that is."
	icon_state = "blackzippo"

/obj/item/flame/lighter/zippo/blue
	name = "\improper blue Zippo lighter"
	icon_state = "bluezippo"

/obj/item/flame/lighter/zippo/engraved
	name = "\improper engraved Zippo lighter"
	icon_state = "engravedzippo"
	item_state = "zippo"

/obj/item/flame/lighter/zippo/gold
	name = "\improper golden Zippo lighter"
	icon_state = "goldzippo"

/obj/item/flame/lighter/zippo/moff
	name = "\improper moth Zippo lighter"
	desc = "Too cute to be a Tymisian."
	icon_state = "moffzippo"

/obj/item/flame/lighter/zippo/red
	name = "\improper red Zippo lighter"
	icon_state = "redzippo"

/obj/item/flame/lighter/zippo/ironic
	name = "\improper ironic Zippo lighter"
	desc = "What a quiant idea."
	icon_state = "ironiczippo"

/obj/item/flame/lighter/zippo/capitalist
	name = "\improper capitalist Zippo lighter"
	desc = "Made of gold and obsidian, this is truly not worth however much you spent on it."
	icon_state = "cappiezippo"

/obj/item/flame/lighter/zippo/communist
	name = "\improper communist Zippo lighter"
	desc = "All you need to spark a revolution."
	icon_state = "commiezippo"

/obj/item/flame/lighter/zippo/royal
	name = "\improper royal Zippo lighter"
	desc = "An incredibly fancy lighter, gilded and covered in the color of royalty."
	icon_state = "royalzippo"

/obj/item/flame/lighter/zippo/gonzo
	name = "\improper Gonzo Zippo lighter"
	desc = "A lighter with the iconic Gonzo fist painted on it."
	icon_state = "gonzozippo"

/obj/item/flame/lighter/zippo/rainbow
	name = "\improper rainbow Zippo lighter"
	icon_state = "rainbowzippo"

/obj/item/flame/lighter/zippo/skull
	name = "\improper badass Zippo lighter"
	desc = "An absolutely badass zippo lighter. Just look at that skull!"
	icon_state = "skullzippo"
