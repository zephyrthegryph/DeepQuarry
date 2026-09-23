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
