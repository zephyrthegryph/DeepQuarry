////////////////////////////////////////////////////////////////////////////////
/// HYPOSPRAY
////////////////////////////////////////////////////////////////////////////////

/obj/item/reagent_containers/hypospray
	name = "hypospray"
	desc = "The DeForest Medical Corporation hypospray is a sterile, air-needle autoinjector for rapid administration of drugs to patients."
	icon = 'icons/obj/syringe.dmi'
	icon_state = "hypo"
	item_state = "hypo"
	amount_per_transfer_from_this = 5
	unacidable = TRUE
	volume = 30
	max_transfer_amount = null
	/// Poured into until it is spent (an autoinjector shuts when it is used).
	var/open_at_start = TRUE
	slot_flags = SLOT_BELT
	drop_sound = SFX_ITEMS_DROP_GUN
	pickup_sound = SFX_ITEMS_PICKUP_GUN
	preserve_item = 1
	var/filled = 0
	var/list/filled_reagents
	var/hyposound	// What sound do we play on use?

/obj/item/reagent_containers/hypospray/Initialize(mapload)
	. = ..()
	if(filled)
		if(filled_reagents)
			for(var/r in filled_reagents)
				reagents.add_reagent(r, LAZYACCESS(filled_reagents, r))

// A hypospray is a holder of its volume that is poured into like any open container, and that puts one transfer into the blood of a person by a click
// (injector(), code/library/reagents/injector.dm): at once, or after three seconds when the hypospray is the prototype or the one injected is awake and
// resists in combat mode. Armour does not stop it. The sound, the transfer and the log are do_injection(), which a type may extend.
CAPABILITIES(/obj/item/reagent_containers/hypospray)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		lid = TRUE,
		lid_visible = FALSE,
		starts_open = nameof(open_at_start),
		transfer_default = nameof(amount_per_transfer_from_this))
	injector(slow = nameof(prototype))
	extend("injector.inject", then(PROC_REF(injected)))
	extend("injector.inject_slowly", then(PROC_REF(injected)))

/// The injection: the transfer, the sound and the log.
/obj/item/reagent_containers/hypospray/proc/injected(datum/act/op/A)
	return do_injection(A.target, A.actor) ? OP_OK : OP_FAILED

// This does the actual injection and transfer.
/obj/item/reagent_containers/hypospray/proc/do_injection(mob/living/carbon/human/H, mob/living/user)
	if(!istype(H) || !istype(user))
		return FALSE

	user.setClickCooldown(DEFAULT_QUICK_COOLDOWN)
	balloon_alert(user, "injected \the [H] with \the [src]")
	balloon_alert(H, "you feel a tiny prick!")

	if(hyposound)
		playsound(src, hyposound, 25)

	if(H.reagents)
		var/contained = reagentlist()
		var/trans = reagents.trans_to_mob(H, amount_per_transfer_from_this, CHEM_BLOOD)
		add_attack_logs(user,H,"Injected with [src.name] containing [contained], trasferred [trans] units")
		to_chat(user, span_notice("[trans] units injected. [reagents.total_volume] units remaining in \the [src]."))
		return TRUE
	return FALSE

//A vial-loaded hypospray. Cartridge-based!
/obj/item/reagent_containers/hypospray/vial
	name = "advanced hypospray"
	icon_state = "advhypo"
	desc = "A new development from DeForest Medical, this new hypospray takes 30-unit vials as the drug supply for easy swapping."
	var/obj/item/reagent_containers/glass/beaker/vial/loaded_vial //Wow, what a name.
	volume = 0

// Comes with an empty vial.

/obj/item/reagent_containers/hypospray/vial/Initialize(mapload)
	. = ..()
	icon_state = "[initial(icon_state)]" // ALLOW(decl): discards a map-edited icon_state
	volume = loaded_vial.volume
	reagents.maximum_volume = loaded_vial.reagents.maximum_volume

// The vial hypospray takes a 30-unit vial for its drug supply: a vial is loaded in three seconds (once), and an empty hand takes it out when the hypospray
// is in the other hand. What the vial held is the hypospray's while it is in.
CAPABILITIES(/obj/item/reagent_containers/hypospray/vial)
	owns_one(nameof(loaded_vial), /obj/item/reagent_containers/glass/beaker/vial, starts = /obj/item/reagent_containers/glass/beaker/vial)
	configure(injector(slow = nameof(prototype), vial = nameof(loaded_vial)))
	op("load", item(/obj/item/reagent_containers/glass/beaker/vial), priority(OP_PRIORITY_PART + 5), label("Load the vial"),
		needs(req_is(nameof(loaded_vial), FALSE, because = MSG(hypo/has_vial))),
		begins(MSG(hypo/begin_load)), wait(3 SECONDS), then(PROC_REF(vial_loaded)))
	extend("injector.unload", then(PROC_REF(vial_unloaded)))

