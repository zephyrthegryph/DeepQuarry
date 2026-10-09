/obj/item/phone
	name = "red phone"
	desc = "Should anything ever go wrong..."
	icon = 'icons/obj/radio.dmi'
	icon_state = "red_phone"
	force = 3.0
	throwforce = 2.0
	throw_speed = 1
	throw_range = 4
	w_class = ITEMSIZE_SMALL
	attack_verb = list("called", "rang")
	hitsound = SFX_WEAPONS_RING
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

/obj/item/rsp
	name = "\improper Rapid-Seed-Producer (RSP)"
	desc = "A device used to rapidly deploy seeds."
	icon = 'icons/obj/items.dmi'
	icon_state = "rcd"
	opacity = 0
	density = FALSE
	anchored = FALSE
	var/stored_matter = 0
	var/mode = 1
	w_class = ITEMSIZE_NORMAL
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

/obj/item/bikehorn
	name = "bike horn"
	desc = "A horn off of a bicycle."
	icon = 'icons/obj/items.dmi'
	icon_state = "bike_horn"
	item_state = "bike_horn"
	throwforce = 3
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_HOLSTER
	throw_speed = 3
	throw_range = 15
	attack_verb = list("HONKED")
	var/honk_sound = SFX_ITEMS_BIKEHORN
	var/cooldown = 0
	var/honk_text = FALSE
	///Var for attack_self chain
	var/special_handling = FALSE

CAPABILITIES(/obj/item/bikehorn)
	op("honk", in_hand(), label("Honk"), when(cond_not(nameof(special_handling))), then(PROC_REF(honked)))

/obj/item/bikehorn/proc/honked(datum/act/op/A)
	if(COOLDOWN_FINISHED(src, cooldown))
		COOLDOWN_START(src, cooldown, 2 SECONDS)
		play_sfx(src, honk_sound, volume = 50, vary = TRUE)
		add_fingerprint(A.actor)
		if(honk_text)
			audible_message(span_maroon("[honk_text]"))
	return OP_OK

/obj/item/bikehorn/Crossed(atom/movable/AM as mob|obj)
	if(AM.is_incorporeal())
		return
	if(isliving(AM))
		playsound(src, honk_sound, 50, 1)

/obj/item/c_tube
	name = "cardboard tube"
	desc = "A tube... of cardboard."
	icon = 'icons/obj/items.dmi'
	icon_state = "c_tube"
	throwforce = 1
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 5
	resistance_flags = FLAMMABLE

/obj/item/disk
	name = "disk"
	icon = 'icons/obj/discs_vr.dmi'
	drop_sound = SFX_ITEMS_DROP_DISK
	pickup_sound =  SFX_ITEMS_PICKUP_DISK

/obj/item/disk/nuclear
	name = "nuclear authentication disk"
	desc = "Better keep this safe."
	icon_state = "nucleardisk"
	item_state = "card-id"
	w_class = ITEMSIZE_SMALL
	resistance_flags = INDESTRUCTIBLE | FIRE_PROOF

/obj/item/gift
	name = "gift"
	desc = "A wrapped item."
	icon = 'icons/obj/gifts.dmi'
	icon_state = "gift3"
	var/size = 3.0
	var/obj/item/gift = null
	item_state = "gift"
	w_class = ITEMSIZE_LARGE
	resistance_flags = FLAMMABLE

/obj/item/SWF_uplink
	name = "station-bounced radio"
	desc = "Used to communicate, it appears."
	icon = 'icons/obj/radio.dmi'
	icon_state = "radio"
	var/temp = null
	var/uses = 4.0
	var/selfdestruct = 0.0
	var/traitor_frequency = 0.0
	slot_flags = SLOT_BELT
	item_state = "radio"
	throwforce = 5
	w_class = ITEMSIZE_SMALL
	throw_speed = 4
	throw_range = 20
	MATERIAL_BULK(MAT_STEEL, 100)
	drop_sound = SFX_ITEMS_DROP_DEVICE
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE

/obj/item/staff
	name = "wizards staff"
	desc = "Apparently a staff used by the wizard."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "staff"
	item_icons = list(
			slot_l_hand_str = 'icons/mob/items/lefthand_melee.dmi',
			slot_r_hand_str = 'icons/mob/items/righthand_melee.dmi',
			)
	force = 3.0
	throwforce = 5.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL
	attack_verb = list("bludgeoned", "whacked", "disciplined")

