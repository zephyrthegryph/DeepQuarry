/obj/item/clothing/shoes/syndigaloshes
	desc = "A pair of brown shoes. They seem to have extra grip."
	name = "brown shoes"
	icon_state = "brown"
	permeability_coefficient = 0.05
	item_flags = NOSLIP
	var/list/clothing_choices = list()
	siemens_coefficient = 0.8
	species_restricted = null
	step_volume_mod = 0.5
	drop_sound = 'sound/items/drop/rubber.ogg'
	pickup_sound = 'sound/items/pickup/rubber.ogg'
	resistance_flags = FIRE_PROOF | ACID_PROOF

/obj/item/clothing/shoes/mime
	name = "mime shoes"
	icon_state = "white"
	step_volume_mod = 0	//It's a mime

/obj/item/clothing/shoes/galoshes
	desc = "Rubber boots"
	name = "galoshes"
	icon_state = "galoshes"
	permeability_coefficient = 0.05
	siemens_coefficient = 0 //They're thick rubber boots! Of course they won't conduct electricity!
	item_flags = NOSLIP
	slowdown = SHOES_SLOWDOWN+0.5
	species_restricted = null
	drop_sound = 'sound/items/drop/rubber.ogg'
	pickup_sound = 'sound/items/pickup/rubber.ogg'
	resistance_flags = ACID_PROOF

/obj/item/clothing/shoes/dress
	name = "dress shoes"
	desc = "Sharp looking low quarters, perfect for a formal uniform."
	icon_state = "laceups"

/obj/item/clothing/shoes/dress/white
	name = "white dress shoes"
	desc = "Brilliantly white low quarters, not a spot on them."
	icon_state = "whitedress"

/obj/item/clothing/shoes/sandal
	desc = "A pair of rather plain, wooden sandals."
	name = "sandals"
	icon_state = "wizard"
	species_restricted = null
	body_parts_covered = 0

	wizard_garb = 1

/obj/item/clothing/shoes/sandals
	desc = "A pair of simple sandals."
	name = "sandals"
	icon_state = "sandals_recolor"

/obj/item/clothing/shoes/flipflop
	name = "flip flops"
	desc = "A pair of foam flip flops. For those not afraid to show a little ankle."
	icon_state = "thongsandal"
	addblends = "thongsandal_a"

/obj/item/clothing/shoes/cookflop
	name = "grilling sandals"
	desc = "All this talk of antags, greytiding, and griefing... I just wanna grill for god's sake!"
	icon_state = "cookflops"
	species_restricted = null
	body_parts_covered = 0

/obj/item/clothing/shoes/tourist_1
	name = "tourist sandals"
	desc = "Black sandals usually worn by tourists. Need I say more?"
	icon_state = "tourist_1"
	species_restricted = null
	body_parts_covered = 0

/obj/item/clothing/shoes/tourist_2
	name = "tourist sandals"
	desc = "Green sandals usually worn by tourists. Need I say more?"
	icon_state = "tourist_2"
	species_restricted = null
	body_parts_covered = 0

/obj/item/clothing/shoes/sandal/clogs
	name = "plastic clogs"
	desc = "A pair of plastic clog shoes."
	icon_state = "clogs"

/obj/item/clothing/shoes/sandal/marisa
	desc = "A pair of magic, black shoes."
	name = "magic shoes"
	icon_state = "black"
	body_parts_covered = FEET

/obj/item/clothing/shoes/clown_shoes
	desc = "The prankster's standard-issue clowning shoes. Damn they're huge!"
	name = "clown shoes"
	icon_state = "clown"
	slowdown = SHOES_SLOWDOWN+0.5
	force = 0
	//CHOMPRemove - removed built in squeak sounds
	species_restricted = null

/*	CHOMPEdit - Replaced with squeak component
/obj/item/clothing/shoes/clown_shoes/handle_movement(turf/walking, running)
	if(running)
		if(footstep >= 2)
			footstep = 0
			playsound(src, "clownstep", 50, 1) // this will get annoying very fast.
		else
			footstep++
	else
		playsound(src, "clownstep", 20, 1)
*/

