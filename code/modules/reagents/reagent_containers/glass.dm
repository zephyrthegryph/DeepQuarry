////////////////////////////////////////////////////////////////////////////////
/// (Mixing)Glass.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/glass
	name = " "
	var/base_name = " "
	desc = " "
	var/base_desc = " "
	icon = 'icons/obj/chemical.dmi'
	icon_state = "null"
	item_state = "null"
	amount_per_transfer_from_this = 10
	min_transfer_amount = 1
	max_transfer_amount = 60
	volume = 60
	w_class = ITEMSIZE_SMALL
	flags = NOCONDUCT
	unacidable = TRUE //glass doesn't dissolve in acid
	drop_sound = SFX_ITEMS_DROP_BOTTLE
	pickup_sound = SFX_ITEMS_PICKUP_BOTTLE
	resistance_flags = ACID_PROOF

	var/label_text = ""
	/// Reagents to fill the container with at the start, formatted as "reagentID" = quantity
	var/list/prefill = null

TRACKED(/obj/item/reagent_containers/glass, label_text)

// What anything made of glass takes from a hand: a pen labels it, a small thing is dipped into it (in a hostile, disarm or grab stance), and a hot
// thing tests the blood in it.
CAPABILITY_DEF(glass_handling, CAP_GLASS_HANDLING, key = NONE)

/datum/capability/def/glass_handling/entries()
	return list(
		op("label", inputs(item(/obj/item/pen), item(/obj/item/flashlight/pen)), label("Label it"), \
			asks(/datum/prompt/text, fields = list("question" = "Enter a label for it:")), then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, label_applied))),
		op("dip", item(/obj/item), stance(I_DISARM, I_GRAB, I_HURT), when(TYPE_PROC_REF(/obj/item/reagent_containers/glass, dip_fits)), label("Dip into it"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, dip_applied))),
		op("blood_test", item(/obj/item), priority(OP_PRIORITY_TAKE_OUT), when(req(TYPE_PROC_REF(/obj/item/reagent_containers, blood_test_fits))), label("Test the blood"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers, blood_tested))))

// A glass container is a reagent_container() whose settings are the vars of the type (volume, the amount a transfer moves and the range a person may
// set it in, prefill); everything under /glass is one but the rag, which has its own rules. It starts with its lid off. It is poured into an open holder of liquid (not onto what it is put on: a table, a machine that
// takes it), drawn from a closed tank, splashed over things in a hostile stance, drunk from yourself and fed to others in three seconds. A closed one milks the venom of a creature.
CAPABILITY_DEF(glass_container, CAP_GLASS_CONTAINER, key = NONE)

/datum/capability/def/glass_container/entries()
	return list(
		reagent_container( \
			volume = nameof(/obj/item/reagent_containers/glass::volume), \
			lid = TRUE, \
			starts_open = TRUE, \
			transfer_default = nameof(/obj/item/reagent_containers/glass::amount_per_transfer_from_this), \
			transfer_min = nameof(/obj/item/reagent_containers/glass::min_transfer_amount), \
			transfer_max = nameof(/obj/item/reagent_containers/glass::max_transfer_amount), \
			starts = nameof(/obj/item/reagent_containers/glass::prefill), \
			taps = list(/obj/structure/reagent_dispensers), \
			rests_on = REAGENT_CONTAINER_CAN_BE_PLACED_INTO_DEFAULT, \
			feed = TRUE, \
			examine_range = 2),
		op("milk", at_target(/mob/living), answers(INTENT_ATTACK, INTENT_USE), priority(OP_PRIORITY_ATTACK), when(cond_not(REAGENT_CONTAINER_LID_OPEN)), label("Milk venom"), \
			then(TYPE_PROC_REF(/obj/item/reagent_containers/glass, venom_milked))))

CAPABILITIES(/obj/item/reagent_containers/glass)
	glass_handling()
	glass_container()

MSG_DEF_SELF(glass/label_too_long, "The label can be at most 50 characters long.")
MSG_DEF_SELF(glass/no_venom, "That creature has no venom you can express. Open the container to drink from it.")
MSG_DEF_SELF(glass/venom_recently, "That creature had its venom expressed too recently, try again later.")