MSG_DEF_SELF(hypo/has_vial, "It already has a vial.")
MSG_DEF(hypo/begin_load, "You begin loading %I% into %T%.", "%U% begins loading %I% into %T%.")
MSG_DEF(hypo/loaded, "You load %I% into %T%.", "%U% has loaded %I% into %T%.")

/// The empty hand takes the vial out: what was in it goes back.
/obj/item/reagent_containers/hypospray/vial/proc/vial_unloaded(datum/act/op/A)
	var/mob/user = A.actor
	if(!loaded_vial)
		return OP_REFUSED
	reagents.trans_to_holder(loaded_vial.reagents, volume)
	reagents.maximum_volume = 0
	user.put_in_hands(loaded_vial)
	rel_take(src, nameof(loaded_vial))
	balloon_alert(user, "vial removed from \the [src]")
	play_sfx(src, SFX_WEAPONS_FLIPBLADE)
	return OP_OK

/// The look (the draw sweep: from its template).
/obj/item/reagent_containers/hypospray/vial/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][loaded_vial ? "" : "_empty"]")

/// The vial goes in (the wait is over): its contents are the hypospray's.
/obj/item/reagent_containers/hypospray/vial/proc/vial_loaded(datum/act/op/A)
	var/mob/user = A.actor
	var/obj/item/reagent_containers/glass/beaker/vial/W = A.held
	if(loaded_vial || !(W in user))
		return OP_REFUSED
	if(W.is_open_container())
		cap_key_set(W, REAGENT_CONTAINER_LID_OPEN, FALSE)
	if(!move_into(src, nameof(src.loaded_vial), W, user))
		return OP_REFUSED
	reagents.maximum_volume = loaded_vial.reagents.maximum_volume
	loaded_vial.reagents.trans_to_holder(reagents,volume)
	balloon_alert_visible("[user] has loaded [W] into \the [src].", "loaded [W] into \the [src].")
	play_sfx(src, SFX_WEAPONS_EMPTY)
	return OP_OK

/obj/item/reagent_containers/hypospray/autoinjector
	name = "autoinjector"
	desc = "A rapid and safe way to administer small amounts of drugs by untrained or trained personnel."
	icon_state = "blue"
	item_state = "blue"
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	amount_per_transfer_from_this = 5
	volume = 5
	filled = 1
	filled_reagents = list(REAGENT_ID_INAPROVALINE = 5)
	preserve_item = 0
	hyposound = SFX_EFFECTS_HYPOSPRAY

/obj/item/reagent_containers/hypospray/autoinjector/empty
	filled = 0

/obj/item/reagent_containers/hypospray/autoinjector/used/Initialize(mapload)
	. = ..()
	cap_key_set(src, REAGENT_CONTAINER_LID_OPEN, FALSE)

/// A used injector shows spent, whatever it still holds.
/obj/item/reagent_containers/hypospray/autoinjector/used/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)]0")

/obj/item/reagent_containers/hypospray/autoinjector/do_injection(mob/living/carbon/human/H, mob/living/user)
	. = ..()
	if(.) // Will occur if successfully injected.
		cap_key_set(src, REAGENT_CONTAINER_LID_OPEN, FALSE)

/// Appearance reader: TRUE while the autoinjector holds reagents.
/obj/item/reagent_containers/hypospray/autoinjector/proc/appearance_filled()
	return reagents?.total_volume > 0 ? TRUE : FALSE

/// The look (the draw sweep: from its template).
/obj/item/reagent_containers/hypospray/autoinjector/draw(datum/look/look)
	..()
	look.watch(reagents)
	look.state("[initial(icon_state)][appearance_filled() ? "1" : "0"]")

/obj/item/reagent_containers/hypospray/autoinjector/examine(mob/user)
	. = ..()
	if(reagents && reagents.reagent_list.len)
		. += span_notice("It is currently loaded.")
	else
		. += span_notice("It is spent.")


/obj/item/reagent_containers/hypospray/autoinjector/detox
	name = "autoinjector (antitox)"
	icon_state = "green"
	filled_reagents = list(REAGENT_ID_ANTITOXIN = 5)

//Special autoinjectors, while having potent chems like the 15u ones, the chems are usually potent enough that 5u is enough
/obj/item/reagent_containers/hypospray/autoinjector/bonemed
	name = "bone repair injector"
	desc = "A rapid and safe way to administer small amounts of drugs by untrained or trained personnel. This one excels at treating damage to bones."
	filled_reagents = list(REAGENT_ID_OSTEODAXON = 5)

