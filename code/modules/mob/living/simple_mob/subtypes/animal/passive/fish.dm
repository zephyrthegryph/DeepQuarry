// Different types of fish! They are all subtypes of this tho
/datum/category_item/catalogue/fauna/invasive_fish
	name = "Invasive Fauna - Fish"
	desc = "This fish is considered an invasive species according \
	to Sivian wildlife regulations. Removal or relocation is advised."
	value = CATALOGUER_REWARD_TRIVIAL

/mob/living/simple_mob/animal/passive/fish
	name = "fish"
	desc = "Its a fishy.  No touchy fishy."
	icon = 'icons/mob/fish.dmi'
	item_state = "fish"

	catalogue_data = list(/datum/category_item/catalogue/fauna/invasive_fish) // CHOMPEnable

	mob_size = MOB_SMALL
	// So fish are actually underwater.
	plane = TURF_PLANE
	layer = UNDERWATER_LAYER

	organ_names = /datum/decl/mob_organ_names/fish

	holder_type = /obj/item/holder/fish

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/fish
	meat_amount = 3

	var/randomize_location = TRUE

// ALLOW(init/INSTANCE_STATE): rolls where in the water it swims unless the map placed it
/mob/living/simple_mob/animal/passive/fish/Initialize(mapload)
	. = ..()

	if(!default_pixel_x && randomize_location)
		default_pixel_x = rand(-12, 12)

	if(!default_pixel_y && randomize_location)
		default_pixel_y = rand(-6, 10)

// Makes the AI unable to willingly go on land.
/mob/living/simple_mob/animal/passive/fish/IMove(turf/newloc, safety = TRUE)
	if(is_type_in_list(newloc, GLOB.suitable_fish_turf_types))
		return ..() // Procede as normal.
	return MOVEMENT_FAILED // Don't leave the water!


/mob/living/simple_mob/animal/passive/fish/life_breathing_due()
	return TRUE

/// Take damage if we are not in water.
/mob/living/simple_mob/animal/passive/fish/life_breathing(datum/seq_frame/life/F)
	if(istype(src.loc, /obj/item/glass_jar/fish))
		var/obj/item/glass_jar/fish/jar = src.loc
		if(jar.filled)
			return

	var/turf/T = get_turf(src)
	if(T && !is_type_in_list(T, GLOB.suitable_fish_turf_types))
		if(prob(50))
			after(src, 0, TYPE_PROC_REF(/mob/living, say), with = list(pick("Blub", "Glub", "Burble")))
		src.add_oxygen_debt(src.unsuitable_atoms_damage, T)

// Subtypes.
/mob/living/simple_mob/animal/passive/fish/bass
	name = "bass"
	tt_desc = "E Micropterus notius"
	icon_state = "bass-swim"
	icon_living = "bass-swim"
	icon_dead = "bass-dead"

/mob/living/simple_mob/animal/passive/fish/trout
	name = "trout"
	tt_desc = "E Salmo trutta"
	icon_state = "trout-swim"
	icon_living = "trout-swim"
	icon_dead = "trout-dead"

/mob/living/simple_mob/animal/passive/fish/salmon
	name = "salmon"
	tt_desc = "E Oncorhynchus nerka"
	icon_state = "salmon-swim"
	icon_living = "salmon-swim"
	icon_dead = "salmon-dead"

/mob/living/simple_mob/animal/passive/fish/perch
	name = "perch"
	tt_desc = "E Perca flavescens"
	icon_state = "perch-swim"
	icon_living = "perch-swim"
	icon_dead = "perch-dead"

/mob/living/simple_mob/animal/passive/fish/pike
	name = "pike"
	tt_desc = "E Esox aquitanicus"
	icon_state = "pike-swim"
	icon_living = "pike-swim"
	icon_dead = "pike-dead"

/mob/living/simple_mob/animal/passive/fish/koi
	name = "koi"
	tt_desc = "E Cyprinus rubrofuscus"
	icon_state = "koi-swim"
	icon_living = "koi-swim"
	icon_dead = "koi-dead"

