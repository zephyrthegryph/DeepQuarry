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