/obj/item/clothing/shoes/cult
	name = "boots"
	desc = "A pair of boots worn by the followers of Nar-Sie."
	icon_state = "cult"
	item_state_slots = list(slot_r_hand_str = "cult", slot_l_hand_str = "cult")
	force = 2
	siemens_coefficient = 0.7

	min_cold_protection_temperature = SHOE_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = SHOE_MAX_HEAT_PROTECTION_TEMPERATURE
	species_restricted = null

/obj/item/clothing/shoes/cult/cultify()
	return

/obj/item/clothing/shoes/cyborg
	name = "cyborg boots"
	desc = "Shoes for a cyborg costume"
	icon_state = "boots"

/obj/item/clothing/shoes/slippers
	name = "bunny slippers"
	desc = "Fluffy!"
	icon_state = "slippers"
	force = 0
	species_restricted = null
	w_class = ITEMSIZE_SMALL
	drop_sound = 'sound/items/drop/clothing.ogg'
	pickup_sound = 'sound/items/pickup/clothing.ogg'

/obj/item/clothing/shoes/slippers/worn
	name = "worn bunny slippers"
	desc = "Fluffy..."
	icon_state = "slippers_worn"
	item_state_slots = list(slot_r_hand_str = "slippers", slot_l_hand_str = "slippers")

/obj/item/clothing/shoes/laceup
	name = "black oxford shoes"
	icon_state = "oxford_black"

/obj/item/clothing/shoes/laceup/grey
	name = "grey oxford shoes"
	icon_state = "oxford_grey"

/obj/item/clothing/shoes/laceup/brown
	name = "brown oxford shoes"
	icon_state = "oxford_brown"

/obj/item/clothing/shoes/swimmingfins
	desc = "Help you swim good."
	name = "swimming fins"
	icon_state = "flippers"
	item_state_slots = list(slot_r_hand_str = "galoshes", slot_l_hand_str = "galoshes")
	item_flags = NOSLIP
	slowdown = SHOES_SLOWDOWN+0.5
	species_restricted = null

/obj/item/clothing/shoes/athletic
	name = "athletic shoes"
	desc = "A pair of sleek athletic shoes. Made by and for the sporty types."
	icon_state = "sportshoe"
	addblends = "sportshoe_a"
	item_state_slots = list(slot_r_hand_str = "sportheld", slot_l_hand_str = "sportheld")

/obj/item/clothing/shoes/skater
	name = "skater shoes"
	desc = "A pair of wide shoes with thick soles.  Designed for skating."
	icon_state = "skatershoe"
	addblends = "skatershoe_a"
	item_state_slots = list(slot_r_hand_str = "skaterheld", slot_l_hand_str = "skaterheld")

/obj/item/clothing/shoes/heels
	name = "high heels"
	desc = "A pair of high-heeled shoes. Fancy!"
	icon_state = "heels"
	addblends = "heels_a"

/obj/item/clothing/shoes/footwraps
	name = "cloth footwraps"
	desc = "A roll of treated canvas used for wrapping claws or paws"
	icon_state = "clothwrap"
	item_state = "clothwrap"
	blocks_footsteps = FALSE
	force = 0
	w_class = ITEMSIZE_SMALL
	species_restricted = null
	drop_sound = 'sound/items/drop/clothing.ogg'
	pickup_sound = 'sound/items/pickup/clothing.ogg'

/obj/item/clothing/shoes/boots/ranger
	var/bootcolor = "white"
	name = "ranger boots"
	desc = "The Rangers special lightweight hybrid magboots-jetboots perfect for EVA. If only these functions were so easy to copy in reality.\
		These ones are just a well-made pair of boots in appropriate colours."
	icon = 'icons/obj/clothing/ranger.dmi'
	icon_state = "ranger_boots"

/obj/item/clothing/shoes/boots/ranger/Initialize(mapload)
	. = ..()
	if(icon_state == "ranger_boots")
		name = "[bootcolor] ranger boots"
		icon_state = "[bootcolor]_ranger_boots"

/obj/item/clothing/shoes/boots/ranger/black
	bootcolor = "black"

/obj/item/clothing/shoes/boots/ranger/pink
	bootcolor = "pink"

/obj/item/clothing/shoes/boots/ranger/green
	bootcolor = "green"

