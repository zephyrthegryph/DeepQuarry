GLOBAL_LIST_EMPTY(outfits_decls)
GLOBAL_LIST_EMPTY(outfits_decls_by_type)
GLOBAL_DATUM_INIT(outfits_decls_root, /datum/decl/hierarchy/outfit, new) // Rewuires the above lists

/proc/outfit_by_type(outfit_type)
	return GLOB.outfits_decls_by_type[outfit_type]

/proc/outfits()
	return GLOB.outfits_decls

/datum/decl/hierarchy/outfit
	name = "Naked"

	var/uniform = null
	var/suit = null
	var/back = null
	var/belt = null
	var/gloves = null
	var/shoes = null
	var/head = null
	var/mask = null
	var/l_ear = null
	var/r_ear = null
	var/glasses = null
	var/id = null
	var/l_pocket = null
	var/r_pocket = null
	var/suit_store = null
	var/r_hand = null
	var/l_hand = null
	// In the list(path=count,otherpath=count) format
	var/list/uniform_accessories = list() // webbing, armbands etc - fits in slot_tie
	var/list/backpack_contents = list()

	var/id_type
	var/id_desc
	var/id_slot

	var/pda_type
	var/pda_slot

	var/id_pda_assignment

	var/headset = /obj/item/radio/headset
	var/headset_alt = /obj/item/radio/headset/alt
	var/headset_earbud = /obj/item/radio/headset/earbud

	var/backpack = /obj/item/storage/backpack
	var/satchel_one  = /obj/item/storage/backpack/satchel/norm
	var/satchel_two  = /obj/item/storage/backpack/satchel
	var/messenger_bag = /obj/item/storage/backpack/messenger
	var/sports_bag = /obj/item/storage/backpack/sport
	var/satchel_three = /obj/item/storage/backpack/satchel/strapless

	var/flags // Specific flags

	var/undress = 1	//Does the outfit undress the mob upon equp?

/datum/decl/hierarchy/outfit/New()
	..()

	if(is_hidden_category())
		return
	GLOB.outfits_decls_by_type[type] = src
	dd_insertObjectList(GLOB.outfits_decls, src)

/datum/decl/hierarchy/outfit/proc/pre_equip(mob/living/carbon/human/H)
	switch(H.headset)
		if(1) l_ear = headset
		if(2) l_ear = headset_alt
		if(3) l_ear = headset_earbud
	if(flags & OUTFIT_HAS_BACKPACK)
		switch(H.backbag)
			if(2) back = backpack
			if(3) back = satchel_one
			if(4) back = satchel_two
			if(5) back = messenger_bag
			if(6) back = sports_bag
			if(7) back = satchel_three
			else back = null

/datum/decl/hierarchy/outfit/proc/post_equip(mob/living/carbon/human/H)
	if(flags & OUTFIT_HAS_JETPACK)
		var/obj/item/tank/jetpack/J = locate(/obj/item/tank/jetpack) in H
		if(!J)
			return
		J.toggle()
		J.toggle_valve()

/datum/decl/hierarchy/outfit/proc/equip(mob/living/carbon/human/H, rank, assignment)
	equip_base(H)

	rank = rank || id_pda_assignment
	assignment = id_pda_assignment || assignment || rank
	var/obj/item/card/id/W = equip_id(H, rank, assignment)
	if(W)
		rank = W.rank
		assignment = W.assignment
	equip_pda(H, rank, assignment)

	for(var/path in backpack_contents)
		var/number = backpack_contents[path]
		for(var/i=0,i<number,i++)
			H.equip_to_slot_or_del(new path(H), slot_in_backpack)

	post_equip(H)

	if(W) // We set ID info last to ensure the ID photo is as correct as possible.
		H.set_id_info(W)
	return 1

