// Latent-safe types (containment.md section 4.4): instances may collapse into
// latent entries. Each one's state serializes (the state lint checks its saved
// vars, and dq_state_latent_round_trip round-trips every subtype). Initialize()
// side effects are audited by L2. Rollout order is containment.md section 4.6.

/obj/item/paper
	latent_safe = TRUE

/// info_links is derived from info (it embeds this paper's ref), so rebuild it.
/obj/item/paper/state_post_apply(list/blob, flags)
	..()
	updateinfolinks()

/// Its recursive_move component relays moves of whatever it is stuck to.
/obj/item/paper/sticky
	latent_safe = FALSE

/obj/item/pen
	latent_safe = TRUE

/obj/item/reagent_containers/pill
	latent_safe = TRUE

/// Its reagent (/datum/reagent/sleevingcure) is commented out in medicine.dm,
/// so creating one runtimes. Left for the medical owner.
/obj/item/reagent_containers/pill/sleevingcure
	latent_safe = FALSE

/obj/item/light
	latent_safe = TRUE

/obj/item/ammo_casing
	latent_safe = TRUE

/obj/item/ammo_casing/state_codecs()
	return ..() + list("BB" = /datum/state_codec/child)

/// An admin's fax being composed: it refers to the admin, sender and fax machine.
/obj/item/paper/admin
	latent_safe = FALSE

// ---- C5 step 1: what closets hold (starts_with) ----

/obj/item/clothing
	latent_safe = TRUE

/obj/item/tool
	latent_safe = TRUE

/obj/item/trash
	latent_safe = TRUE

/obj/item/toy
	latent_safe = TRUE

/obj/item/stack
	latent_safe = TRUE

// Initialize() registers with the world (processing, material services,
// radio, lighting, mob lists): these stay real until that moves to on_materialize().
/obj/item/clothing/suit/circuitry
	latent_safe = FALSE

/obj/item/clothing/head/circuitry
	latent_safe = FALSE

/obj/item/clothing/shoes/circuitry
	latent_safe = FALSE

/obj/item/clothing/gloves/circuitry
	latent_safe = FALSE

/obj/item/clothing/under/circuitry
	latent_safe = FALSE

/obj/item/clothing/glasses/circuitry
	latent_safe = FALSE

/obj/item/clothing/ears/circuitry
	latent_safe = FALSE

/obj/item/clothing/gloves/regen
	latent_safe = FALSE

/obj/item/clothing/gloves/toxinregen
	latent_safe = FALSE

/obj/item/clothing/gloves/stamina
	latent_safe = FALSE

/obj/item/clothing/gloves/ring/buzzer
	latent_safe = FALSE

/obj/item/clothing/gloves/telekinetic
	latent_safe = FALSE

/obj/item/clothing/mask/gas/poltergeist
	latent_safe = FALSE

/obj/item/clothing/mask/ai
	latent_safe = FALSE

/obj/item/clothing/accessory/collar/shock
	latent_safe = FALSE

/obj/item/clothing/accessory/bodycam
	latent_safe = FALSE

/obj/item/clothing/accessory/dosimeter
	latent_safe = FALSE

/obj/item/tool/transforming/altevian
	latent_safe = FALSE

/obj/item/stack/material/supermatter
	latent_safe = FALSE

// State that doesn't serialize yet (live references: compass labels, HUD
// screens, hoods, spark systems, components that refuse), or material rings whose
// rad_insulation doesn't survive JSON exactly.

/obj/item/clothing/accessory/bracelet/material
	latent_safe = FALSE

/obj/item/clothing/accessory/ring/material
	latent_safe = FALSE

/obj/item/clothing/accessory/watch/survival
	latent_safe = FALSE

/obj/item/clothing/glasses/omnihud
	latent_safe = FALSE

/obj/item/clothing/gloves/black/bloodletter
	latent_safe = FALSE

/obj/item/clothing/gloves/boxing/hologlove
	latent_safe = FALSE

/obj/item/clothing/head/pilot
	latent_safe = FALSE

/obj/item/clothing/mask/paper
	latent_safe = FALSE

/obj/item/clothing/shoes/clown_shoes
	latent_safe = FALSE

/obj/item/clothing/shoes/dry_galoshes
	latent_safe = FALSE

/obj/item/clothing/shoes/mech_shoes
	latent_safe = FALSE

/obj/item/clothing/suit/armor/shield
	latent_safe = FALSE

/obj/item/clothing/suit/space/void/autolok
	latent_safe = FALSE

/obj/item/clothing/suit/space/void/zaddat
	latent_safe = FALSE

/obj/item/tool/screwdriver/test_driver
	latent_safe = FALSE

// ---- C5 step 2: mapped storage ----
// Storage keeps starts_with latent until used (storage.dm), and may itself be
// a latent entry in a closet.