/obj/item/staff/broom
	name = "broom"
	desc = "Used for sweeping, and flying into the night while cackling. Black cat not included."
	icon = 'icons/obj/wizard.dmi'
	icon_state = "broom"

/obj/item/staff/gentcane
	name = "Gentlemans Cane"
	desc = "An ebony can with an ivory tip."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "cane"

/obj/item/staff/stick
	name = "stick"
	desc = "A great tool to drag someone else's drinks across the bar."
	icon = 'icons/obj/weapons.dmi'
	icon_state = "stick"
	item_state = "cane"
	force = 3.0
	throwforce = 5.0
	throw_speed = 1
	throw_range = 5
	w_class = ITEMSIZE_SMALL

/obj/item/module
	icon = 'icons/obj/module.dmi'
	icon_state = "std_module"
	item_state = "std_mod"
	w_class = ITEMSIZE_SMALL
	var/mtype = 1						// 1=electronic 2=hardware
	drop_sound = SFX_ITEMS_DROP_COMPONENT
	pickup_sound = SFX_ITEMS_PICKUP_COMPONENT

/obj/item/module/card_reader
	name = "card reader module"
	icon_state = "card_mod"
	item_state = "std_mod"
	desc = "An electronic module for reading data and ID cards."

/obj/item/module/power_control
	name = "power control module"
	icon_state = "power_mod"
	item_state = "std_mod"
	desc = "Heavy-duty switching circuits for power control."
	MATERIAL_BULK(MAT_GLASS, 40)

/obj/item/module/id_auth
	name = "\improper ID authentication module"
	icon_state = "id_mod"
	desc = "A module allowing secure authorization of ID cards."

/obj/item/module/cell_power
	name = "power cell regulator module"
	icon_state = "power_mod"
	item_state = "std_mod"
	desc = "A converter and regulator allowing the use of power cells."

/obj/item/module/cell_power
	name = "power cell charger module"
	icon_state = "power_mod"
	item_state = "std_mod"
	desc = "Charging circuits for power cells."

/obj/item/camera_bug
	name = "camera bug"
	icon = 'icons/obj/device.dmi'
	icon_state = "flash"
	w_class = ITEMSIZE_TINY
	item_state = "electronic"
	throw_speed = 4
	throw_range = 20

MSG_DEF_SELF(camera_bug/none, "No bugged functioning cameras found.")

/// Using it asks which bugged camera to watch (the old attack_self).
CAPABILITIES(/obj/item/camera_bug)
	op("use", in_hand(), priority(OP_PRIORITY_DEFAULT - 1), needs(req(PROC_REF(has_bugged_cameras), because = MSG(camera_bug/none))), asks(/datum/prompt/choice, fields = list("question" = "Select the camera to observe", "title" = "Select Camera", "choices" = computed(PROC_REF(camera_choices)), "timeout" = 0), step = "k232"), then(PROC_REF(interaction_self)))

/// The functioning bugged cameras.
/obj/item/camera_bug/proc/bugged_cameras()
	var/list/cameras = list()
	for (var/obj/machinery/camera/C in REGISTRY_MEMBERS(REGISTRY_CAMERAS))
		if (C.bugged && C.status)
			cameras.Add(C)
	return cameras

/// Requirement: some bugged camera works.
/obj/item/camera_bug/proc/has_bugged_cameras(datum/act/op/A)
	return length(bugged_cameras()) > 0

/// The question's choices: the c_tags of the bugged cameras.
/obj/item/camera_bug/proc/camera_choices(datum/act/op/A)
	var/list/friendly_cameras = list()
	for (var/obj/machinery/camera/C in bugged_cameras())
		friendly_cameras.Add(C.c_tag)
	return friendly_cameras

/// Old attack_self, after the camera is chosen.
/obj/item/camera_bug/proc/interaction_self(datum/act/op/A)
	var/mob/user = A.actor
	var/target = A.step_value("k232")
	if (!target)
		return OP_OK
	for (var/obj/machinery/camera/C in bugged_cameras())
		if (C.c_tag == target)
			target = C
			break
	if (user.stat == 2) return OP_OK

	user.begin_remote_view(/datum/remote_view/item_zoom, target, null, /datum/remote_view_config/camera_standard, src, 0, FALSE)
	return OP_OK