/datum/decl/hierarchy/outfit/proc/equip_base(mob/living/carbon/human/H)
	pre_equip(H)

	//Start with uniform,suit,backpack for additional slots
	if(uniform)
		H.equip_to_slot_or_del(new uniform(H),slot_w_uniform)
	if(suit)
		// no_jacket pref deleted; always equip the default suit. Players who don't
		// want it pick an alternate uniform via the regular loadout system.
		H.equip_to_slot_or_del(new suit(H),slot_wear_suit)
	if(back)
		H.equip_to_slot_or_del(new back(H),slot_back)
	if(belt)
		H.equip_to_slot_or_del(new belt(H),slot_belt)
	if(gloves)
		H.equip_to_slot_or_del(new gloves(H),slot_gloves)
	if(shoes)
	// , remove RS No shoes
	//	if(!(H.client?.prefs?.shoe_hater))	//RS ADD
		H.equip_to_slot_or_del(new shoes(H),slot_shoes)
	// , remove RS No Shoes
	if(mask)
		H.equip_to_slot_or_del(new mask(H),slot_wear_mask)
	if(head)
		H.equip_to_slot_or_del(new head(H),slot_head)
	if(l_ear)
		H.equip_to_slot_or_del(new l_ear(H),slot_l_ear)
	if(r_ear)
		H.equip_to_slot_or_del(new r_ear(H),slot_r_ear)
	if(glasses)
		H.equip_to_slot_or_del(new glasses(H),slot_glasses)
	if(id)
		H.equip_to_slot_or_del(new id(H),slot_wear_id)
	if(l_pocket)
		H.equip_to_slot_or_del(new l_pocket(H),slot_l_store)
	if(r_pocket)
		H.equip_to_slot_or_del(new r_pocket(H),slot_r_store)
	if(suit_store)
		H.equip_to_slot_or_del(new suit_store(H),slot_s_store)

	if(l_hand)
		H.put_in_l_hand(new l_hand(H))
	if(r_hand)
		H.put_in_r_hand(new r_hand(H))

	for(var/path in uniform_accessories)
		var/number = uniform_accessories[path]
		for(var/i=0,i<number,i++)
			H.equip_to_slot_or_del(new path(H), slot_tie)

	if(H.species)
		H.species.equip_survival_gear(H, flags&OUTFIT_EXTENDED_SURVIVAL, flags&OUTFIT_COMPREHENSIVE_SURVIVAL)

/datum/decl/hierarchy/outfit/proc/equip_id(mob/living/carbon/human/H, rank, assignment)
	if(!id_slot || !id_type)
		return
	var/obj/item/card/id/W = new id_type(H)
	if(id_desc)
		W.desc = id_desc
	if(rank)
		W.rank = rank
	if(assignment)
		W.assignment = assignment
	if(H.equip_to_slot_or_del(W, id_slot))
		return W

/datum/decl/hierarchy/outfit/proc/equip_pda(mob/living/carbon/human/H, rank, assignment)
	if(!pda_slot || !pda_type)
		return
	var/obj/item/pda/pda = new pda_type(H)
	if(H.equip_to_slot_or_del(pda, pda_slot))
		pda.owner = H.real_name
		pda.ownjob = assignment
		pda.ownrank = rank
		pda.name = "PDA-[H.real_name] ([assignment])"
		var/_ringtone = H.client?.prefs?.read_preference(/datum/preference/text/human/ringtone) // migrated pref
		if(_ringtone)
			pda.ttone = _ringtone
		return pda

/datum/decl/hierarchy/outfit/dd_SortValue()
	return name


// === merged from outfit_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/datum/decl/hierarchy/outfit/USDF/Marine
	name = "USDF marine"
	uniform = /obj/item/clothing/under/solgov/utility/army/urban
	shoes = /obj/item/clothing/shoes/boots/jackboots
	gloves = /obj/item/clothing/gloves/combat
	r_pocket = /obj/item/ammo_magazine/m95
	l_pocket = /obj/item/ammo_magazine/m95
	l_hand = /obj/item/ammo_magazine/m95
	r_hand = /obj/item/ammo_magazine/m95
	back = /obj/item/gun/projectile/automatic/battlerifle
	backpack_contents = list(/obj/item/storage/box = 1)
	hierarchy_type = /datum/decl/hierarchy/outfit/wizard
	head = /obj/item/clothing/head/helmet/combat/USDF
	suit = /obj/item/clothing/suit/armor/combat/USDF
	belt = /obj/item/storage/belt/security/tactical

	headset = /obj/item/radio/headset/centcom
	headset_alt = /obj/item/radio/headset/centcom
	headset_earbud = /obj/item/radio/headset/centcom

/datum/decl/hierarchy/outfit/USDF/Marine/equip_id(mob/living/carbon/human/H)
	var/obj/item/card/id/C = ..()
	C.name = "[H.real_name]'s military ID Card"
	C.icon_state = "lifetime"
	C.access = SSaccess.get_all_station_access()
	C.access += SSaccess.get_all_centcom_access()
	C.assignment = "USDF"
	C.registered_name = H.real_name
	return C

