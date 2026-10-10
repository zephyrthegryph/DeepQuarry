//trees
/obj/structure/flora/tree
	name = "tree"
	anchored = TRUE
	density = TRUE
	pixel_x = -16
	plane = MOB_PLANE // You know what, let's play it safe.
	layer = ABOVE_MOB_LAYER
	var/base_state = null	// Used for stumps.
	max_integrity = 200		// Used for chopping down trees.
	var/shake_animation_degrees = 4	// How much to shake the tree when struck.  Larger trees should have smaller numbers or it looks weird.
	var/product = null	// What you get when chopping this tree down.  Generally it will be a type of wood.
	var/product_amount = 10 // How much of a stack you get, if the above is defined.
	var/is_stump = FALSE // If true, suspends damage tracking and most other effects.
	var/indestructable = FALSE // If true, the tree cannot die.

TRACKED(/obj/structure/flora/tree, is_stump)

TYPE_TABLE_DECLARE(/obj/structure/flora/tree, winter_icon_suffix, FALSE)

/// Rolled before init: the tree's look (a winter tree one of six, a pine one of three).
/obj/structure/flora/tree/roll_icon_state(datum/roller/R)
	if(TYPE_TABLE_GET(src, winter_icon_suffix))
		return "[base_state][R.number(1, 6)]"
	return choose_icon_state(R)

/obj/structure/flora/tree/update_transform()
	var/matrix/M = matrix()
	M.Scale(icon_scale_x, icon_scale_y)
	M.Translate(0, 16*(icon_scale_y-1))
	animate(src, transform = M, time = 10)

// Override this for special icons.
/obj/structure/flora/tree/proc/choose_icon_state(datum/roller/R)
	return icon_state

/obj/structure/flora/tree/can_harvest(obj/item/I)
	. = FALSE
	if(!is_stump && harvest_tool && istype(I, harvest_tool) && harvest_loot && harvest_loot.len && harvest_count < max_harvests)
		. = TRUE
	return .

// Trees harvest through flora's own interaction_item() when the item qualifies; otherwise the tree replaces it with its own hit and dig.
CAPABILITIES(/obj/structure/flora/tree)
	without("item")
	without("uproot")
	op("dig_stump", item(/obj/item/shovel), label("Dig up the stump"), when(nameof(is_stump)), priority(OP_PRIORITY_PART), wait(5 SECONDS), then(PROC_REF(chop_done)))
	op("tree_hit", item(/obj/item), label("Use"), then(PROC_REF(interaction_hit)))
	op("search_sticks", hand(), ungated(), label("Search for sticks"), needs(req(PROC_REF(has_sticks), because = MSG(tree/no_sticks))), begins(MSG(tree/searching_sticks)), wait(5 SECONDS), then(PROC_REF(sticks_found)))
	extend(/datum/act/hit/explosion, instead(then(PROC_REF(tree_blast))))

/// Old attackby: harvest (flora's own harvest), dig up a stump, or take a hit.
/obj/structure/flora/tree/proc/interaction_hit(datum/act/op/A)
	var/mob/living/user = A.actor
	var/obj/item/W = A.held
	if(can_harvest(W))
		return interaction_item(A)

	if(is_stump)
		return OP_OK

	act_message(user, src, others = span_danger("%U% hits %T% with %I%!"), item = W)

	var/damage_to_do = W.force
	if(!W.sharp && !W.edge)
		damage_to_do = round(damage_to_do / 4)
	if(damage_to_do > 0)
		if(W.sharp && W.edge)
			play_sfx(src, SFX_EFFECTS_WOODCUTTING, 0.5)
		else
			playsound(src, W.hitsound, 50, 1)
		if(damage_to_do > 5 && !indestructable)
			adjust_health(-damage_to_do)
		else
			to_chat(user, span_warning("\The [W] is ineffective at harming \the [src]."))

	hit_animation()
	user.setClickCooldown(user.get_attack_speed(W))
	user.do_attack_animation(src)
	return OP_OK

/obj/structure/flora/tree/proc/chop_done(datum/act/op/A)
	act_message(A.actor, src, others = span_infoplain(span_bold("%U%") + " digs up %T% stump with %I%."), item = A.held)
	consume(src, A.actor)

// Shakes the tree slightly, more or less stolen from lockers.
/obj/structure/flora/tree/proc/hit_animation()
	var/init_px = pixel_x
	var/shake_dir = pick(-1, 1)
	var/matrix/M = matrix()
	M.Scale(icon_scale_x, icon_scale_y)
	M.Translate(0, 16*(icon_scale_y-1))
	animate(src, transform=turn(M, shake_animation_degrees * shake_dir), pixel_x=init_px + 2*shake_dir, time=1)
	animate(transform=M, pixel_x=init_px, time=6, easing=ELASTIC_EASING)

