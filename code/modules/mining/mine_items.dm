/******************************Lantern*******************************/

/obj/item/flashlight/lantern
	name = "lantern"
	icon_state = "lantern"
	desc = "A mining lantern."
	light_range = 6			// luminosity when on
	light_color = "FF9933" // A slight yellow/orange color.

/*****************************Pickaxe********************************/

/obj/item/pickaxe
	name = "pickaxe"
	desc = "A miner's best friend."
	icon = 'icons/obj/items.dmi'
	slot_flags = SLOT_BELT
	force = 15.0
	throwforce = 4.0
	icon_state = "pickaxe"
	item_state = "pickaxe"
	w_class = ITEMSIZE_LARGE
	MATERIAL_BULK(MAT_STEEL, 2500)
	var/digspeed = 36 //moving the delay to an item var so R&D can make improved picks. --NEO
	var/sand_dig = FALSE // does this thing dig sand?
	attack_verb = list("hit", "pierced", "sliced", "attacked")
	var/drill_sound = SFX_PICKAXE
	var/drill_verb = "picking"
	sharp = TRUE
	injury_kind = INJURY_PIERCE

	var/excavation_amount = 200
	var/destroy_artefacts = FALSE // some mining tools will destroy artefacts completely while avoiding side-effects.
	var/borg_flags = COUNTS_AS_ROBOTIC_MELEE //The ONLY reason this gets this here is because pickaxes are SO hardcoded that it's easier to add it here than everywhere else. Please do not attach this to everything that you desire. Only VERY SPECIFIC THINGS under CERTAIN CIRCUMSTANCES, PLEASE. 99% of things can be added to code\modules\projectiles\guns\energy\cyborg.dm

/obj/item/pickaxe/silver
	name = "silver pickaxe"
	icon_state = "spickaxe"
	item_state = "spickaxe"
	digspeed = 27
	desc = "This makes no metallurgic sense."

/obj/item/pickaxe/gold
	name = "golden pickaxe"
	icon_state = "gpickaxe"
	item_state = "gpickaxe"
	digspeed = 18
	desc = "This makes no metallurgic sense."
	drill_verb = "picking"

/obj/item/pickaxe/diamond
	name = "diamond pickaxe"
	icon_state = "dpickaxe"
	item_state = "dpickaxe"
	digspeed = 9
	desc = "A pickaxe with a diamond pick head."
	drill_verb = "picking"

/*****************************Drill********************************/

/obj/item/pickaxe/drill
	name = "mining drill" // Can dig sand as well!
	icon_state = "drill"
	item_state = "jackhammer"
	digspeed = 30 //Only slighty better than a pickaxe
	sand_dig = TRUE
	MATERIAL_BULK(MAT_STEEL, 3750)
	desc = "The most basic of mining drills, for short excavations and small mineral extractions."
	drill_verb = "drilling"

MATERIAL_MIX(/obj/item/pickaxe/advdrill, list(MAT_STEEL = 4000, MAT_PLASTEEL = 2500))
/obj/item/pickaxe/advdrill
	name = "advanced mining drill" // Can dig sand as well!
	icon_state = "advdrill"
	item_state = "jackhammer"
	digspeed = 27
	sand_dig = TRUE
	desc = "Yours is the drill that will pierce through the rock walls."
	drill_verb = "drilling"

MATERIAL_MIX(/obj/item/pickaxe/diamonddrill, list(MAT_STEEL = 4500, MAT_PLASTEEL = 3000, MAT_DIAMONDS = 1000))
/obj/item/pickaxe/diamonddrill //When people ask about the badass leader of the mining tools, they are talking about ME!
	name = "diamond mining drill"
	icon_state = "diamonddrill"
	item_state = "jackhammer"
	digspeed = 4 //Digs through walls, girders, and can dig up sand
	sand_dig = TRUE
	desc = "Yours is the drill that will pierce the heavens!"
	drill_verb = "drilling"

/obj/item/pickaxe/jackhammer
	name = "sonic jackhammer"
	icon_state = "jackhammer"
	item_state = "jackhammer"
	digspeed = 18 //faster than drill, but cannot dig
	desc = "Cracks rocks with sonic blasts, perfect for killing cave lizards."
	drill_verb = "hammering"
	destroy_artefacts = TRUE

/obj/item/pickaxe/borgdrill
	name = "jackhammer"
	icon_state = "borg_pick"
	item_state = "jackhammer"
	digspeed = 13
	sand_dig = TRUE
	desc = "Cracks rocks with a hardened pneumatic bit."
	drill_verb = "hammering"
	destroy_artefacts = TRUE

