// Latent-safe types (containment.md section 4.4): instances may collapse into
// latent entries. Each one's state serializes (the state lint checks its saved
// vars, and dq_state_latent_round_trip round-trips every subtype). Initialize()
// side effects are audited by L2. Rollout order is containment.md section 4.6.
// C10 (containment.md section 4.7): dq_storability_sandbox verifies every
// latent_safe = TRUE declaration below against real mechanical checks instead
// of trusting it by hand. Every latent_safe = FALSE opt-out here also
// declares latent_unsafe_reason() (latent.dm), so the reason a type is
// excluded is a queryable proc on the type itself, not only a floating `//`
// comment above the var assignment -- the comment stays too, since it often
// covers a whole block of related types at once.

// ---- Machine internals (roadmap C6): board and stock parts ----
// Initialize() side effects are cosmetic (random pixel offset) or a static
// read into an instance var (security board networks); nothing registers
// with a subsystem or builds a child eagerly.

// board_type is a nested /datum/frame/frame_types instance built inline
// (`var/board_type = new /datum/frame/frame_types/X`), owned only by this
// board; the frame_type codec (codecs.dm) saves it as a nested blob (or
// passes it through as plain text for the few boards that set it to a
// string instead -- circuitboard.dm's own comment). frame_types' own vars
// (name, frame_size, frame_class, a circuit type path, frame_style,
// x_offset, y_offset, an icon_override resource) are all plain values the
// generic encoder already handles, so it needs no codec of its own.





/// info_links is derived from info (it embeds this paper's ref), so rebuild it.
/obj/item/paper/state_post_apply(list/blob, flags)
	..()
	updateinfolinks()

/// Its recursive move relay (/datum/recursive_move) relays moves of whatever it is stuck to.

/obj/item/paper/sticky/latent_unsafe_reason()
	return "Its recursive move relay (/datum/recursive_move) relays moves of whatever it is stuck to."



/// Its reagent (/datum/reagent/sleevingcure) is commented out in medicine.dm,
/// so creating one runtimes. Left for the medical owner.

/obj/item/reagent_containers/pill/sleevingcure/latent_unsafe_reason()
	return "Its reagent (/datum/reagent/sleevingcure) is commented out in medicine.dm, so creating one runtimes. Left for the medical owner."



/obj/item/ammo_casing/state_codecs()
	return ..() + list("BB" = /datum/state_codec/child)

/// An admin's fax being composed: it refers to the admin, sender and fax machine.

/obj/item/paper/admin/latent_unsafe_reason()
	return "An admin's fax being composed: it refers to the admin, sender and fax machine."

// ---- C5 step 1: what closets hold (starts_with) ----






// Initialize() registers with the world (processing, material services,
// radio, lighting, mob lists): these stay real until that moves to on_materialize().

/obj/item/clothing/suit/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/head/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/shoes/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/under/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/glasses/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/ears/circuitry/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/regen/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/toxinregen/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/stamina/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/ring/buzzer/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/gloves/telekinetic/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/mask/gas/poltergeist/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/mask/ai/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/accessory/collar/shock/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/accessory/bodycam/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/clothing/accessory/dosimeter/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/tool/transforming/altevian/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."


/obj/item/stack/material/supermatter/latent_unsafe_reason()
	return "Initialize() registers with the world (processing, material services, radio, lighting, mob lists): these stay real until that moves to on_materialize()."

// State that doesn't serialize yet (live references: compass labels, HUD
// screens, hoods, spark systems, components that refuse), or material rings whose
// rad_insulation doesn't survive JSON exactly.


/obj/item/clothing/accessory/bracelet/material/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/accessory/ring/material/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/accessory/watch/survival/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/glasses/omnihud/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/gloves/black/bloodletter/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/gloves/boxing/hologlove/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/head/pilot/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/mask/paper/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/shoes/clown_shoes/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/shoes/dry_galoshes/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/shoes/mech_shoes/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/suit/armor/shield/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/suit/space/void/autolok/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/clothing/suit/space/void/zaddat/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."


/obj/item/tool/screwdriver/test_driver/latent_unsafe_reason()
	return "State that doesn't serialize yet (live references: compass labels, HUD screens, hoods, spark systems, components that refuse), or material rings whose rad_insulation doesn't survive JSON exactly."