/datum/category_item/catalogue/fauna/javelin
	name = "Sivian Fauna - Javelin Shark"
	desc = "Classification: S Cetusan minimalix\
	<br><br>\
	A small breed of fatty shark native to the waters near the Ullran Expanse.\
	The creatures are not known to attack humans or larger animals, possibly \
	due to their size. It is speculated that they are actually scavengers, \
	as they are most commonly found near the gulf floor. \
	<br>\
	The Javelin's reproductive cycle only recurs between three and four \
	Sivian years. \
	<br>\
	These creatures are considered a protected species, and thus require an \
	up-to-date license to be hunted."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/passive/fish/javelin
	name = "javelin"
	tt_desc = "S Cetusan minimalix"
	icon_state = "javelin-swim"
	icon_living = "javelin-swim"
	icon_dead = "javelin-dead"

	catalogue_data = list(/datum/category_item/catalogue/fauna/javelin)

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/fish/sif

/datum/category_item/catalogue/fauna/icebass
	name = "Sivian Fauna - Glitter Bass"
	desc = "Classification: X Micropterus notius crotux\
	<br><br>\
	Initially a genetically engineered hybrid of the common Earth bass and \
	the Sivian Rock-Fish. These were designed to deal with the invasive \
	fish species, however to their creators' dismay, they instead \
	began to form their own passive niche. \
	<br>\
	Due to the brilliant reflective scales earning them their name, the \
	animals pose a specific issue for Sivian animals relying on \
	bioluminesence to aid in their hunt. \
	<br>\
	Despite their beauty, they are considered an invasive species."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/passive/fish/icebass
	name = "glitter bass"
	tt_desc = "X Micropterus notius crotux"
	icon_state = "sifbass-swim"
	icon_living = "sifbass-swim"
	icon_dead = "sifbass-dead"

	catalogue_data = list(/datum/category_item/catalogue/fauna/icebass)

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/fish/sif

	var/max_red = 150
	var/min_red = 50

	var/max_blue = 255
	var/min_blue = 50

	var/max_green = 150
	var/min_green = 50

	var/dorsal_color = "#FFFFFF"
	var/belly_color = "#FFFFFF"


// ALLOW(init/INSTANCE_STATE): rolls its dorsal and belly colours
/mob/living/simple_mob/animal/passive/fish/icebass/Initialize(mapload)
	. = ..()
	set_dorsal_color(rgb(rand(min_red,max_red), rand(min_green,max_green), rand(min_blue,max_blue)))
	set_belly_color(rgb(rand(min_red,max_red), rand(min_green,max_green), rand(min_blue,max_blue)))

TRACKED(/mob/living/simple_mob/animal/passive/fish/icebass, dorsal_color)
TRACKED(/mob/living/simple_mob/animal/passive/fish/icebass, belly_color)

/// The tinted dorsal and belly masks over the fish.
/mob/living/simple_mob/animal/passive/fish/icebass/draw(datum/look/look)
	..()
	var/state = look.state_so_far(src)
	look.overlay(look_overlay_image(icon, "[state]_mask-body", color = dorsal_color))
	look.overlay(look_overlay_image(icon, "[state]_mask-belly", color = belly_color))

/datum/category_item/catalogue/fauna/rockfish
	name = "Sivian Fauna - Rock Puffer"
	desc = "Classification: S Tetraodontidae scopulix\
	<br><br>\
	A species strangely resembling the puffer-fish of Earth. These \
	creatures do not use toxic spines to protect themselves, instead \
	utilizing an incredibly durable exoskeleton that is molded by the \
	expansion of its ventral fluid bladders. \
	<br>\
	Rock Puffers or 'Rock-fish' are often host to smaller creatures which \
	maneuver their way into the gap between the fish's body and shell. \
	<br>\
	The species is also capable of pulling its vibrantly colored head into \
	the safer confines of its shell, the action being utilized in their \
	attempts to find a mate."
	value = CATALOGUER_REWARD_EASY

/mob/living/simple_mob/animal/passive/fish/rockfish
	name = "rock-fish"
	tt_desc = "S Tetraodontidae scopulix"
	icon_state = "rockfish-swim"
	icon_living = "rockfish-swim"
	icon_dead = "rockfish-dead"

	catalogue_data = list(/datum/category_item/catalogue/fauna/rockfish)

	armor_spec = "melee=90;bullet=50;laser=-15;energy=30;bomb=30;bio=100;rad=100"

	var/max_red = 255
	var/min_red = 50

	var/max_blue = 255
	var/min_blue = 50

	var/max_green = 255
	var/min_green = 50

	var/head_color = "#FFFFFF"

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/fish/sif