/obj/item/pai_cable
	desc = "A flexible coated cable with a universal jack on one end."
	name = "data cable"
	icon = 'icons/obj/power.dmi'
	icon_state = "wire1"

	var/obj/machinery/machine

///////////////////////////////////////Stock Parts /////////////////////////////////

/obj/item/stock_parts
	name = "stock part"
	desc = "What?"
	gender = PLURAL
	icon = 'icons/obj/stock_parts.dmi'
	w_class = ITEMSIZE_SMALL
	var/rating = 1
	drop_sound = SFX_ITEMS_DROP_COMPONENT
	pickup_sound = SFX_ITEMS_PICKUP_COMPONENT

CAPABILITIES(/obj/item/stock_parts)
	rolls(nameof(pixel_x), range_of(-5.0, 5))
	rolls(nameof(pixel_y), range_of(-5.0, 5))
	op("item", item(/obj/item), label("Use"), then(PROC_REF(interaction_item)))

/obj/item/stock_parts/get_rating()
	return rating

//Rank 1

/obj/item/stock_parts/console_screen
	name = "console screen"
	desc = "Used in the construction of computers and other devices with a interactive console."
	icon_state = "screen"
	MATERIAL_BULK(MAT_GLASS, 200)

MATERIAL_MIX(/obj/item/stock_parts/capacitor, list(MAT_STEEL = 50,MAT_GLASS = 50))
/obj/item/stock_parts/capacitor
	name = "capacitor"
	desc = "A basic capacitor used in the construction of a variety of devices."
	icon_state = "capacitor"

	var/max_charge = 1000

/// Stored charge; read by its holder's derived fields as "capacitor.charge" (magnetic guns).
/obj/item/stock_parts/capacitor/var/charge = 0
TRACKED(/obj/item/stock_parts/capacitor, charge)

/obj/item/stock_parts/capacitor/Initialize(mapload)
	. = ..()
	max_charge *= rating

/obj/item/stock_parts/capacitor/proc/charge(amount)
	set_charge(min(charge + amount, max_charge))

/obj/item/stock_parts/capacitor/proc/use(amount)
	if(charge)
		set_charge(max(charge - amount, 0))

MATERIAL_MIX(/obj/item/stock_parts/scanning_module, list(MAT_STEEL = 50,MAT_GLASS = 20))
/obj/item/stock_parts/scanning_module
	name = "scanning module"
	desc = "A compact, high resolution scanning module used in the construction of certain devices."
	icon_state = "scan_module"

/obj/item/stock_parts/manipulator
	name = "micro-manipulator"
	desc = "A tiny little manipulator used in the construction of certain devices."
	icon_state = "micro_mani"
	MATERIAL_BULK(MAT_STEEL, 30)

MATERIAL_MIX(/obj/item/stock_parts/micro_laser, list(MAT_STEEL = 10,MAT_GLASS = 20))
/obj/item/stock_parts/micro_laser
	name = "micro-laser"
	desc = "A tiny laser used in certain devices."
	icon_state = "micro_laser"

/obj/item/stock_parts/matter_bin
	name = "matter bin"
	desc = "A container for hold compressed matter awaiting re-construction."
	icon_state = "matter_bin"
	MATERIAL_BULK(MAT_STEEL, 80)

// Tier subtypes (adv / super / hyper / omni / nano / pico /
// high / ultra / phasic) are gone. Stock parts are now material-driven:
// each part instance carries a `material_id` that points into
// GLOB.name_to_material, and get_rating() derives the rating from a
// per-part-type formula over the material's properties. See
// code/modules/materials/material_stock_parts.dm for the
// formulas and the imbue/crafting flow.

// Subspace stock parts