// ---- C5 step 2: mapped storage ----
// Storage keeps starts_with latent until used (storage.dm), and may itself be
// a latent entry in a closet.


// Their icon or Initialize() reads what they hold, so contents are made eagerly.








/obj/item/storage/fancy





// ---- C5 step 5: pill bottles ----
// A pill bottle is ordinary mapped storage (storage.dm handles the generator
// and materializes before use, open, examine, ...): plain starts_with lines
// of latent-safe pills stay declared. chem_master.dm makes a loaded bottle's
// pills real before it reads .contents. Nothing to opt out here; bottles
// whose Initialize() fills itself directly (dice, benzilate, ...) never set
// starts_with, so the generator is a no-op for them regardless.







// A robot gripper's pockets are a live tool: code reads the one item in
// each pocket every time the gripper is used or its menu is drawn.



// Storage whose Initialize() makes real things that don't serialize (guns,
// radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the
// sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox;
// they stay real until their contents are latent-safe.

/obj/item/stack/cable_coil/random_belt

/obj/item/stack/cable_coil/random_belt/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/backpack/clown/loaded/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/backpack/dufflebag/cratebooze/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/backpack/fluff/stunstaff/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/backpack/messenger/sec/fluff/ivymoomoo/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/backpack/mime/loaded/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."

/obj/item/storage/bag/circuits/all

/obj/item/storage/bag/circuits/all/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."

/obj/item/storage/bag/circuits/basic

/obj/item/storage/bag/circuits/basic/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/arithmetic/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/converter/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/input/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/logic/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/manipulation/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/memory/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/output/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/power/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/reagents/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/smart/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/time/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/transfer/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bag/circuits/mini/trig/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/bagoplanets/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/ambrosia/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/ambrosiadeus/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/anomaly/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/backup_kit/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/bourbon/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/buns/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/camerabug/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/capguntoy/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/casino/costume_sexyclown/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/casino/foamcrossbow/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/custardcream/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/donkpockets/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/donut/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/explorerkeys/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/fitness_trainer/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/fluff/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/fortune_teller/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/cowboy/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/firefighter/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/horrorcop/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/lumberjack/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/marine/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/masked_killer/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/professional/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."


/obj/item/storage/box/halloween/vampirehunter/latent_unsafe_reason()
	return "Storage whose Initialize() makes real things that don't serialize (guns, radios, PDAs, circuits, food with seeds...), or with Initialize() bugs the sandbox shows. Found by dq_state_latent_round_trip and dq_lifecycle_sandbox; they stay real until their contents are latent-safe."

// starts_with holds an inline new-with-vars literal (a clothing item with
// starting_accessories set), which the generic list encoder can't serialize.

/obj/item/storage/box/halloween/whiteout/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/ids/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/injectors/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/jaffacake/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/old_syringes/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/rhubarbcustard/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/saucer/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/seccarts/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/shrimpsandbananas/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/sinpockets/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/smokes/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/snakesnackbox/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/stylist/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/survival/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."

/obj/item/storage/box/syndicate

/obj/item/storage/box/syndicate/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/chameleon/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/demolitions/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/demolitions_heavy/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/demolitions_super_heavy/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/g9mm/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/space/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/spy/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/voidsuit/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/weapon_cells/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/winegum/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/wings/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/wormcan/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/yoga_teacher/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/briefcase/target_toy/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/fancy/crackers/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/fancy/heartbox/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/internal/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mre/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/dessert/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/menu4/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/menu5/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/menu7/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/menu8/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/menu9/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/mrebag/side/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/pouch/holster/full_stunrevolver/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/pouch/holster/full_taser/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/flamer/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nerd_pack_cmo/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nerd_pack_med/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nsfw_pack/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nsfw_pack_hos/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nsfw_pack_hybrid/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/secure/briefcase/nsfw_pack_hybrid_combat/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/emergency/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/cat/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/cti/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/heart/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/mars/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/nt/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/nymph/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/lunchbox/syndicate/filled/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/stack/cable_coil/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/belt/utility/chief/full/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/PDAs/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/electrical/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/metalfoam/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/pill_bottle/sleevingcure/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/backpack/dufflebag/cratedrills/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/backpack/sport/hyd/catchemall/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/belt/utility/alien/full/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/belt/utility/spicyfull/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/dosimeter/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/paranormal_investigator/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/private_investigator/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/syndie_kit/imp_uplink/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/box/teargas/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."