MATERIAL_MIX(/obj/item/pickaxe/plasmacutter, list(MAT_STEEL = 3000, MAT_PLASTEEL = 1500, MAT_DIAMONDS = 500, MAT_PHORON = 500))
/obj/item/pickaxe/plasmacutter
	name = "plasma cutter"
	desc = "A rock cutter that uses bursts of hot plasma. You could use it to cut limbs off of xenos! Or, you know, mine stuff."
	icon_state = "plasmacutter"
	item_state = "plasmacutter"
	w_class = ITEMSIZE_NORMAL //it is smaller than the pickaxe
	digspeed = 18 //Can slice though normal walls, all girders, or be used in reinforced wall deconstruction/light thermite on fire
	drill_verb = "cutting"
	drill_sound = SFX_ITEMS_WELDER
	sharp = TRUE
	edge = TRUE
	injury_kind = INJURY_BURN

/obj/item/pickaxe/plasmacutter/borg
	name = "mounted plasma cutter"
	icon_state = "pcutter_borg"

/*****************************Shovel********************************/

/obj/item/shovel
	name = "shovel"
	desc = "A large tool for digging and moving dirt. Alt click to switch modes."
	icon = 'icons/obj/items.dmi'
	icon_state = "shovel"
	item_state = "shovel"
	slot_flags = SLOT_BELT
	force = 8.0
	throwforce = 4.0
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_STEEL, 50)
	attack_verb = list("bashed", "bludgeoned", "thrashed", "whacked")
	sharp = FALSE
	edge = TRUE
	var/digspeed = 40
	var/grave_mode = FALSE

TRACKED(/obj/item/shovel, grave_mode)

CAPABILITIES(/obj/item/shovel)
	op("toggle_grave_mode", hand(), gesture(GESTURE_ALT), label("Toggle digging mode"),
		needs(req_adjacent()), then(PROC_REF(grave_mode_toggled)))

/obj/item/shovel/proc/grave_mode_toggled(datum/act/op/A)
	set_grave_mode(!grave_mode)
	to_chat(A.actor, span_notice("You'll now dig [grave_mode ? "out graves" : "for loot"]."))
	return OP_OK

/obj/item/shovel/wood
	icon_state = "whiteshovel"
	item_state = "whiteshovel"
	var/tmp/datum/material/material_static
	resistance_flags = FLAMMABLE

CAPABILITIES(/obj/item/shovel/wood)
	param(nameof(shovel_material), pos = 1, apply = PROC_REF(carve))

/// The material a shovel is carved from (its constructor param); a bare one (the survival recipe, a map, a test) is plain wood.
/obj/item/shovel/wood/var/shovel_material = MAT_WOOD

/// Applied at init from its constructor param (param(apply =), code/engine/lifeforms/params.dm).
/obj/item/shovel/wood/proc/carve(_mat)
	material_static = get_material_by_name(_mat || MAT_WOOD)
	if(!istype(material(), /datum/material))
		material_static = null
	else
		name = "[material().display_name] shovel"
		set_bulk_material(material().name, 50)
		changed(src)

/obj/item/shovel/wood/draw(datum/look/look)
	..()
	look.color = material() ? material().icon_colour : initial(color)
	if(material())
		look.alpha = min(max(255 * material().opacity, 80), 255)

/obj/item/shovel/spade
	name = "spade"
	desc = "A small tool for digging and moving dirt."
	icon_state = "spade"
	item_state = "spade"
	force = 5.0
	throwforce = 7.0
	w_class = ITEMSIZE_SMALL

/obj/item/shovel/wood
	name = "wooden shovel"
	desc = "An improvised tool for digging and moving dirt."
	icon = 'icons/obj/items.dmi'
	icon_state = "woodshovel"
	slot_flags = SLOT_BELT
	item_state = "woodshovel"
	w_class = ITEMSIZE_NORMAL
	MATERIAL_BULK(MAT_WOOD, 50)
	sharp = 0
	edge = 1

/*****************************Icepick********************************/

//Ice pick, mountain axe, or ice axe.YW Creation.
/obj/item/ice_pick
	name = "ice axe"
	desc = "A sharp tool for climbers and hikers to break up ice and keep themselves from slipping on a steep slope."
	icon_state = "icepick"
	item_state = "icepick"
	MATERIAL_BULK(MAT_STEEL, 12000) //Same as a knife
	force = 15 //increasing force for icepick/axe, cause it's a freaking iceaxe.
	throwforce = 0