// ALLOW(init/INSTANCE_STATE): rolls its head colour
/mob/living/simple_mob/animal/passive/fish/rockfish/Initialize(mapload)
	. = ..()
	set_head_color(rgb(rand(min_red,max_red), rand(min_green,max_green), rand(min_blue,max_blue)))

TRACKED(/mob/living/simple_mob/animal/passive/fish/rockfish, head_color)

/// The tinted head mask over the fish.
/mob/living/simple_mob/animal/passive/fish/rockfish/draw(datum/look/look)
	..()
	look.overlay(look_overlay_image(icon, "[look.state_so_far(src)]_mask", color = head_color))

/datum/category_item/catalogue/fauna/solarfish
	name = "Sivian Fauna - Solar Fin"
	desc = "Classification: S Exocoetidae solarin\
	<br><br>\
	An incredibly rare species of Sivian fish.\
	The solar-fin missile fish is a specialized omnivore capable of \
	catching insects or small birds venturing too close to the water's \
	surface. \
	<br>\
	The glimmering fins of the solar-fin are actually biofluorescent, \
	'charged' by the creature basking at the surface of the water, most \
	commonly by the edge of an ice-shelf, as a rapid means of cover. \
	<br>\
	These creatures are considered a protected species, and thus require an \
	up-to-date license to be hunted."
	value = CATALOGUER_REWARD_HARD

/mob/living/simple_mob/animal/passive/fish/solarfish
	name = "sun-fin"
	tt_desc = "S Exocoetidae solarin"
	icon_state = "solarfin-swim"
	icon_living = "solarfin-swim"
	icon_dead = "solarfin-dead"

	catalogue_data = list(/datum/category_item/catalogue/fauna/solarfish)

	has_eye_glow = TRUE

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/fish/sif

/datum/category_item/catalogue/fauna/murkin
	name = "Sivian Fauna - Murkfish"
	desc = "Classification: S Perca lutux\
	<br><br>\
	A small, Sivian fish most known for its bland-ness.\
	<br>\
	The species is incredibly close in appearance to the Earth \
	perch, aside from its incredibly tall dorsal fin. The animals use \
	the fin to assess the wind direction while near the surface. \
	<br>\
	The murkfish earns its name from the fact its dense meat tastes like mud \
	thanks to a specially formed protein, most likely an adaptation to \
	protect the species from predation."
	value = CATALOGUER_REWARD_TRIVIAL

/mob/living/simple_mob/animal/passive/fish/murkin
	name = "murkin"
	tt_desc = "S Perca lutux"

	icon_state = "murkin-swim"
	icon_living = "murkin-swim"
	icon_dead = "murkin-dead"

	catalogue_data = list(/datum/category_item/catalogue/fauna/murkin)

	meat_type = /obj/item/reagent_containers/food/snacks/carpmeat/sif/murkfish

/datum/decl/mob_organ_names/fish
TYPE_TABLE(/datum/decl/mob_organ_names/fish, mob_organ_hit_zones, list("head", "body", "dorsal fin", "left pectoral fin", "right pectoral fin", "tail fin"))


// === merged from fish_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/mob/living/simple_mob/animal/passive/fish/koi/poisonous
	desc = "A genetic marvel, combining the docility and aesthetics of the koi with some of the resiliency and cunning of the noble space carp."
	endurance = 50
	meat_amount = 0

CAPABILITIES(/mob/living/simple_mob/animal/passive/fish/koi/poisonous)
	reagents(60, starts = list(REAGENT_ID_TOXIN = 45, REAGENT_ID_IMPEDREZENE = 15))
	op("koi_poisonous_hand_help", hand(), stance(I_HELP), label("Pet"), then(PROC_REF(koi_poisonous_interaction_hand_help)))
	op("koi_poisonous_hand_hurt", hand(), stance(I_HURT), label("Hit"), then(PROC_REF(koi_poisonous_interaction_hand_hurt)))
	op("koi_poisonous_hand_disarm", hand(), stance(I_DISARM), label("Shove"), then(PROC_REF(koi_poisonous_interaction_hand_disarm)))
	op("koi_poisonous_hand_grab", hand(), stance(I_GRAB), label("Grab"), then(PROC_REF(koi_poisonous_interaction_hand_grab)))

