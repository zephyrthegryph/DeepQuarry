CAPABILITIES(/obj/item/storage/box/syndicate)
	initial_contents(PROC_REF(roll_bundle))

/// Rolled contents (initial_contents()): one of nine equally likely bundles.
/obj/item/storage/box/syndicate/proc/roll_bundle(datum/roller/R)
	var/static/list/bundles = list(
		"bloodyspai" = list(/obj/item/clothing/under/chameleon, /obj/item/clothing/mask/gas/voice, /obj/item/card/id/syndicate, /obj/item/clothing/shoes/syndigaloshes),
		"stealth" = list(/obj/item/gun/energy/crossbow, /obj/item/pen/reagent/paralysis, /obj/item/chameleon),
		"screwed" = list(/obj/effect/spawner/newbomb/timer/syndicate, /obj/effect/spawner/newbomb/timer/syndicate, /obj/item/powersink, /obj/item/clothing/suit/space/syndicate, /obj/item/clothing/head/helmet/space/syndicate, /obj/item/clothing/mask/gas/syndicate, /obj/item/tank/emergency/oxygen/double),
		"guns" = list(/obj/item/gun/projectile/revolver, /obj/item/ammo_magazine/s357, /obj/item/card/emag, /obj/item/plastique, /obj/item/plastique),
		"murder" = list(/obj/item/melee/energy/sword, /obj/item/clothing/glasses/thermal/syndi, /obj/item/card/emag, /obj/item/clothing/shoes/syndigaloshes),
		"freedom" = list(/obj/item/implanter/freedom, /obj/item/implanter/uplink),
		"hacker" = list(/obj/item/encryptionkey/syndicate, /obj/item/aiModule/syndicate, /obj/item/card/emag, /obj/item/encryptionkey/binary),
		"lordsingulo" = list(/obj/item/radio/beacon/syndicate, /obj/item/clothing/suit/space/syndicate, /obj/item/clothing/head/helmet/space/syndicate, /obj/item/clothing/mask/gas/syndicate, /obj/item/tank/emergency/oxygen/double, /obj/item/card/emag),
		"smoothoperator" = list(/obj/item/storage/box/syndie_kit/g9mm, /obj/item/storage/bag/trash, /obj/item/soap/syndie, /obj/item/bodybag, /obj/item/clothing/under/suit_jacket, /obj/item/clothing/shoes/laceup))
	return bundles[R.choose(bundles)]

/obj/item/storage/box/syndie_kit
	name = "box"
	desc = "A sleek, sturdy box"
	icon_state = "box_of_doom"

/obj/item/storage/box/syndie_kit/imp_freedom
	name = "boxed freedom implant (with injector)"

CAPABILITIES(/obj/item/storage/box/syndie_kit/imp_freedom)
	initial_contents(/obj/item/implanter/freedom)

/obj/item/storage/box/syndie_kit/imp_compress
	name = "box (C)"
	starts_with = list(/obj/item/implanter/compressed)

/obj/item/storage/box/syndie_kit/imp_explosive
	name = "box (E)"
	starts_with = list(/obj/item/implanter/explosive)

/obj/item/storage/box/syndie_kit/imp_uplink
	name = "boxed uplink implant (with injector)"

CAPABILITIES(/obj/item/storage/box/syndie_kit/imp_uplink)
	initial_contents(/obj/item/implanter/uplink)

/obj/item/storage/box/syndie_kit/imp_aug
	name = "boxed augment implant (with injector)"
	var/case_type = /obj/item/implantcase/shades

CAPABILITIES(/obj/item/storage/box/syndie_kit/imp_aug)
	initial_contents(/obj/item/implanter)
	initial_contents(nameof(case_type))

/obj/item/storage/box/syndie_kit/imp_aug/taser
	case_type = /obj/item/implantcase/taser

/obj/item/storage/box/syndie_kit/imp_aug/laser
	case_type = /obj/item/implantcase/laser

/obj/item/storage/box/syndie_kit/imp_aug/dart
	case_type = /obj/item/implantcase/dart

/obj/item/storage/box/syndie_kit/imp_aug/toolkit
	case_type = /obj/item/implantcase/toolkit

/obj/item/storage/box/syndie_kit/imp_aug/medkit
	case_type = /obj/item/implantcase/medkit

/obj/item/storage/box/syndie_kit/imp_aug/surge
	case_type = /obj/item/implantcase/surge

/obj/item/storage/box/syndie_kit/imp_aug/analyzer
	case_type = /obj/item/implantcase/analyzer

/obj/item/storage/box/syndie_kit/imp_aug/sword
	case_type = /obj/item/implantcase/sword

/obj/item/storage/box/syndie_kit/imp_aug/sprinter
	case_type = /obj/item/implantcase/sprinter