/*****************************Flags********************************/

/obj/item/stack/flag
	name = "flags"
	desc = "Some colourful flags."
	singular_name = "flag"
	amount = 10
	max_amount = 10
	icon = 'icons/obj/mining.dmi'
	var/upright = 0
	var/base_state

CAPABILITIES(/obj/item/stack/flag)
	without("ui_open")
	op("flag_interaction_item", item(/obj/item), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(flag_interaction_item)))
	op("flag_hand", hand(), ungated(), priority(OP_PRIORITY_DEFAULT - 1), label("Knock down"), then(PROC_REF(flag_hand)))
	op("flag_self", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Plant"), needs(req(PROC_REF(can_plant_holds), because = PROC_REF(can_plant_refusal))), then(PROC_REF(flag_self)))

/obj/item/stack/flag/Initialize(mapload)
	. = ..()
	base_state = icon_state

/obj/item/stack/flag/blue
	name = "blue flags"
	singular_name = "blue flag"
	icon_state = "blueflag"

/obj/item/stack/flag/red
	name = "red flags"
	singular_name = "red flag"
	icon_state = "redflag"

/obj/item/stack/flag/yellow
	name = "yellow flags"
	singular_name = "yellow flag"
	icon_state = "yellowflag"

/obj/item/stack/flag/green
	name = "green flags"
	singular_name = "green flag"
	icon_state = "greenflag"

/// Requirement (was REQ_* can_plant): the legacy check answers TRUE to pass.
/obj/item/stack/flag/proc/can_plant_holds(datum/act/op/A)
	var/answer = can_plant(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_plant_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/stack/flag/proc/can_plant_refusal(datum/act/op/A)
	var/answer = can_plant(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/// Old attackby.
/obj/item/stack/flag/proc/flag_interaction_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/W = A.held
	if(upright && istype(W,src.type))
		src.attack_hand(user)
	else
		return OP_DECLINE
	return OP_PASS

/// Old attack_hand: knock an upright flag down; otherwise fall through to the stack's split and pickup.
/obj/item/stack/flag/proc/flag_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!upright)
		return OP_DECLINE
	upright = 0
	icon_state = base_state
	set_anchored(FALSE)
	act_message(user, src, others = span_infoplain(span_bold("%U%") + " knocks down %T%."))
	return OP_OK

/// Requirement: TRUE, or why the flag can't be planted here.
/obj/item/stack/flag/proc/can_plant(mob/user, atom/target, obj/item/held)
	var/turf/T = get_turf(src)
	if(!T || !ismineralturf(T))
		return "the flag won't stand up in this terrain"
	var/obj/item/stack/flag/F = locate_within(T, /obj/item/stack/flag)
	if(F && F.upright)
		return "there is already a flag here"
	return TRUE

/// Old attack_self: plant a flag.
/obj/item/stack/flag/proc/flag_self(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = get_turf(src)
	var/obj/item/stack/flag/newflag = new src.type(T)
	newflag.set_amount(1, TRUE)
	newflag.upright = 1
	newflag.set_anchored(TRUE)
	newflag.name = newflag.singular_name
	newflag.icon_state = "[newflag.base_state]_open"
	act_message(user, newflag, others = span_infoplain(span_bold("%U%") + " plants %T% firmly in the ground."))
	src.use(1)

/*****************************Trailblazer item********************************/

/obj/item/stack/lightpole
	name = "Trailblazers"
	desc = "Some colourful trail lights."
	singular_name = "trailblazer"
	amount = 10
	max_amount = 10
	icon = 'icons/obj/mining.dmi'
	var/blazer_type = /obj/structure/trailblazer

CAPABILITIES(/obj/item/stack/lightpole)
	without("ui_open")
	op("lightpole_self", in_hand(), label("Plant"), needs(req(PROC_REF(can_plant_holds), because = PROC_REF(can_plant_refusal))), then(PROC_REF(lightpole_self)))

/obj/item/stack/lightpole/red
	name = "red flags"
	singular_name = "red trail blazer"
	icon_state = "redtrail_light"
	blazer_type = /obj/structure/trailblazer/red

/obj/item/stack/lightpole/blue
	name = "blue trail blazers"
	singular_name = "blue trail blazer"
	icon_state = "bluetrail_light"
	blazer_type = /obj/structure/trailblazer/blue

/obj/item/stack/lightpole/yellow
	name = "red flags"
	singular_name = "red trail blazer"
	icon_state = "yellowtrail_light"
	blazer_type = /obj/structure/trailblazer/yellow

/// Requirement: TRUE, or why the light can't be planted where the user stands.
/obj/item/stack/lightpole/proc/can_plant(mob/user, atom/target, obj/item/held)
	var/turf/T = get_turf(user)
	if(!T || (!istype(T,/turf/simulated/mineral) && !istype(T,/turf/simulated/floor/outdoors) && !istype(T,/turf/simulated/floor/snow) && !istype(T,/turf/snow)))
		return "the light won't stand up in this terrain"
	if(locate_within(get_turf(src), /obj/structure/trailblazer))
		return "there is already a light here"
	return TRUE

/// Old attack_self: plant a trail light.
/// Requirement (was REQ_* can_plant): the legacy check answers TRUE to pass.
/obj/item/stack/lightpole/proc/can_plant_holds(datum/act/op/A)
	var/answer = can_plant(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_plant_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/stack/lightpole/proc/can_plant_refusal(datum/act/op/A)
	var/answer = can_plant(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/item/stack/lightpole/proc/lightpole_self(datum/act/op/A)
	var/mob/user = A.actor
	var/turf/T = get_turf(user)
	task_timed(user, 8 SECONDS, src, src, PROC_REF(plant_done), list(user, T))
	return TRUE

/obj/item/stack/lightpole/proc/plant_done(mob/user, turf/T)
	if(locate_within(T, /obj/structure/trailblazer))
		return
	var/obj/structure/trailblazer/newlightpole = new blazer_type(T)
	act_message(user, newlightpole, others = "%U% plants %T% firmly in the ground.")
	use(1)

/*****************************Trailblazer structure********************************/

/datum/category_item/catalogue/material/trail_blazer
	name = "Ice Colony Equipment - Trailblazer"
	desc = "This is a glowing stick embedded in the ground with a light on top, commonly used in snowy installations and in tundra conditions."
	value = CATALOGUER_REWARD_EASY

/obj/structure/trailblazer
	name = "trail blazer"
	desc = "A glowing stick- light."
	icon = 'icons/obj/mining.dmi'
	icon_state = "redtrail_light_on"
	density = TRUE
	anchored = TRUE
	var/stack_type = /obj/item/stack/lightpole/red
	catalogue_data = list(/datum/category_item/catalogue/material/trail_blazer)

CAPABILITIES(/obj/structure/trailblazer)
	climb()
	op("hand", hand(), ungated(), label("Use"), then(PROC_REF(interaction_hand)))

/obj/structure/trailblazer/Initialize(mapload)
	. = ..()
	set_color()

/obj/structure/trailblazer/proc/set_color()
	icon_state = "redtrail_light_on"
	set_light(2, 2, "#FF0000")

/obj/structure/trailblazer/proc/knock_down_done(mob/user)
	act_message(user, src, others = "%U% knocks down %T%.")
	replace_with(src, stack_type, 1)

/// Old attack_hand.
/obj/structure/trailblazer/proc/interaction_hand(datum/act/op/A)
	var/mob/user = A.actor
	if(!istext(task_timed(user, 8 SECONDS, src, src, PROC_REF(knock_down_done), list(user))))
		return TRUE
	return TRUE

/obj/structure/trailblazer/red
	name = "trail blazer"
	desc = "A glowing stick- light.This one is glowing red."
	icon_state = "redtrail_light_on"
	stack_type = /obj/item/stack/lightpole/red

/obj/structure/trailblazer/blue
	name = "trail blazer"
	desc = "A glowing stick- light. This one is glowing blue."
	icon_state = "bluetrail_light_on"
	stack_type = /obj/item/stack/lightpole/blue

/obj/structure/trailblazer/blue/set_color()
	icon_state = "bluetrail_light_on"
	set_light(2, 2, "#C4FFFF")

/obj/structure/trailblazer/yellow
	name = "trail blazer"
	desc = "A glowing stick- light. This one is glowing yellow."
	icon_state = "yellowtrail_light_on"
	stack_type = /obj/item/stack/lightpole/yellow

/obj/structure/trailblazer/yellow/set_color()
	icon_state = "yellowtrail_light_on"
	set_light(2, 2, "#ffea00")

/// Accessor for a shared definition.
/obj/item/shovel/wood/proc/material() as /datum/material
	return material_static