// ALLOW(init/INSTANCE_STATE): remembers the name and description it was given, a map or loadout edit, for its label
/obj/item/reagent_containers/glass/Initialize(mapload)
	. = ..()
	base_name = name
	base_desc = desc

// ---- the label ----

/// The pen wrote `value`: the label (up to 50 letters; the name shows 20), or none when it is empty.
/obj/item/reagent_containers/glass/proc/label_applied(datum/act/op/A)
	var/datum/prompt/R = A.answer
	var/mob/user = A.actor
	var/tmp_label = sanitizeSafe("[R?.value]", MAX_NAME_LEN) || ""
	if(length(tmp_label) > 50)
		A.reason = /datum/msg/glass/label_too_long
		return OP_REFUSED
	if(length(tmp_label) > 10)
		balloon_alert(user, "label set")
	else
		balloon_alert(user, "label set to \"[tmp_label]\"")
	set_label_text(tmp_label)
	update_name_label()
	return OP_OK

/obj/item/reagent_containers/glass/proc/update_name_label()
	if(label_text == "")
		name = base_name
	else if(length(label_text) > 20)
		var/short_label_text = copytext(label_text, 1, 21)
		name = "[base_name] ([short_label_text]...)"
	else
		name = "[base_name] ([label_text])"
	desc = "[base_desc] It is labeled \"[label_text]\"."

// ---- dipping and testing ----

/// The held thing is small enough to dip, the container is open, and the thing is not a container of its own (which pours instead).
/obj/item/reagent_containers/glass/proc/dip_fits(datum/act/op/A)
	var/obj/item/held = A.held
	return !isnull(held) && held.w_class <= w_class && is_open_container() && !istype(held, /obj/item/reagent_containers)

/obj/item/reagent_containers/glass/proc/dip_applied(datum/act/op/A)
	var/obj/item/held = A.held
	balloon_alert(A.actor, "[held] dipped into \the [src].")
	reagents.touch_obj(held, reagents.total_volume, A.actor)
	return OP_OK

// ---- venom ----

/// What a creature's venom is and how much of it comes out of one milking: a trait's chosen injection, or a spider's poison.
/obj/item/reagent_containers/glass/proc/venom_milked(datum/act/op/A)
	var/mob/living/target = A.target
	var/mob/living/user = A.actor
	var/reagent
	var/amount
	if(target.trait_injection_selected)
		reagent = target.trait_injection_selected
		amount = target.trait_injection_amount
	else if(istype(target, /mob/living/simple_mob/animal/giant_spider))
		var/mob/living/simple_mob/animal/giant_spider/spider = target
		reagent = spider.poison_type
		amount = spider.poison_per_bite
	if(!reagent || !amount)
		A.reason = /datum/msg/glass/no_venom
		return OP_REFUSED
	if(!COOLDOWN_FINISHED(target, venom_milking_cd))
		act_message(user, target, MSG_SELF(span_warning("%T% had their venom expressed too recently, try again later.")), \
			MSG_OTHERS(span_warning("%U% attempts to express venom from %T%, but nothing happens.")))
		A.reason = /datum/msg/glass/venom_recently
		return OP_REFUSED
	COOLDOWN_START(target, venom_milking_cd, 30 SECONDS)
	act_message(user, target, others = span_notice("%U% expresses venom from %T%."))
	reagents.add_reagent(reagent, amount)
	return OP_OK

/// Venom was expressed from this mob recently (a COOLDOWN; venom_milked()).
/mob/living/var/tmp/venom_milking_cd = 0