/datum/decl/hierarchy/outfit/USDF/Officer
	name = "USDF officer"
	head = /obj/item/clothing/head/dress/army/command
	shoes = /obj/item/clothing/shoes/boots/jackboots
	uniform = /obj/item/clothing/under/solgov/mildress/army/command
	back = /obj/item/storage/backpack/satchel
	belt = /obj/item/gun/projectile/revolver/consul
	l_pocket = /obj/item/ammo_magazine/s44
	r_pocket = /obj/item/ammo_magazine/s44
	r_hand = /obj/item/clothing/accessory/holster/hip
	l_hand = /obj/item/clothing/accessory/tie/black

	headset = /obj/item/radio/headset/centcom
	headset_alt = /obj/item/radio/headset/centcom
	headset_earbud = /obj/item/radio/headset/centcom

/datum/decl/hierarchy/outfit/USDF/Officer/equip_id(mob/living/carbon/human/H)
	var/obj/item/card/id/C = ..()
	C.name = "[H.real_name]'s military ID Card"
	C.icon_state = "lifetime"
	C.access = SSaccess.get_all_station_access()
	C.access += SSaccess.get_all_centcom_access()
	C.assignment = "USDF"
	C.registered_name = H.real_name
	return C

/datum/decl/hierarchy/outfit/solcom/representative
	name = "SolGov Representative" // SolGov
	shoes = /obj/item/clothing/shoes/laceup
	uniform = /obj/item/clothing/under/suit_jacket/navy
	back = /obj/item/storage/backpack/satchel
	l_pocket = /obj/item/pen/blue
	r_pocket = /obj/item/pen/red
	r_hand = /obj/item/pda/centcom
	l_hand = /obj/item/clipboard

	headset = /obj/item/radio/headset/centcom
	headset_alt = /obj/item/radio/headset/centcom
	headset_earbud = /obj/item/radio/headset/centcom

/datum/decl/hierarchy/outfit/solcom/representative/equip_id(mob/living/carbon/human/H)
	var/obj/item/card/id/C = ..()
	C.name = "[H.real_name]'s SolGov ID Card" // SolGov
	C.icon_state = "lifetime"
	C.access = SSaccess.get_all_station_access()
	C.access += SSaccess.get_all_centcom_access()
	C.assignment = "SolGov Representative" // SolGov
	C.registered_name = H.real_name
	return C

/datum/decl/hierarchy/outfit/imperial/soldier
	name = "Imperial soldier"
	head = /obj/item/clothing/head/helmet/combat/imperial
	shoes =/obj/item/clothing/shoes/leg_guard/combat/imperial
	gloves = /obj/item/clothing/gloves/arm_guard/combat/imperial
	uniform = /obj/item/clothing/under/imperial
	mask = /obj/item/clothing/mask/gas/imperial
	suit = /obj/item/clothing/suit/armor/combat/imperial
	back = /obj/item/storage/backpack/satchel
	belt = /obj/item/storage/belt/security/tactical/bandolier
	l_pocket = /obj/item/cell/device/weapon
	r_pocket = /obj/item/cell/device/weapon
	r_hand = /obj/item/melee/energy/sword/imperial
	l_hand = /obj/item/shield/energy/imperial
	suit_store = /obj/item/gun/energy/imperial

	headset = /obj/item/radio/headset/syndicate
	headset_alt = /obj/item/radio/headset/syndicate
	headset_earbud = /obj/item/radio/headset/syndicate

/datum/decl/hierarchy/outfit/imperial/officer
	name = "Imperial officer"
	head = /obj/item/clothing/head/helmet/combat/imperial/centurion
	shoes = /obj/item/clothing/shoes/leg_guard/combat/imperial
	gloves = /obj/item/clothing/gloves/arm_guard/combat/imperial
	uniform = /obj/item/clothing/under/imperial
	mask = /obj/item/clothing/mask/gas/imperial
	suit = /obj/item/clothing/suit/armor/combat/imperial/centurion
	belt = /obj/item/storage/belt/security/tactical/bandolier
	l_pocket = /obj/item/cell/device/weapon
	r_pocket = /obj/item/cell/device/weapon
	r_hand = /obj/item/melee/energy/sword/imperial
	l_hand = /obj/item/shield/energy/imperial
	suit_store = /obj/item/gun/energy/imperial

	headset = /obj/item/radio/headset/syndicate
	headset_alt = /obj/item/radio/headset/syndicate
	headset_earbud = /obj/item/radio/headset/syndicate

/*
SOUTHERN CROSS OUTFITS
Keep outfits simple. Spawn with basic uniforms and minimal gear. Gear instead goes in lockers. Keep this in mind if editing.
*/