/obj/item/storage
	latent_safe = TRUE

// Their icon or Initialize() reads what they hold, so contents are made eagerly.

/obj/item/storage/bag/santabag
	latent_contents = FALSE

/obj/item/storage/bag/trash
	latent_contents = FALSE

/obj/item/storage/box/donut
	latent_contents = FALSE

/obj/item/storage/box/fancy/chewables/tobacco/nico
	latent_contents = FALSE

/obj/item/storage/box/tgmc_mre
	latent_contents = FALSE

/obj/item/storage/box/wings
	latent_contents = FALSE

/obj/item/storage/box/wormcan
	latent_contents = FALSE

/obj/item/storage/fancy
	latent_contents = FALSE

/obj/item/storage/laundry_basket
	latent_contents = FALSE

/obj/item/storage/lockbox/vials
	latent_contents = FALSE

/obj/item/storage/mre
	latent_contents = FALSE

/obj/item/storage/mrebag
	latent_contents = FALSE

// ---- C5 step 5: pill bottles ----
// A pill bottle is ordinary mapped storage (storage.dm handles the generator
// and materializes before use, open, examine, ...): plain starts_with lines
// of latent-safe pills stay declared. chem_master.dm makes a loaded bottle's
// pills real before it reads .contents. Nothing to opt out here; bottles
// whose Initialize() fills itself directly (dice, benzilate, ...) never set
// starts_with, so the generator is a no-op for them regardless.

/obj/item/storage/pouch/baton
	latent_contents = FALSE

/obj/item/storage/pouch/flares
	latent_contents = FALSE

/obj/item/storage/pouch/holster
	latent_contents = FALSE

/obj/item/storage/sample_container
	latent_contents = FALSE

/obj/item/storage/trinketbox
	latent_contents = FALSE

/obj/item/storage/wallet
	latent_contents = FALSE

/obj/item/storage/box/remote_scene_tools
	latent_contents = FALSE

/obj/item/storage/backpack/sport/hyd/catchemall
	latent_contents = FALSE

// Storage whose Initialize() makes real things that don't serialize (guns,
// radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the
// sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox;
// they stay real until their contents are latent-safe.

/obj/item/stack/cable_coil/random_belt
	latent_safe = FALSE

/obj/item/storage/backpack/clown/loaded
	latent_safe = FALSE

/obj/item/storage/backpack/dufflebag/cratebooze
	latent_safe = FALSE

/obj/item/storage/backpack/fluff/stunstaff
	latent_safe = FALSE

/obj/item/storage/backpack/messenger/sec/fluff/ivymoomoo
	latent_safe = FALSE

/obj/item/storage/backpack/mime/loaded
	latent_safe = FALSE

/obj/item/storage/bag/circuits/all
	latent_safe = FALSE

/obj/item/storage/bag/circuits/basic
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/arithmetic
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/converter
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/input
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/logic
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/manipulation
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/memory
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/output
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/power
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/reagents
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/smart
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/time
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/transfer
	latent_safe = FALSE

/obj/item/storage/bag/circuits/mini/trig
	latent_safe = FALSE

/obj/item/storage/bagoplanets
	latent_safe = FALSE

/obj/item/storage/box/ambrosia
	latent_safe = FALSE

/obj/item/storage/box/ambrosiadeus
	latent_safe = FALSE

/obj/item/storage/box/anomaly
	latent_safe = FALSE

/obj/item/storage/box/backup_kit
	latent_safe = FALSE

/obj/item/storage/box/bourbon
	latent_safe = FALSE

/obj/item/storage/box/buns
	latent_safe = FALSE

/obj/item/storage/box/camerabug
	latent_safe = FALSE

/obj/item/storage/box/capguntoy
	latent_safe = FALSE

/obj/item/storage/box/casino/costume_sexyclown
	latent_safe = FALSE

/obj/item/storage/box/casino/foamcrossbow
	latent_safe = FALSE

/obj/item/storage/box/custardcream
	latent_safe = FALSE

/obj/item/storage/box/donkpockets
	latent_safe = FALSE

/obj/item/storage/box/donut
	latent_safe = FALSE

/obj/item/storage/box/explorerkeys
	latent_safe = FALSE

/obj/item/storage/box/fitness_trainer
	latent_safe = FALSE

/obj/item/storage/box/fluff
	latent_safe = FALSE

/obj/item/storage/box/fortune_teller
	latent_safe = FALSE

/obj/item/storage/box/halloween/cowboy
	latent_safe = FALSE

/obj/item/storage/box/halloween/firefighter
	latent_safe = FALSE

/obj/item/storage/box/halloween/horrorcop
	latent_safe = FALSE

/obj/item/storage/box/halloween/lumberjack
	latent_safe = FALSE

/obj/item/storage/box/halloween/marine
	latent_safe = FALSE