/// The look of a glass container: the filling (by how full it is, in the colour of what is in it), the lid while it is on, and a label.
/obj/item/reagent_containers/glass/proc/draw_glass(datum/look/look, base, filled, labelled)
	var/datum/reagents/R = reagents
	look.watch(R) // its level and colour are tracked on the holder: the filling follows them
	if(filled && R?.total_volume)
		var/image/filling = image('icons/obj/reagentfillings.dmi', src, "[icon_state]10")
		var/percent = volume ? round((R.total_volume / volume) * 100) : 0
		switch(percent)
			if(0.1 to 20)	filling.icon_state = "[icon_state]-10"
			if(20 to 40) 	filling.icon_state = "[icon_state]-20"
			if(40 to 60)	filling.icon_state = "[icon_state]-40"
			if(60 to 80)	filling.icon_state = "[icon_state]-60"
			if(80 to 100)	filling.icon_state = "[icon_state]-80"
			if(100 to INFINITY)	filling.icon_state = "[icon_state]-100"
		filling.color = R.tint
		look.overlay(filling)
	if(!is_open_container())
		look.overlay("lid_[base]")
	if(labelled && label_text)
		look.overlay("label_[base]")

/obj/item/reagent_containers/glass/beaker
	name = "beaker"
	desc = "A beaker."
	icon = 'icons/obj/chemical.dmi'
	icon_state = "beaker"
	item_state = "beaker"
	center_of_mass_x = 15
	center_of_mass_y = 11
	material_template = /datum/material_template/container
	material_total = 500
	drop_sound = SFX_ITEMS_DROP_GLASS
	pickup_sound = SFX_ITEMS_PICKUP_GLASS
	var/rating = 1

/obj/item/reagent_containers/glass/beaker/get_rating()
	return rating

/obj/item/reagent_containers/glass/beaker/Initialize(mapload)
	. = ..()
	desc += " Can hold up to [volume] units."

/// The filling in the colour of what it holds, the lid while it is on, and a label.
/obj/item/reagent_containers/glass/beaker/draw(datum/look/look)
	. = ..()
	draw_glass(look, initial(icon_state), TRUE, TRUE)

/obj/item/reagent_containers/glass/beaker/large
	name = "large beaker"
	desc = "A large beaker."
	icon_state = "beakerlarge"
	center_of_mass_x = 16
	center_of_mass_y = 11
	material_template = /datum/material_template/container
	material_total = 5000
	volume = 120
	amount_per_transfer_from_this = 10
	max_transfer_amount = 120
	flags = NONE
	rating = 3

/obj/item/reagent_containers/glass/beaker/noreact
	name = "cryostasis beaker"
	desc = "A cryostasis beaker that allows for chemical storage without reactions."
	icon_state = "beakernoreact"
	center_of_mass_x = 16
	center_of_mass_y = 13
	material_template = /datum/material_template/container
	material_total = 500
	volume = 60
	amount_per_transfer_from_this = 10
	flags = NOREACT

/obj/item/reagent_containers/glass/beaker/bluespace
	name = "bluespace beaker"
	desc = "A bluespace beaker, powered by experimental bluespace technology."
	icon_state = "beakerbluespace"
	center_of_mass_x = 16
	center_of_mass_y = 11
	material_template = /datum/material_template/container
	material_total = 5000
	volume = 300
	amount_per_transfer_from_this = 10
	max_transfer_amount = 300
	flags = NONE
	rating = 5

/obj/item/reagent_containers/glass/beaker/vial
	name = "vial"
	desc = "A small glass vial."
	icon_state = "vial"
	center_of_mass_x = 15
	center_of_mass_y = 9
	material_template = /datum/material_template/container
	material_total = 250
	volume = 30
	w_class = ITEMSIZE_TINY
	amount_per_transfer_from_this = 10
	max_transfer_amount = 30
	flags = NONE

/obj/item/reagent_containers/glass/beaker/cryoxadone
	name = "beaker (cryoxadone)"
	prefill = list(REAGENT_ID_CRYOXADONE = 30)

/obj/item/reagent_containers/glass/beaker/sulphuric
	prefill = list(REAGENT_ID_SACID = 60)

/obj/item/reagent_containers/glass/beaker/stopperedbottle
	name = "stoppered bottle"
	desc = "A stoppered bottle for keeping beverages fresh."
	icon_state = "stopperedbottle"
	center_of_mass_x = 16
	center_of_mass_y = 13
	volume = 120
	amount_per_transfer_from_this = 10
	max_transfer_amount = 120
	flags = NONE

