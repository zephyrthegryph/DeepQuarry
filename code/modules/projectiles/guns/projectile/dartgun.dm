/obj/item/projectile/bullet/chemdart
	name = "dart"
	icon_state = "dart"
	damage = 5
	var/reagent_amount = 15
	range = 15 //shorter range

	muzzle_type = null

CAPABILITIES(/obj/item/projectile/bullet/chemdart)
	reagents(nameof(reagent_amount))


/obj/item/ammo_casing/chemdart
	name = "chemical dart"
	desc = "A casing containing a small hardened, hollow dart."
	icon_state = "dartcasing"
	caliber = "dart"
	projectile_type = /obj/item/projectile/bullet/chemdart

/obj/item/ammo_casing/chemdart/expend()
	..()

/obj/item/ammo_magazine/chemdart
	name = "dart cartridge"
	desc = "A rack of hollow darts."
	icon_state = "darts"
	item_state = "rcdammo"
	mag_type = MAGAZINE
	caliber = "dart"
	ammo_type = /obj/item/ammo_casing/chemdart
	max_ammo = 5
	multiple_sprites = 1

/obj/item/gun/projectile/dartgun/get_mechanics_info(list/additional_information)
	return ..(list("Stores up to [max_beakers] beakers. The dart gun only draws from beakers with mixing enabled, in equal amounts from each.") + additional_information)

/obj/item/gun/projectile/dartgun
	name = "dart gun"
	desc = "Zeng-Hu Pharmaceutical's entry into the arms market, the Z-H P Artemis is a gas-powered dart gun capable of delivering chemical cocktails swiftly across short distances."
	description_antag = "The dart gun is silenced, but cannot pierce thick clothing such as armor or space-suits, and thus is better for use against soft targets, or commonly exposed areas of the body."
	icon_state = "dartgun-empty"
	item_state = null
	var/base_state = "dartgun"

	caliber = "dart"
	fire_sound = SFX_WEAPONS_EMPTY
	fire_sound_text = "a metallic click"
	recoil = 0
	silenced = 1
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/chemdart
	allowed_magazines = list(/obj/item/ammo_magazine/chemdart)
	var/default_magazine_casing_count = 5
	var/track_magazine = 1
	auto_eject = 0

	var/list/beakers //All containers inside the gun.
	var/list/mixing //Containers being used for mixing.
	var/max_beakers = 3
	var/container_type = /obj/item/reagent_containers/glass/beaker
	var/list/starting_chems = null
	special_weapon_handling = TRUE

// Slotted beakers sit in the gun's contents; mixing is a subset of them.
/obj/item/gun/projectile/dartgun/ownership()
	. = ..()
	. += owns(nameof(beakers), policy = OWN_CONTAINED, is_list = TRUE, starts = PROC_REF(make_beakers))


/// The starting beakers (owns(starts =)): one of each starting chem.
/obj/item/gun/projectile/dartgun/proc/make_beakers(current)
	. = list()
	for(var/chem in starting_chems)
		var/obj/B = new container_type(src)
		B.reagents.add_reagent(chem, 60)
		. += B

/// Declared icon_state suffix: "-empty", the tracked dart count, or nothing.
/obj/item/gun/projectile/dartgun/proc/appearance_suffix()
	if(!ammo_magazine)
		return "-empty"
	if(!track_magazine)
		return ""
	return "-[min(length(ammo_magazine.stored_ammo), default_magazine_casing_count)]"
/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/dartgun/draw(datum/look/look)
	..()
	look.state("[base_state][appearance_suffix()]")

/obj/item/gun/projectile/dartgun/consume_next_projectile()
	. = ..()
	var/obj/item/projectile/bullet/chemdart/dart = .
	if(istype(dart))
		fill_dart(dart)

/obj/item/gun/projectile/dartgun/examine(mob/user)
	. = ..()
	if(length(beakers))
		. += span_notice("[src] contains:")
		for(var/obj/item/reagent_containers/glass/beaker/B in beakers)
			if(B.reagents && B.reagents.reagent_list.len)
				for(var/datum/reagent/R in B.reagents.reagent_list)
					. += span_notice("[R.volume] units of [R.name]")

/// Old attackby.
/obj/item/gun/projectile/dartgun/gun_item(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/reagent_containers/glass))
		if(!istype(I, container_type))
			to_chat(user, span_blue("[I] doesn't seem to fit into [src]."))
			return OP_PASS
		if(length(beakers) >= max_beakers)
			to_chat(user, span_blue("[src] already has [max_beakers] beakers in it - another one isn't going to fit!"))
			return OP_PASS
		var/obj/item/reagent_containers/glass/beaker/B = I
		if(!move_into(src, nameof(src.beakers), B, user))
			return OP_PASS
		to_chat(user, span_blue("You slot [B] into [src]."))
		updateUsrDialog(user)
		return OP_OK
	return ..()