/obj/item/reagent_containers/hypospray/autoinjector/clonemed
	name = "clone injector"
	desc = "A rapid and safe way to administer small amounts of drugs by untrained or trained personnel. This one excels at treating genetic damage."
	filled_reagents = list(REAGENT_ID_REZADONE = 5)

/obj/item/reagent_containers/hypospray/autoinjector/allergen
	name = "AllergyPen"
	desc = "An autoinjector designed for use during an allergic reaction or anaphylaxis. The user should immediately seek medical support after use, for additional monitoring and aid."
	icon_state = "allergy"
	item_state = "allergy"

// These have a 15u capacity, somewhat higher tech level, and generally more useful chems, but are otherwise the same as the regular autoinjectors.
/obj/item/reagent_containers/hypospray/autoinjector/biginjector
	name = "empty hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity."
	icon_state = "autoinjector"
	amount_per_transfer_from_this = 15
	volume = 15
	filled_reagents = list(REAGENT_ID_INAPROVALINE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/empty //for the autolathe
	name = "large autoinjector"
	filled = 0

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/brute
	name = "trauma hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This one is made to be used on victims of \
	moderate blunt trauma."
	filled_reagents = list(REAGENT_ID_BICARIDINE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/burn
	name = "burn hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This one is made to be used on burn victims, \
	featuring an optimized chemical mixture to allow for rapid healing."
	filled_reagents = list(REAGENT_ID_KELOTANE = 7.5, REAGENT_ID_DERMALINE = 7.5)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/toxin
	name = "toxin hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This one is made to counteract toxins."
	filled_reagents = list(REAGENT_ID_ANTITOXIN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/oxy
	name = "oxy hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This one is made to counteract oxygen \
	deprivation."
	filled_reagents = list(REAGENT_ID_DEXALINP = 10, REAGENT_ID_TRICORDRAZINE = 5)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/purity
	name = "purity hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This variant excels at \
	resolving viruses, infections, radiation, and genetic maladies."
	filled_reagents = list(REAGENT_ID_SPACEACILLIN = 4, REAGENT_ID_ARITHRAZINE = 5, REAGENT_ID_PRUSSIANBLUE = 5, REAGENT_ID_RYETALYN = 1)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/pain
	name = "pain hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This one contains potent painkillers."
	filled_reagents = list(REAGENT_ID_TRAMADOL = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/organ
	name = "organ hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  Organ damage is resolved by this variant."
	filled_reagents = list(REAGENT_ID_ALKYSINE = 3, REAGENT_ID_IMIDAZOLINE = 2, REAGENT_ID_PERIDAXON = 10)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/combat
	name = "combat hypo"
	desc = "A refined version of the standard autoinjector, allowing greater capacity.  This is a more dangerous and potentially \
	addictive hypo compared to others, as it contains a potent cocktail of various chemicals to optimize the recipient's combat \
	ability."
	filled_reagents = list(REAGENT_ID_BICARIDINE = 3, REAGENT_ID_KELOTANE = 1.5, REAGENT_ID_DERMALINE = 1.5, REAGENT_ID_OXYCODONE = 3, REAGENT_ID_HYPERZINE = 3, REAGENT_ID_TRICORDRAZINE = 3)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting
	name = "clotting agent"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. This variant excels at treating bleeding wounds and internal bleeding."
	filled_reagents = list(REAGENT_ID_INAPROVALINE = 5, REAGENT_ID_MYELAMINE = 10)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/glucose
	name = "glucose hypo"
	desc = "A hypoinjector filled with glucose, used for critically malnourished patients and voidsuited workers."
	filled_reagents = list(REAGENT_ID_GLUCOSE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/stimm
	name = "stimm injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one is filled with a home-made stimulant, with some serious side-effects."
	filled_reagents = list(REAGENT_ID_STIMM = 10) // More than 10u will OD.

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/expired
	name = "expired injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one has had its contents expire a long time ago, using it now will probably make someone sick, or worse."
	filled_reagents = list(REAGENT_ID_EXPIREDMEDICINE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/soporific
	name = "soporific injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one is sometimes used by orderlies, as it has soporifics, which make someone tired and fall asleep."
	filled_reagents = list(REAGENT_ID_STOXIN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cyanide
	name = "cyanide injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one contains cyanide, a lethal poison. It being inside a medical autoinjector has certain unsettling implications."
	filled_reagents = list(REAGENT_ID_CYANIDE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/serotrotium
	name = "serotrotium injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one is filled with serotrotium, which causes concentrated production of the serotonin neurotransmitter in humans."
	filled_reagents = list(REAGENT_ID_SEROTROTIUM = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/bliss
	name = "illicit injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one contains various illicit drugs, held inside a hypospray to make smuggling easier."
	filled_reagents = list(REAGENT_ID_BLISS = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/cryptobiolin
	name = "cryptobiolin injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one contains cryptobiolin, which causes confusion."
	filled_reagents = list(REAGENT_ID_CRYPTOBIOLIN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/impedrezene
	name = "impedrezene injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one has impedrezene inside, a narcotic that impairs higher brain functioning. \
	This autoinjector is almost certainly created illegitimately."
	filled_reagents = list(REAGENT_ID_IMPEDREZENE = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mindbreaker
	name = "mindbreaker injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This one stores the dangerous hallucinogen called 'Mindbreaker', likely put in place \
	by illicit groups hoping to hide their product."
	filled_reagents = list(REAGENT_ID_MINDBREAKER = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/psilocybin
	name = "psilocybin injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This has psilocybin inside, which is a strong psychotropic derived from certain species of mushroom. \
	This autoinjector likely was made by criminal elements to avoid detection from casual inspection."
	filled_reagents = list(REAGENT_ID_PSILOCYBIN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/mutagen
	name = "unstable mutagen injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This contains unstable mutagen, which makes using this a very bad idea. It will either \
	ruin your genetic health, turn you into a Five Points violation, or both!"
	filled_reagents = list(REAGENT_ID_MUTAGEN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/lexorin
	name = "lexorin injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	This contains lexorin, a dangerous toxin that stops respiration, and has been \
	implicated in several high-profile assassinations in the past."
	filled_reagents = list(REAGENT_ID_LEXORIN = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/healing_nanites
	name = "medical nanite injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	The injector stores a slurry of highly advanced and specialized nanomachines designed \
	to restore bodily health from within. The nanomachines are short-lived but degrade \
	harmlessly, and cannot self-replicate in order to remain Five Points compliant."
	filled_reagents = list(REAGENT_ID_HEALINGNANITES = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/defective_nanites
	name = "defective nanite injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	The injector stores a slurry of highly advanced and specialized nanomachines that \
	are unfortunately malfunctioning, making them unsafe to use inside of a living body. \
	Because of the Five Points, these nanites cannot self-replicate."
	filled_reagents = list(REAGENT_ID_DEFECTIVENANITES = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated
	name = "contaminated injector"
	desc = "A refined version of the standard autoinjector, allowing greater capacity. \
	The hypospray contains a viral agent inside, as well as a liquid substance that encourages \
	the growth of the virus inside."
	filled_reagents = list(REAGENT_ID_VIRUSFOOD = 15)

/obj/item/reagent_containers/hypospray/autoinjector/biginjector/contaminated/do_injection(mob/living/carbon/human/H, mob/living/user)
	. = ..()
	if(.) // Will occur if successfully injected.
		add_attack_logs(user, H, "Infected \the [H] with \the [src], by \the [user].")


/obj/item/reagent_containers/hypospray/autoinjector/burn
	name = "autoinjector (burn)"
	icon_state = "purple"
	filled_reagents = list(REAGENT_ID_DERMALINE = 3.5, REAGENT_ID_LEPORAZINE = 1.5)

/obj/item/reagent_containers/hypospray/autoinjector/trauma
	name = "autoinjector (trauma)"
	icon_state = "black"
	filled_reagents = list(REAGENT_ID_BICARIDINE = 4, REAGENT_ID_TRAMADOL = 1)

/obj/item/reagent_containers/hypospray/autoinjector/oxy
	name = "autoinjector (oxy)"
	icon_state = "blue"
	filled_reagents = list(REAGENT_ID_DEXALINP = 5)

/obj/item/reagent_containers/hypospray/autoinjector/rad
	name = "autoinjector (rad)"
	icon_state = "black"
	filled_reagents = list(REAGENT_ID_HYRONALIN = 5)

/obj/item/storage/box/traumainjectors
	name = "box of emergency injectors"
	desc = "Contains emergency autoinjectors."
	icon_state = "syringe"
	max_storage_space = ITEMSIZE_COST_SMALL * 7 // 14
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/trauma = 4,
		/obj/item/reagent_containers/hypospray/autoinjector/detox = 2,
		/obj/item/reagent_containers/hypospray/autoinjector/burn = 1
	)

/obj/item/reagent_containers/hypospray
	var/prototype = 0

/obj/item/reagent_containers/hypospray/science
	name = "prototype hypospray"
	desc = "This reproduction hypospray is nearly a perfect replica of the early model DeForest hyposprays, sharing many of the same features. However, there are additional safety measures installed to prevent unwanted injections."
	prototype = 1