// Used when the tree gets hurt.  amount is the (negative) health delta, kept for the
// legacy callers and the product-degradation math.
/obj/structure/flora/tree/proc/adjust_health(amount, damage_wood = FALSE)
	if(is_stump || indestructable)
		return

	// Bullets and lasers ruin some of the wood
	if(damage_wood && product_amount > 0)
		var/wood = initial(product_amount)
		product_amount -= round(wood * (abs(amount)/max_integrity))

	take_damage(abs(amount), BRUTE, MELEE, sound_effect = FALSE)

// Felling the tree at 0 integrity turns it into a persistent stump rather than
// deleting it, so we handle it here instead of letting the base qdel the tree.
/obj/structure/flora/tree/atom_destruction(damage_flag)
	SHOULD_CALL_PARENT(FALSE)
	if(is_stump || indestructable)
		return
	die()

// Called when the tree loses all health, for whatever reason.
/obj/structure/flora/tree/proc/die()
	if(is_stump || indestructable)
		return

	if(product && product_amount) // Make wooden logs.
		new product(get_turf(src), product_amount)
	visible_message(span_danger("\The [src] is felled!"))
	stump()

// Makes the tree into a mostly non-interactive stump.
/obj/structure/flora/tree/proc/stump()
	if(is_stump)
		return

	set_is_stump(TRUE)
	set_density(FALSE)
	icon_state = "[base_state]_stump"
	cut_overlays() // For the Sif tree and other future glowy trees.
	set_light(0)


/// A blast tears into the tree through its own health, ruining some of the wood.
/obj/structure/flora/tree/proc/tree_blast(datum/act/hit/explosion/A)
	adjust_health(-(max_integrity / A.packet.severity), TRUE)
	return TRUE

/obj/structure/flora/tree/bullet_act(obj/item/projectile/Proj)
	if(Proj.get_structure_damage())
		adjust_health(-Proj.get_structure_damage(), TRUE)

/obj/structure/flora/tree/get_description_interaction()
	var/list/results = list()

	if(!is_stump)
		results += "[desc_panel_image("hatchet")]to cut down this tree into logs.  Any sharp and strong weapon will do."

	results += ..()

	return results

// Subtypes.

// Pine trees

/obj/structure/flora/tree/pine
	name = "pine tree"
	icon = 'icons/obj/flora/pinetrees.dmi'
	icon_state = "pine_1"
	base_state = "pine"
	product = /obj/item/stack/material/log
	shake_animation_degrees = 3

/obj/structure/flora/tree/pine/choose_icon_state(datum/roller/R)
	return "[base_state]_[R.number(1, 3)]"

// ition Start 15/2/20 TFF - Holodeck variation trees, drop no wood.
/obj/structure/flora/tree/pine/holo
	product = null
	product_amount = 0
// ition End


/obj/structure/flora/tree/pine/xmas
	name = "xmas tree"
	icon = 'icons/obj/flora/pinetrees.dmi'
	icon_state = "pine_c"

/obj/structure/flora/tree/pine/xmas/presents
	icon_state = "pinepresents"
	desc = "A wondrous decorated Christmas tree. It has presents!"
	indestructable = TRUE
	var/gift_type = /obj/item/a_gift
	var/list/ckeys_that_took

TRACKED(/obj/structure/flora/tree/pine/xmas/presents, ckeys_that_took)

CAPABILITIES(/obj/structure/flora/tree/pine/xmas/presents)
	op("take_present", hand(), label("Take a present"), priority(OP_PRIORITY_NORMAL + 1), needs(req(PROC_REF(can_take_present), because = MSG(xmas_presents/none_left))), then(PROC_REF(interaction_hand)))

/obj/structure/flora/tree/pine/xmas/presents/choose_icon_state(datum/roller/R)
	return "pinepresents"

/// Requirement: one present per player.
/obj/structure/flora/tree/pine/xmas/presents/proc/can_take_present(datum/act/op/A)
	return (!read_once(present_taken(A.actor))) ? null : MSG(xmas_presents/none_left) // a player's key is fixed while it plays

/// Has `user`'s player already taken a present from this tree?
/obj/structure/flora/tree/pine/xmas/presents/proc/present_taken(mob/user)
	return user.ckey && LAZYACCESS(ckeys_that_took, user.ckey)

MSG_DEF_SELF(xmas_presents/none_left, "There are no presents with your name on.")

/// Old attack_hand: take a present, once per ckey.
/obj/structure/flora/tree/pine/xmas/presents/proc/interaction_hand(datum/act/op/A)
	var/mob/living/user = A.actor
	if(!user.ckey)
		return OP_OK

	to_chat(user, span_notice("After a bit of rummaging, you locate a gift with your name on it!"))
	var/list/takers = ckeys_that_took ? ckeys_that_took.Copy() : list()
	takers[user.ckey] = TRUE
	set_ckeys_that_took(takers)
	var/obj/item/G = new gift_type(src)
	user.put_in_hands(G)
	return OP_OK