/obj/item/storage/box/syndie_kit/imp_aug/med_scanner
	case_type = /obj/item/implantcase/med_scanner

/obj/item/storage/box/syndie_kit/imp_aug/armblade
	case_type = /obj/item/implantcase/armblade

/obj/item/storage/box/syndie_kit/imp_aug/handblade
	case_type = /obj/item/implantcase/handblade

/obj/item/storage/box/syndie_kit/space
	name = "boxed space suit and helmet"
	starts_with = list(
		/obj/item/clothing/suit/space/syndicate,
		/obj/item/clothing/head/helmet/space/syndicate,
		/obj/item/clothing/mask/gas/syndicate,
		/obj/item/tank/emergency/oxygen/double
	)

/obj/item/storage/box/syndie_kit/chameleon
	name = "chameleon kit"
	desc = "Comes with all the clothes you need to impersonate most people.  Acting lessons sold separately."
	starts_with = list(
		/obj/item/storage/backpack/chameleon/full,
		/obj/item/gun/energy/chameleon
	)

/obj/item/storage/box/syndie_kit/clerical
	name = "clerical kit"
	desc = "Comes with all you need to fake paperwork. Assumes you have passed basic writing lessons."
	starts_with = list(
		/obj/item/stamp/chameleon,
		/obj/item/pen/chameleon,
		/obj/item/destTagger,
		/obj/item/packageWrap,
		/obj/item/hand_labeler
	)

/obj/item/storage/box/syndie_kit/spy
	name = "spy kit"
	desc = "For when you want to conduct voyeurism from afar."
	starts_with = list(
		/obj/item/camerabug/spy = 6,
		/obj/item/bug_monitor/spy
	)

/obj/item/storage/box/syndie_kit/g9mm
	name = "\improper Smooth operator"
	desc = "Compact 9mm with silencer kit."
	starts_with = list(
		/obj/item/gun/projectile/pistol,
		/obj/item/silencer
	)

/obj/item/storage/box/syndie_kit/toxin
	name = "toxin kit"
	desc = "An apple will not be enough to keep the doctor away after this."
	starts_with = list(
		/obj/item/reagent_containers/glass/beaker/vial/random/toxin,
		/obj/item/reagent_containers/syringe
	)

/obj/item/storage/box/syndie_kit/cigarette
	name = "\improper Tricky smokes"
	desc = "Comes with the following brands of cigarettes, in this order: 2xFlash, 2xSmoke, 1xMindBreaker, 1xTricordrazine. Avoid mixing them up."

CAPABILITIES(/obj/item/storage/box/syndie_kit/cigarette)
	initial_contents(/obj/item/storage/fancy/cigarettes/tricky/flash, count = 2)
	initial_contents(/obj/item/storage/fancy/cigarettes/tricky/smoke, count = 2)
	initial_contents(/obj/item/storage/fancy/cigarettes/tricky/mindbreaker)
	initial_contents(/obj/item/storage/fancy/cigarettes/tricky/tricordrazine)
	initial_contents(/obj/item/flame/lighter/zippo)

/// The Tricky smokes' packs: plain packs laced through the packet (the reagents are 15 units a cigarette, shared on removal).
/obj/item/storage/fancy/cigarettes/tricky/flash
	desc = "A ubiquitous brand of cigarettes, found in every major spacefaring corporation in the universe. As mild and flavorless as it gets. 'F' has been scribbled on it."

CAPABILITIES(/obj/item/storage/fancy/cigarettes/tricky/flash)
	configure(reagents(starts = list(REAGENT_ID_ALUMINIUM = 30, REAGENT_ID_POTASSIUM = 30, REAGENT_ID_SULFUR = 30)))

/obj/item/storage/fancy/cigarettes/tricky/smoke
	desc = "A ubiquitous brand of cigarettes, found in every major spacefaring corporation in the universe. As mild and flavorless as it gets. 'S' has been scribbled on it."

CAPABILITIES(/obj/item/storage/fancy/cigarettes/tricky/smoke)
	configure(reagents(starts = list(REAGENT_ID_POTASSIUM = 30, REAGENT_ID_SUGAR = 30, REAGENT_ID_PHOSPHORUS = 30)))

/obj/item/storage/fancy/cigarettes/tricky/mindbreaker
	desc = "A ubiquitous brand of cigarettes, found in every major spacefaring corporation in the universe. As mild and flavorless as it gets. 'MB' has been scribbled on it."

// Dylovene (1.5 of each a cigarette, rather than 1.6666...) and mindbreaker (4.5 of silicon and hydrogen).
CAPABILITIES(/obj/item/storage/fancy/cigarettes/tricky/mindbreaker)
	configure(reagents(starts = list(REAGENT_ID_POTASSIUM = 9, REAGENT_ID_NITROGEN = 9, REAGENT_ID_SILICON = 36, REAGENT_ID_HYDROGEN = 27)))