/obj/item/clothing/shoes/boots/ranger/cyan
	bootcolor = "cyan"

/obj/item/clothing/shoes/boots/ranger/orange
	bootcolor = "orange"

/obj/item/clothing/shoes/boots/ranger/yellow
	bootcolor = "yellow"

/*
 * 80s
 */

/obj/item/clothing/shoes/sneakerspurple
	name = "purple sneakers"
	desc = "A stylish, expensive pair of purple sneakers."
	icon_state = "sneakerspurple"
	item_state = "sneakerspurple"

/obj/item/clothing/shoes/sneakersblue
	name = "blue sneakers"
	desc = "A stylish, expensive pair of blue sneakers."
	icon_state = "sneakersblue"
	item_state = "sneakersblue"

/obj/item/clothing/shoes/sneakersred
	name = "red sneakers"
	desc = "A stylish, expensive pair of red sneakers."
	icon_state = "sneakersred"
	item_state = "sneakersred"

/obj/item/clothing/shoes/ballet
	name = "pointe shoes"
	desc = "These shoes feature long lace straps and flattened off toes. Great for the most elegant of dances!"
	icon_state = "ballet"
	item_state = "ballet"


// === merged from miscellaneous_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/shoes/griffin
	name = "griffon boots"
	desc = "A pair of costume boots fashioned after bird talons."
	icon_state = "griffinboots"
	item_state = "griffinboots"

/obj/item/clothing/shoes/bhop
	name = "jump boots"
	desc = "A specialized pair of combat boots with a built-in propulsion system for rapid foward movement."
	icon_state = "jetboots"
	item_state = "jetboots"
	// resistance_flags = FIRE_PROOF
	actions_types = list(/datum/action/item_action/activate_jump_boots)
	permeability_coefficient = 0.05
	var/jumpdistance = 5 //-1 from to see the actual distance, e.g 4 goes over 3 tiles
	var/jumpspeed = 3
	var/recharging_rate = 60 //default 6 seconds between each dash
	var/recharging_time = 0 //time until next dash
	// var/jumping = FALSE //are we mid-jump? We have no throw_at callback, so we have to check user.throwing.
	resistance_flags = FIRE_PROOF

/obj/item/clothing/shoes/bhop/ui_action_click(mob/unused_user, actiontype)
	var/mob/living/user = loc
	if(!isliving(user))
		return

	if(user.throwing)
		return // User is already being thrown

	if(recharging_time > world.time)
		to_chat(user, span_warning("The boot's internal propulsion needs to recharge still!"))
		return

	var/atom/target = get_edge_target_turf(user, user.dir) //gets the user's direction

	playsound(src, 'sound/effects/stealthoff.ogg', 50, 1, 1)
	user.visible_message(span_warning("[user] dashes forward into the air!"))
	user.throw_at(target, jumpdistance, jumpspeed)
	recharging_time = world.time + recharging_rate

/obj/item/clothing/shoes/magboots/adv
	name = "advanced magboots"
	desc = "Advanced magnetic boots for a trained user. They have a lower magnetic force, allowing the user to move more quickly."

	icon_state = "advmag0"
	item_flags = PHORONGUARD
	item_state_slots = list(slot_r_hand_str = "magboots", slot_l_hand_str = "magboots")
	icon_base = "advmag"

/obj/item/clothing/shoes/magboots/adv/set_slowdown()
	if(magpulse)
		slowdown = shoes ? max(SHOES_SLOWDOWN, shoes.slowdown) : SHOES_SLOWDOWN	//So you can't put on magboots to make you walk faster.
	else if(shoes)
		slowdown = shoes.slowdown
	else
		slowdown = SHOES_SLOWDOWN

// Armor Versions Here
/obj/item/clothing/shoes/knight
	name = "knight boots"
	desc = "A pair of olde knight boots."
	icon_state = "knight_boots1"
	item_state = "knight_boots1"
	armor = list(melee = 80, bullet = 50, laser = 10, energy = 0, bomb = 0, bio = 0, rad = 0)

/obj/item/clothing/shoes/knight/black
	name = "knight boots"
	desc = "A pair of olde knight boots."
	icon_state = "knight_boots2"
	item_state = "knight_boots2"