/obj/item/reagent_containers/glass/bucket
	desc = "It's a bucket."
	name = "bucket"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "bucket"
	item_state = "bucket"
	center_of_mass_x = 16
	center_of_mass_y = 10
	MATERIAL_BULK(MAT_STEEL, 200)
	w_class = ITEMSIZE_NORMAL
	amount_per_transfer_from_this = 20
	max_transfer_amount = 120
	volume = 120
	flags = NONE
	unacidable = FALSE
	drop_sound = SFX_ITEMS_DROP_HELM
	pickup_sound = SFX_ITEMS_PICKUP_HELM

/// The lid, while it is on.
/obj/item/reagent_containers/glass/bucket/draw(datum/look/look)
	. = ..()
	draw_glass(look, initial(icon_state), FALSE, FALSE)

// A bucket is wetted into a mop, a bar of soap, made into a bucket sensor with a proximity sensor, armed with a sheet of steel, and cut into a helmet.
CAPABILITIES(/obj/item/reagent_containers/glass/bucket)
	op("sensor", item(/obj/item/assembly/prox_sensor), priority(OP_PRIORITY_PART), label("Add the sensor"), then(PROC_REF(sensor_added)))
	op("robot_frame", stack(/obj/item/stack/material/steel, 1), priority(OP_PRIORITY_PART), label("Arm the robot frame"), then(PROC_REF(frame_armed)))
	op("wet", inputs(item(/obj/item/mop), item(/obj/item/soap)), priority(OP_PRIORITY_PART), label("Wet it"),
		needs(req_reagents(1, because = MSG(glass/bucket_empty))), then(PROC_REF(wetted)))
	op("cut_helmet", tool(TOOL_WIRECUTTER), wait(0), label("Cut a hole in it"), then(PROC_REF(cut_into_helmet)))

MSG_DEF_SELF(glass/bucket_empty, "The bucket is empty!")
MSG_DEF_SELF(glass/no_electronics, "This wooden bucket doesn't play well with electronics.")

/// The sensor goes into the bucket, and the bucket sensor is put in the hands of whoever did it.
/obj/item/reagent_containers/glass/bucket/proc/sensor_added(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, "You add [A.held] to [src].")
	consume(A.held, user)
	user.put_in_hands(new /obj/item/bucket_sensor)
	consume(src, user)
	return OP_OK