//fills the given dart with reagents
/obj/item/gun/projectile/dartgun/proc/fill_dart(obj/item/projectile/bullet/chemdart/dart)
	if(length(mixing))
		var/mix_amount = dart.reagent_amount/length(mixing)
		for(var/obj/item/reagent_containers/glass/beaker/B in mixing)
			B.reagents.trans_to_obj(dart, mix_amount)

/// Old attack_self (the gun self-use chain: /obj/item/gun/proc/gun_self()).
/obj/item/gun/projectile/dartgun/gun_operate(datum/act/op/A, callback)
	var/mob/user = A.actor
	. = ..()
	if(. == OP_OK)
		return OP_OK
	// structured TGUI Dartgun (see
	// code/modules/admin/dartgun_panel.dm).
	user.set_machine(src)
	tgui_interact(user)

/obj/item/gun/projectile/dartgun/proc/check_beaker_mixing(obj/item/B)
	if(!mixing || !beakers)
		return 0
	for(var/obj/item/M in mixing)
		if(M == B)
			return 1
	return 0


///Variants of the Dartgun and Chemdarts.///

/obj/item/gun/projectile/dartgun/research
	name = "prototype dart gun"
	desc = "Zeng-Hu Pharmaceutical's entry into the arms market, the Z-H P Artemis is a gas-powered dart gun capable of delivering chemical cocktails swiftly across short distances. This one seems to be an early model with an NT stamp."
	icon_state = "dartgun_sci-empty"
	base_state = "dartgun_sci"
	magazine_type = /obj/item/ammo_magazine/chemdart/small
	allowed_magazines = list(/obj/item/ammo_magazine/chemdart)
	default_magazine_casing_count = 3
	max_beakers = 2

/obj/item/ammo_casing/chemdart/small
	name = "short chemical dart"
	desc = "A casing containing a small hardened, hollow dart."
	icon_state = "dartcasing"
	caliber = "dart"
	projectile_type = /obj/item/projectile/bullet/chemdart/small

/obj/item/ammo_magazine/chemdart/small
	name = "small dart cartridge"
	desc = "A rack of hollow darts."
	icon_state = "darts_small"
	item_state = "rcdammo"
	mag_type = MAGAZINE
	caliber = "dart"
	ammo_type = /obj/item/ammo_casing/chemdart/small
	max_ammo = 3
	multiple_sprites = 1

/obj/item/projectile/bullet/chemdart/small
	reagent_amount = 10


//-----------------------Tranq Gun----------------------------------
/obj/item/gun/projectile/dartgun/tranq
	name = "tranquilizer gun"
	desc = "A gas-powered dart gun designed by the National Armory of Gaia. This gun is used primarily by United Federation special forces for Tactical Espionage missions. Don't forget your bandana."
	icon_state = "tranqgun"
	item_state = null

	caliber = "dart"
	fire_sound = SFX_WEAPONS_EMPTY
	fire_sound_text = "a metallic click"
	recoil = 0
	silenced = 1
	load_method = MAGAZINE
	magazine_type = /obj/item/ammo_magazine/chemdart
	allowed_magazines = list(/obj/item/ammo_magazine/chemdart)
	auto_eject = 0

/// The look (the draw sweep: from its template).
/obj/item/gun/projectile/dartgun/tranq/draw(datum/look/look)
	..()
	look.state("tranqgun")

// This is to allow xenobio to activate slime cores via remote.
/obj/item/projectile/bullet/chemdart/on_hit(atom/target, blocked = 0, def_zone = null)
	..()
	if(blocked < 2)
		if(isliving(target))
			var/mob/living/L = target
			if(L.can_inject(target_zone=def_zone))
				reagents.trans_to_mob(L, reagent_amount, CHEM_BLOOD)
		else if(istype(target, /obj/item/reagent_containers/food) || istype(target, /obj/item/slime_extract))
			reagents.trans_to_obj(target, reagent_amount)

/// Starts (`mix` TRUE) or stops mixing the beaker in slot `index`.
/obj/item/gun/projectile/dartgun/proc/dartgun_set_mixing(mob/user, index, mix)
	add_fingerprint(user)
	if(!isnum(index) || index < 1 || index > length(beakers))
		return
	var/obj/item/B = LAZYACCESS(beakers, index)
	if(!B)
		return
	if(mix)
		rel_add(src, nameof(mixing), B)
	else
		rel_remove(src, nameof(mixing), B)
	updateUsrDialog(user)

/// Ejects the beaker in slot `index` onto the floor.
/obj/item/gun/projectile/dartgun/proc/dartgun_eject_beaker(mob/user, index)
	add_fingerprint(user)
	if(!isnum(index) || index < 1 || index > length(beakers))
		return
	var/obj/item/reagent_containers/glass/beaker/B = LAZYACCESS(beakers, index)
	if(!B)
		return
	to_chat(user, "You remove [B] from [src].")
	rel_remove(src, nameof(mixing), B)
	own_take_member(src, nameof(beakers), B)
	B.forceMove(get_turf(src))
	updateUsrDialog(user)