/// The help-stance input of koi_poisonous_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_poisonous_interaction_hand_help(datum/act/op/A)
	return koi_poisonous_interaction_hand(A, I_HELP)

/// The hurt-stance input of koi_poisonous_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_poisonous_interaction_hand_hurt(datum/act/op/A)
	return koi_poisonous_interaction_hand(A, I_HURT)

/// The disarm-stance input of koi_poisonous_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_poisonous_interaction_hand_disarm(datum/act/op/A)
	return koi_poisonous_interaction_hand(A, I_DISARM)

/// The grab-stance input of koi_poisonous_interaction_hand: the shared handler with its stance.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_poisonous_interaction_hand_grab(datum/act/op/A)
	return koi_poisonous_interaction_hand(A, I_GRAB)

/mob/living/simple_mob/animal/passive/fish/koi/poisonous/life_type_post_due()
	return TRUE

/mob/living/simple_mob/animal/passive/fish/koi/poisonous/life_type_post(datum/seq_frame/life/F)
	..()
	if(isbelly(src.loc) && prob(10))
		var/obj/belly/B = src.loc
		src.sting(B.owner)

/// Flops away from M, up to `steps` tiles, 0.3 s apart.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_flee(mob/living/M, steps)
	if(!M)
		return
	var/turf/T = get_step_away(src, M)
	if(!T || !is_type_in_list(T, GLOB.suitable_fish_turf_types))
		return
	Move(T)
	if(steps > 1)
		after(src, 0.3 SECONDS, PROC_REF(koi_flee), with = list(M, steps - 1))

/// Old attack_hand: the normal touch, then the koi flails and stings.
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/koi_poisonous_interaction_hand(datum/act/op/A, stance)
	var/mob/living/L = A.actor
	. = OP_OK
	unarmed_touch(L, stance)
	if(isliving(L) && Adjacent(L))
		var/mob/living/M = L
		act_message(src, M, null, MSG_OTHERS(span_warning("%U%[is_dead()?"'s corpse":""] flails at %T%!")))
		SpinAnimation(7,1)
		if(prob(75))
			if(sting(M))
				to_chat(M, span_warning("You feel a tiny prick."))
		if(is_dead())
			return
		koi_flee(M, 3)
/*
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/react_to_attack(atom/A)
	if(isliving(A) && Adjacent(A))
		var/mob/living/M = A
		act_message(src, M, null, MSG_OTHERS(span_warning("%U%[is_dead()?"'s corpse":""] flails at %T%!")))
		SpinAnimation(7,1)
		if(prob(75))
			if(sting(M))
				to_chat(M, span_warning("You feel a tiny prick."))
		if(is_dead())
			return
		koi_flee(M, 3)
*/
/mob/living/simple_mob/animal/passive/fish/koi/poisonous/proc/sting(mob/living/M)
	if(!M.reagents)
		return 0
	M.reagents.add_reagent(REAGENT_ID_TOXIN, 2)
	M.reagents.add_reagent(REAGENT_ID_IMPEDREZENE, 1)
	return 1

/mob/living/simple_mob/animal/passive/fish/measelshark
	name = "Measel Shark"
	tt_desc = "Spot Pistris"
	desc = "An evil measel shark that refuses to get vaccinated, causing other fish to get fish measels."
	icon = 'icons/mob/shark.dmi'
	icon_state = "measelshark"
	icon_living = "measelshark"
	icon_dead = "measelshark-dead"
	meat_amount = 8 //Big fish, tons of meat. Great for feasts.
	meat_type = /obj/item/reagent_containers/food/snacks/sliceable/sharkchunk
	vore_active = 1
	vore_bump_chance = 100
	vore_default_mode = DM_HOLD //docile shark
	vore_capacity = 5
	pixel_x = -50