// Costume Versions Here
/obj/item/clothing/shoes/knight_costume
	name = "knight boots"
	desc = "A pair of olde knight boots."
	icon_state = "knight_boots1"
	item_state = "knight_boots1"

/obj/item/clothing/shoes/knight_costume/black
	name = "knight boots"
	desc = "A pair of olde knight boots."
	icon_state = "knight_boots2"
	item_state = "knight_boots2"

//Antediluvian legwraps
/obj/item/clothing/shoes/antediluvian
	name = "antediluvian legwraps"
	desc = "A pair of wraps with gold inlay that cut off around the ankle."
	icon_state = "antediluvian"
	item_state = "antediluvian"

//Alternative flats
/obj/item/clothing/shoes/flats/white/color/alt
	icon_state = "flatsalt"
	item_state = "flatsalt"

/obj/item/clothing/shoes/sandals_elegant
	name = "elegant sandals"
	desc = "A pair of sandals with thin straps. It emphasizes the ankles!"
	icon_state = "sandals_elegant"
	item_state = "sandals_elegant"
	addblends = "sandals_elegant_a"


// === merged from miscellaneous_chomp.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/clothing/shoes/mech_shoes
	name = "mech shoes"
	desc = "Thud thud."
	icon = 'icons/effects/effects.dmi' //This is to make the unit test happy. These are invisible which are... Less than ideal. This should probably be moved to a trait or sound selector, but I digress. Outside scope of this PR.
	icon_state = "nothing" // Horribly illegal and shouldn't be a thing, but whatever.
	armor = list(melee = 30, bullet = 10, laser = 10, energy = 15, bomb = 20, bio = 0, rad = 0) // Same as loadout jackboots.
	siemens_coefficient = 0.7 // Same as loadout jackboots.
	can_hold_knife = 1
	force = 2
	species_restricted = null
	var/list/squeak_sound = list("mechstep"=1)	//Squeak sound list. Necessary so our subtypes can have different sounds loaded into their component

/obj/item/clothing/shoes/mech_shoes/Initialize(mapload)
	.=..()
	LoadComponent(/datum/component/squeak, squeak_sound, 15*step_volume_mod)

/obj/item/clothing/shoes/mech_shoes/light
	name = "light mech shoes"
	desc = "Thud thud, but quieter."
	squeak_sound = list("powerloaderstep"=1)

/obj/item/clothing/shoes/mech_shoes/heavy
	name = "heavy mech shoes"
	desc = "Thud thud, but heavy."
	squeak_sound = list('sound/mob/footstep_large.ogg'=1,'sound/mob/footstep_large2.ogg'=1)
	step_volume_mod = 4

/obj/item/clothing/shoes/mech_shoes/mister_x
	name = "concealed extra large jackboots"
	desc = "Lets hope there's no evil in this residence."
	squeak_sound = list('sound/mob/heavy_boots.ogg'=1)
	step_volume_mod = 5

/obj/item/clothing/shoes/mech_shoes/mister_x/visible
	name = "visible extra large jackboots"
	icon = 'icons/inventory/feet/item.dmi'
	icon_state = "jackboots"

/obj/item/clothing/shoes/clown_shoes
	var/list/squeak_sound = list("clownstep"=1)

/obj/item/clothing/shoes/clown_shoes/Initialize(mapload)
	.=..()
	LoadComponent(/datum/component/squeak, squeak_sound, 20*step_volume_mod)

/obj/item/clothing/shoes/dry_galoshes
	desc = "A pair of purple rubber boots, designed to prevent slipping on wet surfaces while also drying them."
	name = "absorbent galoshes"
	icon = 'icons/inventory/feet/item.dmi'
	icon_state = "galoshes_dry"
	permeability_coefficient = 0.05
	siemens_coefficient = 0
	item_flags = NOSLIP
	slowdown = SHOES_SLOWDOWN+0.5
	species_restricted = null
	drop_sound = 'sound/items/drop/rubber.ogg'
	pickup_sound = 'sound/items/pickup/rubber.ogg'

/obj/item/clothing/shoes/dry_galoshes/Initialize(mapload)
	.=..()
	LoadComponent(/datum/component/dry)