/obj/item/storage/toolbox/syndicate/powertools/latent_unsafe_reason()
	return "starts_with holds an inline new-with-vars literal (a clothing item with starting_accessories set), which the generic list encoder can't serialize."

// ---- C5 step 4: ammo ----
// Magazines keep their initial rounds as latent_rounds while on a turf or in
// a latent holder (ammunition.dm), and may be entries in closets and storage.


// Ticks in SSobj from Initialize() to Destroy(): never latent (containment.md
// section 4.4, "anything that processes").

/obj/item/ammo_magazine/smart/latent_unsafe_reason()
	return "Ticks in SSobj from Initialize() to Destroy(): never latent (containment.md section 4.4, \"anything that processes\")."

// ---- C5 step 6: PDAs, radios and headsets ----
// L2 and L3 already moved their world registrations into on_materialize()
// (state.md section 5); this is only the serializer round trip.


// Its Initialize() builds a real circuitboard child eagerly (wall-mounted,
// low count, not the bulk case this step targets); leave it for its owner.

/obj/item/radio/intercom/latent_unsafe_reason()
	return "Its Initialize() builds a real circuitboard child eagerly (wall-mounted, low count, not the bulk case this step targets); leave it for its owner."


// Its Initialize() builds a hidden uplink child with its own timers
// (uplink.dm); a rare, antag-only preset, not the bulk case this step targets.

/obj/item/radio/uplink/latent_unsafe_reason()
	return "Its Initialize() builds a hidden uplink child with its own timers (uplink.dm); a rare, antag-only preset, not the bulk case this step targets."


/obj/item/radio/headset/uplink/latent_unsafe_reason()
	return "Its Initialize() builds a hidden uplink child with its own timers (uplink.dm); a rare, antag-only preset, not the bulk case this step targets."

// Mapped pre-linked to a specific telecomms machine; the link is set up once
// at roundstart (its after_init() pass) and would need to be redone on materialize.

/obj/item/radio/bluespacehandset/linked/tether_prelinked/latent_unsafe_reason()
	return "Mapped pre-linked to a specific telecomms machine; the link is set up once at roundstart (its after_init() pass) and would need to be redone on materialize."


/obj/item/radio/bluespacehandset/linked/talon_prelinked/latent_unsafe_reason()
	return "Mapped pre-linked to a specific telecomms machine; the link is set up once at roundstart (its after_init() pass) and would need to be redone on materialize."

/obj/item/radio/bluespacehandset/linked/relicbase_prelinked

/obj/item/radio/bluespacehandset/linked/relicbase_prelinked/latent_unsafe_reason()
	return "Mapped pre-linked to a specific telecomms machine; the link is set up once at roundstart (its after_init() pass) and would need to be redone on materialize."


/obj/item/radio/bluespacehandset/linked/southerncross_prelinked/latent_unsafe_reason()
	return "Mapped pre-linked to a specific telecomms machine; the link is set up once at roundstart (its after_init() pass) and would need to be redone on materialize."


/obj/item/radio/bluespacehandset/linked/cryogaia_prelinked/latent_unsafe_reason()
	return "Mapped pre-linked to a specific telecomms machine; the link is set up once at roundstart (its after_init() pass) and would need to be redone on materialize."

