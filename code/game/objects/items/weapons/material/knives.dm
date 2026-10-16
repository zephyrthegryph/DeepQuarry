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

/*
 * Kitchen knives
 */
/obj/item/material/knife
	name = "kitchen knife"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "knife"
	desc = "A general purpose " + JOB_CHEF + "'s Knife made by SpaceCook Incorporated. Guaranteed to stay sharp for years to come."
	//description_fluff = "This could be used to engrave messages on suitable surfaces if you really put your mind to it! Alt-click a floor or wall to engrave with it." //This way it's not a completely hidden, arcane art to engrave.
	injury_kind = INJURY_CUT
	force_divisor = 0.15 // 9 when wielded with hardness 60 (steel)
	MATERIAL_BULK(MAT_STEEL, 12000)

CAPABILITIES(/obj/item/material/knife)
	configure(item_surgery(cavity_implantable = FALSE))
	configure(item_combat(sharp = TRUE, edge = TRUE, attack_verbs = list("slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))
	configure(item_sounds(drop = SFX_ITEMS_DROP_KNIFE))

// These no longer inherit from hatchets.
/obj/item/material/knife/tacknife
	name = "tactical knife"
	desc = "You'd be killing loads of people if this was Medal of Valor: Heroes of Space."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "tacknife"
	item_state = "knife"
	force_divisor = 0.25 //15 when hardness 60 (steel)
	applies_material_colour = 1

CAPABILITIES(/obj/item/material/knife/tacknife)
	configure(item_combat(attack_verbs = list("stabbed", "chopped", "cut")))

/obj/item/material/knife/tacknife/combatknife
	name = "combat knife"
	desc = "If only you had a boot to put it in."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "tacknife2"
	item_state = "knife"
	force_divisor = 0.34 // 20 with hardness 60 (steel)
	thrown_force_divisor = 1.75 // 20 with weight 20 (steel)
	applies_material_colour = 1

CAPABILITIES(/obj/item/material/knife/tacknife/combatknife)
	configure(item_combat(attack_verbs = list("sliced", "stabbed", "chopped", "cut")))

// Identical to the tactical knife but nowhere near as stabby.
// Kind of like the toy esword compared to the real thing.
/obj/item/material/knife/tacknife/boot
	name = "boot knife"
	desc = "A small fixed-blade knife for putting inside a boot."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "tacknife3"
	item_state = "knife"
	force_divisor = 0.15
	applies_material_colour = 0

/obj/item/material/knife/hook
	name = "meat hook"
	desc = "A sharp, metal hook what sticks into things."
	icon_state = "hook_knife"

/obj/item/material/knife/ritual
	name = "ritual knife"
	desc = "The unearthly energies that once powered this blade are now dormant."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "render"
	applies_material_colour = 0

/obj/item/material/knife/table
	name = "table knife"
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "knife_table"
	injury_kind = INJURY_BLUNT
	force_divisor = 0.1

CAPABILITIES(/obj/item/material/knife/table)
	configure(item_combat(sharp = FALSE))

/obj/item/material/knife/table/plastic
	default_material = MAT_PLASTIC

/obj/item/material/knife/butch
	name = "butcher's cleaver"
	icon_state = "cleaver"
	desc = "A huge thing used for chopping and chopping up meat. This includes clowns and clown-by-products."
	force_divisor = 0.25 // 15 when wielded with hardness 60 (steel)

CAPABILITIES(/obj/item/material/knife/butch)
	configure(item_combat(attack_verbs = list("cleaved", "slashed", "stabbed", "sliced", "torn", "ripped", "diced", "cut")))

/obj/item/material/knife/machete
	name = "machete"
	desc = "A sharp machete often found in survival kits."
	icon_state = "machete"
	force_divisor = 0.3 // 18 when hardness 60 (steel)
	default_material = MAT_PLASTEEL

CAPABILITIES(/obj/item/material/knife/machete)
	configure(item_worn(slots = SLOT_BELT))
	configure(item_combat(attack_verbs = list("slashed", "chopped", "gouged", "ripped", "cut"), can_cleave = TRUE))

/obj/item/material/knife/machete/cyborg
	name = "integrated machete"
	desc = "A sharp machete often found attached to robots."
	unbreakable = TRUE

/obj/item/material/knife/tacknife/survival
	name = "survival knife"
	desc = "A hunting grade survival knife."
	icon = 'icons/obj/kitchen.dmi'
	icon_state = "survivalknife"
	item_state = "knife"
	applies_material_colour = FALSE
	default_material = MAT_PLASTEEL

CAPABILITIES(/obj/item/material/knife/tacknife/survival)
	configure(item_tooling(speed = 2))

/obj/item/material/knife/stone
	name = "stone blade"
	desc = "A crude blade made by chipping away at a piece of flint."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "stone_blade"
	applies_material_colour = FALSE
	fragile = TRUE
	dulled = TRUE
	default_material = MAT_FLINT

CAPABILITIES(/obj/item/material/knife/stone)
	configure(item_combat(edge = TRUE, sharp = TRUE))

/obj/item/material/knife/stone/wood
	name = "stone knife"
	desc = "A crude blade of flint with a wooden handle, secured with plant fibers twined into sturdy ropes. Useful for cutting, stabbing, slicing, and even shearing."
	icon_state = "stone_wood_knife"
	dulled = FALSE
	fragile = FALSE

/obj/item/material/knife/stone/bone
	name = "stone knife"
	desc = "A crude blade of flint with a bone handle, secured with plant fibers twined into sturdy ropes. Useful for cutting, stabbing, slicing, and even shearing."
	icon_state = "stone_bone_knife"
	dulled = FALSE
	fragile = FALSE


/obj/item/material/knife/machete/deluxe
	name = "deluxe machete"
	desc = "A fine example of a machete, with a polished blade, wooden handle and a leather cord loop."
	icon = 'icons/obj/weapons_vr.dmi'
	icon_state = "machetedx"
	item_state = "machete"
