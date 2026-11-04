/obj/item/material/butterfly
	name = "butterfly knife"
	desc = "A basic metal blade concealed in a lightweight plasteel grip. Small enough when folded to fit in a pocket."
	//description_fluff = "This could be used to engrave messages on suitable surfaces if you really put your mind to it! Alt-click a floor or wall to engrave with it." //This way it's not a completely hidden, arcane art to engrave.
	icon_state = "butterflyknife"
	item_state = null
	var/active = 0
	w_class = ITEMSIZE_SMALL
	force_divisor = 0.25 // 15 when wielded with hardness 60 (steel)
	thrown_force_divisor = 0.25 // 5 when thrown with weight 20 (steel)

/obj/item/material/butterfly/update_force()
	if(active)
		set_edge(TRUE)
		set_sharp(TRUE)
		..() //Updates force.
		set_throwforce(max(3,combat_of(src).force-3))
		set_hitsound(SFX_WEAPONS_BLADESLICE)
		set_icon_state(icon_state + ("_open"))
		set_w_class(ITEMSIZE_NORMAL)
		set_attack_verb(list("attacked", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut"))
	else
		set_force(3)
		set_edge(FALSE)
		set_sharp(FALSE)
		set_hitsound(sounds_of_type(type).hit)
		set_icon_state(initial(icon_state))
		set_w_class(initial(w_class))
		set_attack_verb(combat_of_type(type).attack_verbs)

/obj/item/material/butterfly/switchblade
	name = "switchblade"
	desc = "A classic switchblade with gold engraving. Just holding it makes you feel like a gangster."
	icon_state = "switchblade"

/obj/item/material/butterfly/boxcutter
	name = "box cutter"
	desc = "A thin, inexpensive razor-blade knife designed to open cardboard boxes."
	icon_state = "boxcutter"
	force_divisor = 0.1 // 6 when wielded with hardness 60 (steel)
	thrown_force_divisor = 0.2 // 4 when thrown with weight 20 (steel)


CAPABILITIES(/obj/item/material/butterfly)
	configure(item_combat(attack_verbs = list("patted", "tapped")))
	configure(item_sounds(hit = TRAIT_NONE, drop = SFX_ITEMS_DROP_KNIFE, pickup = SFX_ITEMS_PICKUP_KNIFE))
	op("flip", in_hand(), label("Open or conceal blade"), then(PROC_REF(blade_flipped)))

/// Preserve the blade subtype's complete force and equipment update.
/obj/item/material/butterfly/proc/blade_flipped(datum/act/op/A)
	var/mob/user = A.actor
	set_active(!active)
	update_force()

	if(user)
		if(active)
			to_chat(user, span_notice("You flip out \the [src]."))
			play_sfx(src, SFX_WEAPONS_FLIPBLADE, 0.3)
		else
			to_chat(user, span_notice("\The [src] can now be concealed."))
		add_fingerprint(user)
	return OP_OK