/obj/item/storage/fancy/cigarettes/tricky/tricordrazine
	desc = "A ubiquitous brand of cigarettes, found in every major spacefaring corporation in the universe. As mild and flavorless as it gets. 'T' has been scribbled on it."

CAPABILITIES(/obj/item/storage/fancy/cigarettes/tricky/tricordrazine)
	configure(reagents(starts = list(REAGENT_ID_TRICORDRAZINE = 90)))

/obj/item/storage/box/syndie_kit/ewar_voice
	name = "Electrowarfare and Voice Synthesiser kit"
	desc = "Kit for confounding organic and synthetic entities alike."
	starts_with = list(
		/obj/item/rig_module/electrowarfare_suite,
		/obj/item/rig_module/voice
	)

/obj/item/storage/secure/briefcase/money
	name = "suspicious briefcase"
	desc = "An ominous briefcase that has the unmistakeable smell of old, stale, cigarette smoke, and gives those who look at it a bad feeling."
	starts_with = list(/obj/item/spacecash/c1000 = 10)

/obj/item/storage/box/syndie_kit/combat_armor
	name = "combat armor kit"
	desc = "Contains a full set of combat armor."
	starts_with = list(
		/obj/item/clothing/head/helmet/combat,
		/obj/item/clothing/suit/armor/combat,
		/obj/item/clothing/gloves/arm_guard/combat,
		/obj/item/clothing/shoes/leg_guard/combat
	)

/obj/item/storage/box/syndie_kit/demolitions
	starts_with = list(
		/obj/item/syndie/c4explosive,
		/obj/item/tool/screwdriver
	)

/obj/item/storage/box/syndie_kit/demolitions_heavy
	starts_with = list(
		/obj/item/syndie/c4explosive/heavy,
		/obj/item/tool/screwdriver
	)

/obj/item/storage/box/syndie_kit/demolitions_super_heavy
	starts_with = list(
		/obj/item/syndie/c4explosive/heavy/super_heavy,
		/obj/item/tool/screwdriver
	)

/obj/item/storage/box/syndie_kit/voidsuit
	starts_with = list(
		/obj/item/clothing/suit/space/void/merc,
		/obj/item/clothing/head/helmet/space/void/merc,
		/obj/item/clothing/shoes/magboots,
		/obj/item/tank/jetpack/oxygen
	)

/obj/item/storage/box/syndie_kit/voidsuit/fire
	starts_with = list(
		/obj/item/clothing/suit/space/void/merc/fire,
		/obj/item/clothing/head/helmet/space/void/merc/fire,
		/obj/item/clothing/shoes/magboots,
		/obj/item/tank/jetpack/oxygen
	)

/obj/item/storage/box/syndie_kit/concussion_grenade
	starts_with = list(
		/obj/item/grenade/concussion = 8
		)

/obj/item/storage/box/syndie_kit/deadliest_game
	starts_with = list(
		/obj/item/beartrap/hunting = 4
		)

/obj/item/storage/box/syndie_kit/viral
	starts_with = list(
		// /obj/item/virusdish/random = 3
		)

/obj/item/storage/secure/briefcase/rifle
	name = "secure briefcase"
	starts_with = list(
		/obj/item/sniper_rifle_part/barrel,
		/obj/item/sniper_rifle_part/stock,
		/obj/item/sniper_rifle_part/trigger_group,
		/obj/item/ammo_casing/a145 = 4
	)

// gasthrower (gun/magnetic/gasthrower) was a ZAS-tied weapon that fired
// canister contents; deleted with ZAS atmos machinery. Flamer briefcase now ships
// just the support gear.
/obj/item/storage/secure/briefcase/flamer
	name = "secure briefcase"
	starts_with = list(
		/obj/item/cell/super,
		/obj/item/stock_parts/capacitor,
		/obj/item/tank/phoron/pressurized = 2
	)

// /obj/item/fuel_assembly and /obj/item/gun/magnetic/fuelrod were part
// of the fusion subsystem (deleted with core_field.dm). Fuelrod briefcase
// remains as a placeholder shell so the uplink listing still resolves but the
// case spawns empty until fusion content is replaced.
/obj/item/storage/secure/briefcase/fuelrod
	name = "heavy briefcase"
	desc = "A heavy, locked briefcase. (Fusion content deprecated under LINDA migration.)"
	starts_with = list(
		/obj/item/tool/screwdriver
	)


CAPABILITIES(/obj/item/storage/secure/briefcase/fuelrod)
	configure(item_combat(force = 12))
	configure(storage(accepts = list(
		/obj/item/cell,
		/obj/item/stock_parts,
		/obj/item/tool/screwdriver)))