/// A sheet of steel (the op took it) arms the robot frame: it replaces the bucket where it is held.
/obj/item/reagent_containers/glass/bucket/proc/frame_armed(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/secbot_assembly/edCLN_assembly/B = new /obj/item/secbot_assembly/edCLN_assembly
	B.forceMove(get_turf(src))
	to_chat(user, span_notice("You armed the robot frame."))
	if(user.get_inactive_hand() == src)
		user.remove_from_mob(src)
		user.put_in_inactive_hand(B)
	consume(src, user)
	return OP_OK

/// The mop or the soap is wetted from the bucket, 5 units.
/obj/item/reagent_containers/glass/bucket/proc/wetted(datum/act/op/A)
	var/obj/item/D = A.held
	reagents.trans_to_obj(D, 5, user = A.actor)
	to_chat(A.actor, span_notice("You wet \the [D] in \the [src]."))
	play_sfx(src, SFX_EFFECTS_SLOSH)
	return OP_OK

/obj/item/reagent_containers/glass/bucket/proc/cut_into_helmet(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You cut a big hole in \the [src] with \the [A.held]. It's kinda useless as a bucket now."))
	user.put_in_hands(new /obj/item/clothing/head/helmet/bucket)
	consume(src, user)
	return OP_OK

/obj/item/reagent_containers/glass/bucket/wood
	desc = "An old wooden bucket."
	name = "wooden bucket"
	icon = 'icons/obj/janitor.dmi'
	icon_state = "woodbucket"
	item_state = "woodbucket"
	center_of_mass_x = 16
	center_of_mass_y = 8
	MATERIAL_BULK(MAT_WOOD, 50)
	w_class = ITEMSIZE_LARGE
	amount_per_transfer_from_this = 20
	max_transfer_amount = 120
	volume = 120
	flags = NONE
	unacidable = FALSE
	drop_sound = SFX_ITEMS_DROP_WOODEN
	pickup_sound = SFX_ITEMS_PICKUP_WOODEN

// A wooden bucket takes no electronics, and a hatchet cuts it into a helmet.
CAPABILITIES(/obj/item/reagent_containers/glass/bucket/wood)
	op("hatchet_helmet", item(/obj/item/material/knife/machete/hatchet), priority(OP_PRIORITY_PART), label("Cut a hole in it"), then(PROC_REF(cut_into_wood_helmet)))
	extend("sensor", needs(req(PROC_REF(electronics_welcome))))

/// A wooden bucket does not take electronics.
/obj/item/reagent_containers/glass/bucket/wood/proc/electronics_welcome(datum/act/op/A)
	return (FALSE) ? null : MSG(glass/no_electronics)

/obj/item/reagent_containers/glass/bucket/wood/proc/cut_into_wood_helmet(datum/act/op/A)
	var/mob/user = A.actor
	to_chat(user, span_notice("You cut a big hole in \the [src] with \the [A.held].  It's kinda useless as a bucket now."))
	user.put_in_hands(new /obj/item/clothing/head/helmet/bucket/wood)
	consume(src, user)
	return OP_OK

/obj/item/reagent_containers/glass/cooler_bottle
	desc = "A bottle for a water-cooler."
	name = "water-cooler bottle"
	icon = 'icons/obj/vending.dmi'
	icon_state = "water_cooler_bottle"
	MATERIAL_BULK(MAT_PLASTIC, 2000)
	w_class = ITEMSIZE_NO_CONTAINER
	amount_per_transfer_from_this = 20
	max_transfer_amount = 120
	volume = 2000
	slowdown = 2

CAPABILITIES(/obj/item/reagent_containers/glass/cooler_bottle)
	configure(reagent_container(rests_on = REAGENT_CONTAINER_CAN_BE_PLACED_INTO_WATERCOOLER))

/obj/item/reagent_containers/glass/pint_mug
	desc = "A rustic pint mug designed for drinking ale."
	name = "pint mug"
	icon = 'icons/obj/drinks.dmi'
	icon_state = "pint_mug"
	MATERIAL_BULK(MAT_WOOD, 50)
	drop_sound = SFX_ITEMS_DROP_WOODEN
	pickup_sound = SFX_ITEMS_PICKUP_WOODEN

/obj/item/reagent_containers/glass/beaker/vial/sustenance
	name = "vial (artificial sustenance)"
	prefill = list(REAGENT_ID_ASUSTENANCE = 30)

/obj/item/reagent_containers/glass/kettle
	name = "kettle"
	desc = "A simple kettle for brewing drinks."
	icon_state = "kettle"
	amount_per_transfer_from_this = 10
	max_transfer_amount = 20
	volume = 60
	w_class = ITEMSIZE_SMALL
	flags = NONE
	MATERIAL_BULK(MAT_STEEL, 50)
	drop_sound = SFX_ITEMS_DROP_CROWBAR
	pickup_sound = SFX_ITEMS_PICKUP_DRINKGLASS



/obj/item/reagent_containers/glass/beaker/neurotoxin
	prefill = list(REAGENT_ID_NEUROTOXIN = 50)

/obj/item/reagent_containers/glass/beaker/vial/bicaridine
	name = "vial (" + REAGENT_ID_BICARIDINE + ")"
	prefill = list(REAGENT_ID_BICARIDINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/dylovene
	name = "vial (" + REAGENT_ID_ANTITOXIN + ")"
	prefill = list(REAGENT_ID_ANTITOXIN = 30)

/obj/item/reagent_containers/glass/beaker/vial/dermaline
	name = "vial (" + REAGENT_ID_DERMALINE + ")"
	prefill = list(REAGENT_ID_DERMALINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/kelotane
	name = "vial (" + REAGENT_ID_KELOTANE + ")"
	prefill = list(REAGENT_ID_KELOTANE = 30)

/obj/item/reagent_containers/glass/beaker/vial/inaprovaline
	name = "vial (" + REAGENT_ID_INAPROVALINE + ")"
	prefill = list(REAGENT_ID_INAPROVALINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/dexalin
	name = "vial (" + REAGENT_ID_DEXALIN + ")"
	prefill = list(REAGENT_ID_DEXALIN = 30)

/obj/item/reagent_containers/glass/beaker/vial/dexalinplus
	name = "vial (" + REAGENT_ID_DEXALINP + ")"
	prefill = list(REAGENT_ID_DEXALINP = 30)

/obj/item/reagent_containers/glass/beaker/vial/tricordrazine
	name = "vial (" + REAGENT_ID_TRICORDRAZINE + ")"
	prefill = list(REAGENT_ID_TRICORDRAZINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/alkysine
	name = "vial (" + REAGENT_ID_ALKYSINE + ")"
	prefill = list(REAGENT_ID_ALKYSINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/imidazoline
	name = "vial (" + REAGENT_ID_IMIDAZOLINE + ")"
	prefill = list(REAGENT_ID_IMIDAZOLINE = 30)

/obj/item/reagent_containers/glass/beaker/vial/peridaxon
	name = "vial (" + REAGENT_ID_PERIDAXON + ")"
	prefill = list(REAGENT_ID_PERIDAXON = 30)

/obj/item/reagent_containers/glass/beaker/vial/hyronalin
	name = "vial (" + REAGENT_ID_HYRONALIN +")"
	prefill = list(REAGENT_ID_HYRONALIN = 30)

/obj/item/reagent_containers/glass/beaker/vial/amorphorovir
	name = "vial (" + REAGENT_ID_AMORPHOROVIR + ")"
	prefill = list(REAGENT_ID_AMORPHOROVIR = 1)

/obj/item/reagent_containers/glass/beaker/vial/androrovir
	name = "vial (" + REAGENT_ID_ANDROROVIR + ")"
	prefill = list(REAGENT_ID_ANDROROVIR = 1)

/obj/item/reagent_containers/glass/beaker/vial/gynorovir
	name = "vial (" + REAGENT_ID_GYNOROVIR + ")"
	prefill = list(REAGENT_ID_GYNOROVIR = 1)

/obj/item/reagent_containers/glass/beaker/vial/androgynorovir
	name = "vial (" + REAGENT_ID_ANDROGYNOROVIR + ")"
	prefill = list(REAGENT_ID_ANDROGYNOROVIR = 1)

/obj/item/reagent_containers/glass/beaker/vial/macrocillin
	name = "vial (" + REAGENT_ID_MACROCILLIN + ")"
	prefill = list(REAGENT_ID_MACROCILLIN = 1)

/obj/item/reagent_containers/glass/beaker/vial/microcillin
	name = "vial (" + REAGENT_ID_MICROCILLIN + ")"
	prefill = list(REAGENT_ID_MICROCILLIN = 1)

/obj/item/reagent_containers/glass/beaker/vial/normalcillin
	name = "vial (" + REAGENT_ID_NORMALCILLIN + ")"
	prefill = list(REAGENT_ID_NORMALCILLIN = 1)

/obj/item/reagent_containers/glass/beaker/vial/supermatter
	name = "vial (" + REAGENT_ID_SUPERMATTER + ")"
	desc = "A glass vial containing the extremely dangerous results of grinding a shard of supermatter down to a fine powder."
	prefill = list(REAGENT_ID_SUPERMATTER = 5)

/obj/item/reagent_containers/glass/beaker/measuring_cup
	name = "measuring cup"
	desc = "A measuring cup."
	icon_state = "measure_cup"
	item_state = "measure_cup"

/obj/item/reagent_containers/glass/beaker/lichpowder
	prefill = list(REAGENT_ID_LICHPOWDER = 50)

/obj/item/reagent_containers/glass/beaker/zombiepowder
	prefill = list(REAGENT_ID_ZOMBIEPOWDER = 50)