/datum/type_metadata_registry/register_defaults()
	register(/obj/item/organ, TYPE_META_SLOT_HOOKS, TRUE)
	register(/obj/machinery, TYPE_META_LATENT_CONTENTS, TRUE)
	register(/obj/structure/closet, TYPE_META_LATENT_CONTENTS, TRUE)
	register(/obj/item/storage, TYPE_META_LATENT_CONTENTS, TRUE)
	register(/obj/item/circuitboard, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/stock_parts, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/smes_coil, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/bluespace_crystal, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/paper, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/paper/sticky, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/pen, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/reagent_containers/pill, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/reagent_containers/pill/sleevingcure, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/light, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/ammo_casing, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/paper/admin, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/tool, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/trash, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/toy, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/stack, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/clothing/suit/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/head/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/shoes/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/under/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/glasses/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/ears/circuitry, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/regen, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/toxinregen, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/stamina, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/ring/buzzer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/telekinetic, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/mask/gas/poltergeist, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/mask/ai, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/collar/shock, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/bodycam, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/dosimeter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/tool/transforming/altevian, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/stack/material/supermatter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/bracelet/material, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/ring/material, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/accessory/watch/survival, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/glasses/omnihud, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/black/bloodletter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/gloves/boxing/hologlove, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/head/pilot, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/mask/paper, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/shoes/clown_shoes, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/shoes/dry_galoshes, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/shoes/mech_shoes, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/suit/armor/shield, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/suit/space/void/autolok, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/clothing/suit/space/void/zaddat, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/tool/screwdriver/test_driver, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/storage/bag/santabag, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/bag/trash, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/donut, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/fancy/chewables/tobacco/nico, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/tgmc_mre, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/wings, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/wormcan, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/fancy, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/laundry_basket, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/lockbox/vials, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/mre, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/mrebag, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/pouch/baton, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/pouch/flares, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/pouch/holster, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/sample_container, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/trinketbox, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/wallet, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/internal/gripper, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/box/remote_scene_tools, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/storage/backpack/sport/hyd/catchemall, TYPE_META_LATENT_CONTENTS, FALSE)
	register(/obj/item/stack/cable_coil/random_belt, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/clown/loaded, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/dufflebag/cratebooze, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/fluff/stunstaff, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/messenger/sec/fluff/ivymoomoo, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/mime/loaded, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/all, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/basic, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/arithmetic, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/converter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/input, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/logic, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/manipulation, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/memory, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/output, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/power, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/reagents, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/smart, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/time, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/transfer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bag/circuits/mini/trig, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/bagoplanets, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/ambrosia, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/ambrosiadeus, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/anomaly, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/backup_kit, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/bourbon, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/buns, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/camerabug, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/capguntoy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/casino/costume_sexyclown, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/casino/foamcrossbow, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/custardcream, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/donkpockets, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/donut, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/explorerkeys, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/fitness_trainer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/fluff, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/fortune_teller, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/cowboy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/firefighter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/horrorcop, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/lumberjack, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/marine, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/masked_killer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/professional, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/vampirehunter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/halloween/whiteout, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/ids, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/injectors, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/jaffacake, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/old_syringes, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/rhubarbcustard, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/saucer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/seccarts, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/shrimpsandbananas, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/sinpockets, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/smokes, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/snakesnackbox, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/stylist, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/survival, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndicate, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/chameleon, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/demolitions, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/demolitions_heavy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/demolitions_super_heavy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/g9mm, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/space, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/spy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/voidsuit, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/weapon_cells, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/winegum, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/wings, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/wormcan, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/yoga_teacher, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/briefcase/target_toy, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/fancy/crackers, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/fancy/heartbox, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/internal, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mre, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/dessert, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/menu4, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/menu5, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/menu7, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/menu8, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/menu9, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/mrebag/side, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/pouch/holster/full_stunrevolver, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/pouch/holster/full_taser, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/flamer, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nerd_pack_cmo, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nerd_pack_med, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nsfw_pack, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nsfw_pack_hos, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nsfw_pack_hybrid, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/secure/briefcase/nsfw_pack_hybrid_combat, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/emergency, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/cat/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/cti/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/heart/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/mars/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/nt/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/nymph/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/lunchbox/syndicate/filled, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/stack/cable_coil, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/belt/utility/chief/full, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/PDAs, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/electrical, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/metalfoam, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/pill_bottle/sleevingcure, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/dufflebag/cratedrills, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/backpack/sport/hyd/catchemall, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/belt/utility/alien/full, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/belt/utility/spicyfull, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/dosimeter, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/paranormal_investigator, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/private_investigator, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/syndie_kit/imp_uplink, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/box/teargas, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/storage/toolbox/syndicate/powertools, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/ammo_magazine, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/ammo_magazine/smart, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/radio/intercom, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/card/id, TYPE_META_LATENT_SAFE, TRUE)
	register(/obj/item/radio/uplink, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/headset/uplink, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/bluespacehandset/linked/tether_prelinked, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/bluespacehandset/linked/talon_prelinked, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/bluespacehandset/linked/relicbase_prelinked, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/bluespacehandset/linked/southerncross_prelinked, TYPE_META_LATENT_SAFE, FALSE)
	register(/obj/item/radio/bluespacehandset/linked/cryogaia_prelinked, TYPE_META_LATENT_SAFE, FALSE)