/obj/item/storage/box/halloween/masked_killer
	latent_safe = FALSE

/obj/item/storage/box/halloween/professional
	latent_safe = FALSE

/obj/item/storage/box/halloween/vampirehunter
	latent_safe = FALSE

/obj/item/storage/box/ids
	latent_safe = FALSE

/obj/item/storage/box/injectors
	latent_safe = FALSE

/obj/item/storage/box/jaffacake
	latent_safe = FALSE

/obj/item/storage/box/old_syringes
	latent_safe = FALSE

/obj/item/storage/box/rhubarbcustard
	latent_safe = FALSE

/obj/item/storage/box/saucer
	latent_safe = FALSE

/obj/item/storage/box/seccarts
	latent_safe = FALSE

/obj/item/storage/box/shrimpsandbananas
	latent_safe = FALSE

/obj/item/storage/box/sinpockets
	latent_safe = FALSE

/obj/item/storage/box/smokes
	latent_safe = FALSE

/obj/item/storage/box/snakesnackbox
	latent_safe = FALSE

/obj/item/storage/box/stylist
	latent_safe = FALSE

/obj/item/storage/box/survival
	latent_safe = FALSE

/obj/item/storage/box/syndicate
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/chameleon
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/demolitions
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/demolitions_heavy
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/demolitions_super_heavy
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/g9mm
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/space
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/spy
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/voidsuit
	latent_safe = FALSE

/obj/item/storage/box/weapon_cells
	latent_safe = FALSE

/obj/item/storage/box/winegum
	latent_safe = FALSE

/obj/item/storage/box/wings
	latent_safe = FALSE

/obj/item/storage/box/wormcan
	latent_safe = FALSE

/obj/item/storage/box/yoga_teacher
	latent_safe = FALSE

/obj/item/storage/briefcase/target_toy
	latent_safe = FALSE

/obj/item/storage/fancy/crackers
	latent_safe = FALSE

/obj/item/storage/fancy/heartbox
	latent_safe = FALSE

/obj/item/storage/internal
	latent_safe = FALSE

/obj/item/storage/mre
	latent_safe = FALSE

/obj/item/storage/mrebag/dessert
	latent_safe = FALSE

/obj/item/storage/mrebag/menu4
	latent_safe = FALSE

/obj/item/storage/mrebag/menu5
	latent_safe = FALSE

/obj/item/storage/mrebag/menu7
	latent_safe = FALSE

/obj/item/storage/mrebag/menu8
	latent_safe = FALSE

/obj/item/storage/mrebag/menu9
	latent_safe = FALSE

/obj/item/storage/mrebag/side
	latent_safe = FALSE

/obj/item/storage/pouch/holster/full_stunrevolver
	latent_safe = FALSE

/obj/item/storage/pouch/holster/full_taser
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/flamer
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nerd_pack_cmo
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nerd_pack_med
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nsfw_pack
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nsfw_pack_hos
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nsfw_pack_hybrid
	latent_safe = FALSE

/obj/item/storage/secure/briefcase/nsfw_pack_hybrid_combat
	latent_safe = FALSE

/obj/item/storage/toolbox/emergency
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/cat/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/cti/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/heart/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/mars/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/nt/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/nymph/filled
	latent_safe = FALSE

/obj/item/storage/toolbox/lunchbox/syndicate/filled
	latent_safe = FALSE

/obj/item/stack/cable_coil
	latent_safe = FALSE

/obj/item/storage/belt/utility/chief/full
	latent_safe = FALSE

/obj/item/storage/box/PDAs
	latent_safe = FALSE

/obj/item/storage/toolbox/electrical
	latent_safe = FALSE

/obj/item/storage/box/metalfoam
	latent_safe = FALSE

/obj/item/storage/pill_bottle/sleevingcure
	latent_safe = FALSE

/obj/item/storage/backpack/dufflebag/cratedrills
	latent_safe = FALSE

/obj/item/storage/backpack/sport/hyd/catchemall
	latent_safe = FALSE

/obj/item/storage/belt/utility/alien/full
	latent_safe = FALSE

/obj/item/storage/belt/utility/spicyfull
	latent_safe = FALSE

/obj/item/storage/box/dosimeter
	latent_safe = FALSE

/obj/item/storage/box/paranormal_investigator
	latent_safe = FALSE

/obj/item/storage/box/private_investigator
	latent_safe = FALSE

/obj/item/storage/box/syndie_kit/imp_uplink
	latent_safe = FALSE

/obj/item/storage/box/teargas
	latent_safe = FALSE

/obj/item/storage/toolbox/syndicate/powertools
	latent_safe = FALSE

// ---- C5 step 4: ammo ----
// Magazines keep their initial rounds as latent_rounds while on a turf or in
// a latent holder (ammunition.dm), and may be entries in closets and storage.

/obj/item/ammo_magazine
	latent_safe = TRUE