/datum/decl/hierarchy/outfit/job/explorer2
	name = OUTFIT_JOB_NAME(JOB_EXPLORER)
	shoes = /obj/item/clothing/shoes/boots/winter/explorer
	uniform = /obj/item/clothing/under/explorer
	id_slot = slot_wear_id
	pda_slot = slot_l_store
	pda_type = /obj/item/pda/explorer
	id_type = /obj/item/card/id/exploration
	id_pda_assignment = JOB_EXPLORER
	backpack = /obj/item/storage/backpack/explorer
	satchel_one = /obj/item/storage/backpack/satchel/explorer
	messenger_bag = /obj/item/storage/backpack/messenger/explorer
	flags = OUTFIT_HAS_BACKPACK|OUTFIT_COMPREHENSIVE_SURVIVAL

	headset = /obj/item/radio/headset/explorer
	headset_alt = /obj/item/radio/headset/alt/explorer
	headset_earbud = /obj/item/radio/headset/explorer

/datum/decl/hierarchy/outfit/job/pilot
	name = OUTFIT_JOB_NAME(JOB_PILOT)
	shoes = /obj/item/clothing/shoes/black
	uniform = /obj/item/clothing/under/rank/pilot1/no_webbing
	suit = /obj/item/clothing/suit/storage/toggle/bomber/pilot
	gloves = /obj/item/clothing/gloves/fingerless
	glasses = /obj/item/clothing/glasses/fakesunglasses/aviator
	uniform_accessories = list(/obj/item/clothing/accessory/storage/webbing/pilot1 = 1)
	id_slot = slot_wear_id
	pda_slot = slot_belt
	pda_type = /obj/item/pda/pilot
	id_type = /obj/item/card/id/civilian/pilot
	id_pda_assignment = JOB_PILOT
	flags = OUTFIT_HAS_BACKPACK|OUTFIT_COMPREHENSIVE_SURVIVAL

	headset = /obj/item/radio/headset/pilot
	headset_alt = /obj/item/radio/headset/alt/pilot
	headset_earbud = /obj/item/radio/headset/alt/pilot

/datum/decl/hierarchy/outfit/job/medical/sar
	name = OUTFIT_JOB_NAME(JOB_FIELD_MEDIC)
	uniform = /obj/item/clothing/under/utility/blue
	//suit = /obj/item/clothing/suit/storage/hooded/wintercoat/medical/sar
	shoes = /obj/item/clothing/shoes/boots/winter/explorer
	l_hand = /obj/item/storage/firstaid/regular
	belt = /obj/item/storage/belt/medical/emt
	pda_slot = slot_l_store
	pda_type = /obj/item/pda/sar
	id_type = /obj/item/card/id/exploration/fm
	id_pda_assignment = JOB_FIELD_MEDIC
	backpack = /obj/item/storage/backpack/explorer
	satchel_one = /obj/item/storage/backpack/satchel/explorer
	messenger_bag = /obj/item/storage/backpack/messenger/explorer
	flags = OUTFIT_HAS_BACKPACK|OUTFIT_EXTENDED_SURVIVAL|OUTFIT_COMPREHENSIVE_SURVIVAL

	headset = /obj/item/radio/headset/sar
	headset_alt = /obj/item/radio/headset/alt/sar
	headset_earbud = /obj/item/radio/headset/sar

/datum/decl/hierarchy/outfit/job/pathfinder
	name = OUTFIT_JOB_NAME(JOB_PATHFINDER)
	shoes = /obj/item/clothing/shoes/boots/winter/explorer
	uniform = /obj/item/clothing/under/explorer //TODO: Uniforms.
	id_slot = slot_wear_id
	pda_slot = slot_l_store
	pda_type = /obj/item/pda/pathfinder
	id_type = /obj/item/card/id/exploration/head
	id_pda_assignment = JOB_PATHFINDER
	backpack = /obj/item/storage/backpack/explorer
	satchel_one = /obj/item/storage/backpack/satchel/explorer
	messenger_bag = /obj/item/storage/backpack/messenger/explorer
	flags = OUTFIT_HAS_BACKPACK|OUTFIT_EXTENDED_SURVIVAL|OUTFIT_COMPREHENSIVE_SURVIVAL

	headset = /obj/item/radio/headset/pathfinder
	headset_alt = /obj/item/radio/headset/alt/pathfinder
	headset_earbud = /obj/item/radio/headset/pathfinder

/datum/decl/hierarchy/outfit/job/assistant/explorer
	id_type = /obj/item/card/id/exploration
	flags = OUTFIT_HAS_BACKPACK|OUTFIT_COMPREHENSIVE_SURVIVAL