// Palm trees

/obj/structure/flora/tree/palm
	icon = 'icons/obj/flora/palmtrees.dmi'
	icon_state = "palm1"
	base_state = "palm"
	product = /obj/item/stack/material/log
	product_amount = 5
	max_integrity = 200
	pixel_x = 0

/obj/structure/flora/tree/palm/choose_icon_state(datum/roller/R)
	return "[base_state][R.number(1, 2)]"


// Dead trees

/obj/structure/flora/tree/dead
	icon = 'icons/obj/flora/deadtrees.dmi'
	icon_state = "tree_1"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 5
	max_integrity = 200

/obj/structure/flora/tree/dead/choose_icon_state(datum/roller/R)
	return "[base_state]_[R.number(1, 6)]"

// ition Start 15/2/20 TFF - Holodeck variation trees, drop no wood.
/obj/structure/flora/tree/dead/holo
	product = null
	product_amount = 0
// ition End

// Small jungle trees

/obj/structure/flora/tree/jungle_small
	icon = 'icons/obj/flora/jungletreesmall.dmi'
	icon_state = "tree"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 10
	max_integrity = 400
	pixel_x = -32

/obj/structure/flora/tree/jungle_small/choose_icon_state(datum/roller/R)
	return "[base_state][R.number(1, 6)]"

// Big jungle trees

/obj/structure/flora/tree/jungle
	icon = 'icons/obj/flora/jungletree.dmi'
	icon_state = "tree"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 20
	max_integrity = 800
	pixel_x = -48
	pixel_y = -16
	shake_animation_degrees = 2

/obj/structure/flora/tree/jungle/choose_icon_state(datum/roller/R)
	return "[base_state][R.number(1, 6)]"

// Winter Trees

/obj/structure/flora/tree/winter
	icon = 'icons/obj/flora/wintertree.dmi'
	icon_state = "tree"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 20
	max_integrity = 800
	pixel_x = -48
	pixel_y = -16
	shake_animation_degrees = 2

TYPE_TABLE(/obj/structure/flora/tree/winter, winter_icon_suffix, TRUE)


/obj/structure/flora/tree/winter1
	icon = 'icons/obj/flora/wintertreesmall-1.dmi'
	icon_state = "tree"
	base_state = "tree"
	product = /obj/item/stack/material/log
	product_amount = 20
	max_integrity = 800
	pixel_x = -48
	pixel_y = -16
	shake_animation_degrees = 2

TYPE_TABLE(/obj/structure/flora/tree/winter1, winter_icon_suffix, TRUE)

// Sif trees

/datum/category_item/catalogue/flora/sif_tree
	name = "Sivian Flora - Tree"
	desc = "The damp, shaded environment of Sif's most common variety of tree provides an ideal environment for a wide \
	variety of bioluminescent bacteria. The soft glow of the microscopic organisms in turn attracts several native microphagous \
	animals which act as an effective dispersal method. By this mechanism, new trees and bacterial colonies often sprout in \
	unison, having formed a symbiotic relationship over countless years of evolution.\
	<br><br>\
	Wood-like material can be obtained from this by cutting it down with a bladed tool."
	value = CATALOGUER_REWARD_TRIVIAL

/obj/structure/flora/tree/sif
	name = "glowing tree"
	desc = "It's a tree, except this one seems quite alien.  It glows a deep blue."
	icon = 'icons/obj/flora/deadtrees.dmi'
	icon_state = "tree_sif"
	base_state = "tree_sif"
	blocks_emissive = EMISSIVE_BLOCK_NONE
	product = /obj/item/stack/material/log/sif
	catalogue_data = list(/datum/category_item/catalogue/flora/sif_tree)
	randomize_size = TRUE

	harvest_tool = /obj/item/material/knife
	max_harvests = 2
	min_harvests = 0
	harvest_loot = list(
		/obj/item/reagent_containers/food/snacks/siffruit = 20,
		/obj/item/reagent_containers/food/snacks/grown/sif/sifpod = 5,
		/obj/item/seeds/sifbulb = 1
	)

	var/light_shift = 0

/obj/structure/flora/tree/sif/choose_icon_state(datum/roller/R)
	light_shift = R.number(0, 5)
	return "[base_state][light_shift]"

/obj/structure/flora/tree/sif/draw(datum/look/look)
	..()
	var/bulbs = (5 - light_shift)
	if(bulbs > 0)
		look.light(bulbs, 1, "#33ccff")	// 5 variants, missing bulbs. 5th has no bulbs, so no glow.
		look.overlay(mutable_appearance(icon, "[base_state][bulbs]_glow"))
		look.overlay(emissive_appearance(icon, "[base_state][bulbs]_glow"))