MATERIAL_MIX(/obj/item/stock_parts/subspace/ansible, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/stock_parts/subspace/ansible
	name = "subspace ansible"
	icon_state = "subspace_ansible"
	desc = "A compact module capable of sensing extradimensional activity."

MATERIAL_MIX(/obj/item/stock_parts/subspace/sub_filter, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/stock_parts/subspace/sub_filter
	name = "hyperwave filter"
	icon_state = "hyperwave_filter"
	desc = "A tiny device capable of filtering and converting super-intense radiowaves."

MATERIAL_MIX(/obj/item/stock_parts/subspace/amplifier, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/stock_parts/subspace/amplifier
	name = "subspace amplifier"
	icon_state = "subspace_amplifier"
	desc = "A compact micro-machine capable of amplifying weak subspace transmissions."

MATERIAL_MIX(/obj/item/stock_parts/subspace/treatment, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/stock_parts/subspace/treatment
	name = "subspace treatment disk"
	icon_state = "treatment_disk"
	desc = "A compact micro-machine capable of stretching out hyper-compressed radio waves."

MATERIAL_MIX(/obj/item/stock_parts/subspace/analyzer, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/stock_parts/subspace/analyzer
	name = "subspace wavelength analyzer"
	icon_state = "wavelength_analyzer"
	desc = "A sophisticated analyzer capable of analyzing cryptic subspace wavelengths."

/obj/item/stock_parts/subspace/crystal
	name = "ansible crystal"
	icon_state = "ansible_crystal"
	desc = "A crystal made from pure glass used to transmit laser databursts to subspace."
	MATERIAL_BULK(MAT_GLASS, 50)

/obj/item/stock_parts/subspace/transmitter
	name = "subspace transmitter"
	icon_state = "subspace_transmitter"
	desc = "A large piece of equipment used to open a window into the subspace dimension."
	MATERIAL_BULK(MAT_STEEL, 50)

/obj/item/ectoplasm
	name = "ectoplasm"
	desc = "Spooky!"
	gender = PLURAL
	icon = 'icons/obj/wizard.dmi'
	icon_state = "ectoplasm2"

// Additional construction stock parts

/obj/item/stock_parts/gear
	name = "gear"
	desc = "A gear used for construction."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "gear"
	MATERIAL_BULK(MAT_STEEL, 50)

MATERIAL_MIX(/obj/item/stock_parts/motor, list(MAT_STEEL = 60, MAT_GLASS = 10))
/obj/item/stock_parts/motor
	name = "motor"
	desc = "A motor used for construction."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "motor"

/obj/item/stock_parts/spring
	name = "spring"
	desc = "A spring used for construction."
	icon = 'icons/obj/stock_parts.dmi'
	icon_state = "spring"
	MATERIAL_BULK(MAT_STEEL, 40)

/obj/effect/spawner/parts
	name = "nondescript parts bundle that shouldn't exist"
	desc = "this qdels itself lol! if you're reading this you're codediving or Someone fucked up"

// Five of each part: one set rolled five times.
CAPABILITIES(/obj/effect/spawner/parts)
	map_resolver(GLOBAL_PROC_REF(resolve_loot))

/obj/effect/spawner/parts/t1
	name = "basic parts bundle"
	desc = "5 of each T1 part, no more and no less."

CAPABILITIES(/obj/effect/spawner/parts/t1)
	loot(
		table = list(
			loot_set(1, list(/obj/item/stock_parts/matter_bin, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/micro_laser))),
		count = 5)

/obj/effect/spawner/parts/t2
	name = "advanced parts bundle"
	desc = "5 of each T2 part, no more and no less."

CAPABILITIES(/obj/effect/spawner/parts/t2)
	loot(
		table = list(
			loot_set(1, list(/obj/item/stock_parts/matter_bin, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/micro_laser))),
		count = 5)

/obj/effect/spawner/parts/t3
	name = "super parts bundle"
	desc = "5 of each T3 part, no more and no less."

CAPABILITIES(/obj/effect/spawner/parts/t3)
	loot(
		table = list(
			loot_set(1, list(/obj/item/stock_parts/matter_bin, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/micro_laser))),
		count = 5)

/obj/effect/spawner/parts/t4
	name = "hyper parts bundle"
	desc = "5 of each T4 part, no more and no less."

CAPABILITIES(/obj/effect/spawner/parts/t4)
	loot(
		table = list(
			loot_set(1, list(/obj/item/stock_parts/matter_bin, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/micro_laser))),
		count = 5)

/obj/effect/spawner/parts/t5
	name = "omni parts bundle"
	desc = "5 of each T5 part, no more and no less."

CAPABILITIES(/obj/effect/spawner/parts/t5)
	loot(
		table = list(
			loot_set(1, list(/obj/item/stock_parts/matter_bin, /obj/item/stock_parts/manipulator, /obj/item/stock_parts/capacitor, /obj/item/stock_parts/scanning_module, /obj/item/stock_parts/micro_laser))),
		count = 5)

/// The machine this cable is jacked into (a relation view).
/obj/item/pai_cable/proc/machine() as /obj/machinery
	return machine

