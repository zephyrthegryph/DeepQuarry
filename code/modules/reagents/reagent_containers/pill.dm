////////////////////////////////////////////////////////////////////////////////
/// Pills.
////////////////////////////////////////////////////////////////////////////////
/obj/item/reagent_containers/pill
	name = "pill"
	desc = "A pill."
	icon = 'icons/obj/chemical.dmi'
	icon_state = null
	item_state = "pill"
	drop_sound = SFX_ITEMS_DROP_FOOD
	pickup_sound = SFX_ITEMS_PICKUP_FOOD

	var/base_state = "pill"

	max_transfer_amount = null
	w_class = ITEMSIZE_TINY
	slot_flags = SLOT_EARS
	volume = 60

/// Rolled before init (rolls(), code/engine/lifeforms/rolls.dm): what the old Initialize() drew from the world RNG.
/obj/item/reagent_containers/pill/proc/roll_icon_state(datum/roller/R)
	return "[base_state][R.number(1, 4)]"

// A pill is a sealed holder of its volume that is taken whole and used up (dose(), code/library/reagents/dose.dm): swallowed at once by yourself, forced down
// somebody else's throat in three seconds, dissolved in an open container. A sharp thing or an ID card cuts it up into a powder.
CAPABILITIES(/obj/item/reagent_containers/pill)
	reagent_container(
		volume = nameof(volume),
		needle = TRUE,
		sealed = TRUE,
		settable = FALSE,
		shows_contents = FALSE,
		transfer_default = nameof(amount_per_transfer_from_this))
	dose(route = CHEM_INGEST, cuts_into = /obj/item/reagent_containers/powder)
	rolls(nameof(icon_state), PROC_REF(roll_icon_state), when = cond_not(nameof(icon_state)))

////////////////////////////////////////////////////////////////////////////////
/// Pills. END
////////////////////////////////////////////////////////////////////////////////

//Pills
/obj/item/reagent_containers/pill/antitox
	name = REAGENT_ANTITOXIN + " (30u)"
	desc = "Neutralizes many common toxins."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/antitox)
	configure(reagents(add = list(REAGENT_ID_ANTITOXIN = 30), tint = TRUE))

/obj/item/reagent_containers/pill/tox
	name = "Toxins pill"
	desc = "Highly toxic."
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/tox)
	configure(reagents(add = list(REAGENT_ID_TOXIN = 50), tint = TRUE))

/obj/item/reagent_containers/pill/cyanide
	name = "Strange pill"
	desc = "It's marked 'KCN'. Smells vaguely of almonds."
	icon_state = "pill9"

CAPABILITIES(/obj/item/reagent_containers/pill/cyanide)
	configure(reagents(add = list(REAGENT_ID_CYANIDE = 50)))


/obj/item/reagent_containers/pill/adminordrazine
	name = REAGENT_ADMINORDRAZINE + " pill"
	desc = "It's magic. We don't have to explain it."
	icon_state = "pillA"

CAPABILITIES(/obj/item/reagent_containers/pill/adminordrazine)
	configure(reagents(add = list(REAGENT_ID_ADMINORDRAZINE = 5)))


/obj/item/reagent_containers/pill/stox
	name = REAGENT_STOXIN + " (15u)"
	desc = "Commonly used to treat insomnia."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/stox)
	configure(reagents(add = list(REAGENT_ID_STOXIN = 15), tint = TRUE))

/obj/item/reagent_containers/pill/kelotane
	name = REAGENT_KELOTANE + " (20u)"
	desc = "Used to treat burns."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/kelotane)
	configure(reagents(add = list(REAGENT_ID_KELOTANE = 20), tint = TRUE))

/obj/item/reagent_containers/pill/paracetamol
	name = REAGENT_PARACETAMOL + " (15u)"
	desc = REAGENT_PARACETAMOL + "! A painkiller for the ages. Chewables!"
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/paracetamol)
	configure(reagents(add = list(REAGENT_ID_PARACETAMOL = 15), tint = TRUE))

/obj/item/reagent_containers/pill/tramadol
	name = REAGENT_TRAMADOL + " (15u)"
	desc = "A simple painkiller."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/tramadol)
	configure(reagents(add = list(REAGENT_ID_TRAMADOL = 15), tint = TRUE))

/obj/item/reagent_containers/pill/methylphenidate
	name = REAGENT_METHYLPHENIDATE + " (15u)"
	desc = "Improves the ability to concentrate."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/citalopram
	name = REAGENT_CITALOPRAM + " (15u)"
	desc = "Mild anti-depressant."
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/citalopram)
	configure(reagents(add = list(REAGENT_ID_CITALOPRAM = 15), tint = TRUE))

/obj/item/reagent_containers/pill/dexalin
	name = REAGENT_DEXALIN + " (7.5u)"
	desc = "Used to treat oxygen deprivation."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/dexalin)
	configure(reagents(add = list(REAGENT_ID_DEXALIN = 7.5), tint = TRUE))

/obj/item/reagent_containers/pill/dexalin_plus
	name = REAGENT_DEXALINP + " (15u)"
	desc = "Used to treat extreme oxygen deprivation."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/dexalin_plus)
	configure(reagents(add = list(REAGENT_ID_DEXALINP = 15), tint = TRUE))

/obj/item/reagent_containers/pill/dermaline
	name = REAGENT_DERMALINE + " (15u)"
	desc = "Used to treat burn wounds."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/dermaline)
	configure(reagents(add = list(REAGENT_ID_DERMALINE = 15), tint = TRUE))

/obj/item/reagent_containers/pill/dylovene
	name = REAGENT_ANTITOXIN + " (15u)"
	desc = "A broad-spectrum anti-toxin."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/dylovene)
	configure(reagents(add = list(REAGENT_ID_ANTITOXIN = 15), tint = TRUE))

/obj/item/reagent_containers/pill/inaprovaline
	name = REAGENT_INAPROVALINE + " (30u)"
	desc = "Used to stabilize patients."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/inaprovaline)
	configure(reagents(add = list(REAGENT_ID_INAPROVALINE = 30), tint = TRUE))

/obj/item/reagent_containers/pill/bicaridine
	name = REAGENT_BICARIDINE + " (20u)"
	desc = "Used to treat physical injuries."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/bicaridine)
	configure(reagents(add = list(REAGENT_ID_BICARIDINE = 20), tint = TRUE))

/obj/item/reagent_containers/pill/spaceacillin
	name = REAGENT_SPACEACILLIN + " (15u)"
	desc = "A theta-lactam antibiotic. Effective against many diseases likely to be encountered in space."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/spaceacillin)
	configure(reagents(add = list(REAGENT_ID_SPACEACILLIN = 15), tint = TRUE))

/obj/item/reagent_containers/pill/carbon
	name = REAGENT_CARBON + " (30u)"
	desc = "Used to neutralise chemicals in the stomach."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/carbon)
	configure(reagents(add = list(REAGENT_ID_CARBON = 30), tint = TRUE))

/obj/item/reagent_containers/pill/iron
	name = REAGENT_IRON + " (30u)"
	desc = "Used to aid in blood regeneration after bleeding for red-blooded crew."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/iron)
	configure(reagents(add = list(REAGENT_ID_IRON = 30), tint = TRUE))

/obj/item/reagent_containers/pill/copper
	name = REAGENT_COPPER + " (30u)"
	desc = "Used to aid in blood regeneration after bleeding for blue-blooded crew."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/copper)
	configure(reagents(add = list(REAGENT_ID_COPPER = 30), tint = TRUE))

//Not-quite-medicine
/obj/item/reagent_containers/pill/happy
	name = "Happy pill"
	desc = "Happy happy joy joy!"
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/happy)
	configure(reagents(add = list(REAGENT_ID_BLISS = 15, REAGENT_ID_SUGAR = 15), tint = TRUE))

/obj/item/reagent_containers/pill/zoom
	name = "Zoom pill"
	desc = "Zoooom!"
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/zoom)
	configure(reagents(add = list(REAGENT_ID_EXPIREDMEDICINE = 5, REAGENT_ID_STIMM = 5)))

// ALLOW(init/INSTANCE_STATE): rolls whether this pill carries mould
/obj/item/reagent_containers/pill/zoom/Initialize(mapload)
	. = ..()
	if(prob(50)) // Zoom pill: chance to be more dangerous
		reagents.add_reagent(REAGENT_ID_MOLD, 2) // ALLOW(decl): Initialize rolls a random amount per instance; a declaration has no random form
	color = reagents.get_color()

/obj/item/reagent_containers/pill/diet
	name = "diet pill"
	desc = "Guaranteed to get you slim!"
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/diet)
	configure(reagents(add = list(REAGENT_ID_LIPOZINE = 15), tint = TRUE))

// DISPENSER PILLS!
// These are smaller variants of pills that the medical kiosk gives!
/obj/item/reagent_containers/pill/small_blood_restoration
	name = "blood restoration pill"
	desc = "Used to aid in blood regeneration after or during bleeding for crew with commonly found blood types."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/small_blood_restoration)
	configure(reagents(add = list(REAGENT_ID_IRON = 5, REAGENT_ID_COPPER = 5, REAGENT_ID_SILVER = 5, REAGENT_ID_GOLD = 5), tint = TRUE))

/obj/item/reagent_containers/pill/small_inaprovaline
	name = REAGENT_INAPROVALINE + " (5u)"
	desc = "Used to stabilize patients."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/small_inaprovaline)
	configure(reagents(add = list(REAGENT_ID_INAPROVALINE = 5), tint = TRUE))

/obj/item/reagent_containers/pill/small_prussian_blue
	name = REAGENT_PRUSSIANBLUE + " (5u)"
	desc = "Used for the temporary cessation of radiation effects."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/small_prussian_blue)
	configure(reagents(add = list(REAGENT_ID_PRUSSIANBLUE = 5), tint = TRUE))

/obj/item/reagent_containers/pill/small_tramadol
	name = REAGENT_TRAMADOL + " (5u)"
	desc = "A reelatively moderate painkiller typically given for more severe injuries."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/small_tramadol)
	configure(reagents(add = list(REAGENT_ID_TRAMADOL = 5), tint = TRUE))

/obj/item/reagent_containers/pill/small_paracetamol
	name = REAGENT_PARACETAMOL + " (5u)"
	desc = "A rather weak painkiller typically given for minor injuries."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/small_paracetamol)
	configure(reagents(add = list(REAGENT_ID_PARACETAMOL = 5), tint = TRUE))

/obj/item/reagent_containers/pill/small_dylovene
	name = REAGENT_ANTITOXIN + " (5u)"
	desc = "A broad-spectrum anti-toxin."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/small_dylovene)
	configure(reagents(add = list(REAGENT_ID_ANTITOXIN = 5), tint = TRUE))


/obj/item/reagent_containers/pill/nutriment
	name = REAGENT_NUTRIMENT + " (30u)"
	desc = "Used to feed people on the field. Contains 30 units of " + REAGENT_NUTRIMENT + "."
	icon_state = "pill10"

CAPABILITIES(/obj/item/reagent_containers/pill/nutriment)
	configure(reagents(add = list(REAGENT_ID_NUTRIMENT = 30)))

/obj/item/reagent_containers/pill/protein
	name = REAGENT_PROTEIN + " (30u)"
	desc = "Used to feed carnivores on the field. Contains 30 units of " + REAGENT_PROTEIN + "."
	icon_state = "pill24"

CAPABILITIES(/obj/item/reagent_containers/pill/protein)
	configure(reagents(add = list(REAGENT_ID_PROTEIN = 30)))

/obj/item/reagent_containers/pill/rezadone
	name = REAGENT_REZADONE + " (5u)"
	desc = "A powder with almost magical properties, this substance can effectively treat genetic damage in humanoids, though excessive consumption has side effects."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/rezadone)
	configure(reagents(add = list(REAGENT_ID_REZADONE = 5), tint = TRUE))

/obj/item/reagent_containers/pill/peridaxon
	name = REAGENT_PERIDAXON + " (10u)"
	desc = "Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	icon_state = "pill10"

CAPABILITIES(/obj/item/reagent_containers/pill/peridaxon)
	configure(reagents(add = list(REAGENT_ID_PERIDAXON = 10)))

/obj/item/reagent_containers/pill/carthatoline
	name = REAGENT_CARTHATOLINE + " (15u)"
	desc = REAGENT_CARTHATOLINE + " is strong evacuant used to treat severe poisoning."
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/carthatoline)
	configure(reagents(add = list(REAGENT_ID_CARTHATOLINE = 15), tint = TRUE))

/obj/item/reagent_containers/pill/alkysine
	name = REAGENT_ALKYSINE + " (10u)"
	desc = REAGENT_ALKYSINE + " is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/alkysine)
	configure(reagents(add = list(REAGENT_ID_ALKYSINE = 10), tint = TRUE))

/obj/item/reagent_containers/pill/imidazoline
	name = REAGENT_IMIDAZOLINE + " (15u)"
	desc = "Heals eye damage."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/imidazoline)
	configure(reagents(add = list(REAGENT_ID_IMIDAZOLINE = 15), tint = TRUE))

/obj/item/reagent_containers/pill/osteodaxon
	name = REAGENT_OSTEODAXON + " (25u)"
	desc = "An experimental drug used to heal bone fractures."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/osteodaxon)
	configure(reagents(add = list(REAGENT_ID_OSTEODAXON = 15, REAGENT_ID_INAPROVALINE = 10), tint = TRUE))

/obj/item/reagent_containers/pill/myelamine
	name = REAGENT_MYELAMINE + " (25u)"
	desc = "Used to rapidly clot internal hemorrhages by increasing the effectiveness of platelets."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/myelamine)
	configure(reagents(add = list(REAGENT_ID_MYELAMINE = 15, REAGENT_ID_INAPROVALINE = 10), tint = TRUE))

/obj/item/reagent_containers/pill/hyronalin
	name = REAGENT_HYRONALIN + " (15u)"
	desc = REAGENT_HYRONALIN + " is a medicinal drug used to counter the effect of radiation poisoning."
	icon_state = "pill4"

CAPABILITIES(/obj/item/reagent_containers/pill/hyronalin)
	configure(reagents(add = list(REAGENT_ID_HYRONALIN = 15), tint = TRUE))

/obj/item/reagent_containers/pill/arithrazine
	name = REAGENT_ARITHRAZINE + " (5u)"
	desc = REAGENT_ARITHRAZINE + " is an unstable medication used for the most extreme cases of radiation poisoning."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/arithrazine)
	configure(reagents(add = list(REAGENT_ID_ARITHRAZINE = 5), tint = TRUE))

/obj/item/reagent_containers/pill/corophizine
	name = REAGENT_COROPHIZINE + " (5u)"
	desc = "A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/corophizine)
	configure(reagents(add = list(REAGENT_ID_COROPHIZINE = 5), tint = TRUE))

/obj/item/reagent_containers/pill/vermicetol
	name = REAGENT_VERMICETOL + " (15u)"
	desc = "An extremely potent drug to treat physical injuries."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/vermicetol)
	configure(reagents(add = list(REAGENT_ID_VERMICETOL = 15), tint = TRUE))

/obj/item/reagent_containers/pill/healing_nanites
	name = REAGENT_HEALINGNANITES + " (30u)"
	desc = "Miniature medical robots that swiftly restore bodily damage."
	icon_state = "pill1"

CAPABILITIES(/obj/item/reagent_containers/pill/healing_nanites)
	configure(reagents(add = list(REAGENT_ID_HEALINGNANITES = 30), tint = TRUE))

/obj/item/reagent_containers/pill/sleevingcure
	name = REAGENT_SLEEVINGCURE + " (1u)"
	desc = "A rare cure provided by Vey-Med that helps counteract negative side effects of using imperfect resleeving machinery."
	icon_state = "pill3"

CAPABILITIES(/obj/item/reagent_containers/pill/sleevingcure)
	configure(reagents(add = list(REAGENT_ID_SLEEVINGCURE = 1), tint = TRUE))

/obj/item/reagent_containers/pill/airlock
	name = "\'Airlock\' Pill"
	desc = "Neutralizes toxins and provides a mild analgesic effect."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/airlock)
	configure(reagents(add = list(REAGENT_ID_ANTITOXIN = 15, REAGENT_ID_PARACETAMOL = 5)))


// === merged from firstaid_chomp.dm (methylphenidate pill re-open; placed by its definer so the override wins) ===
/obj/item/reagent_containers/pill/methylphenidate
	name =  REAGENT_METHYLPHENIDATE + " (10u)"
	desc = "A pill to help you concentrate."
	icon_state = "pill2"

CAPABILITIES(/obj/item/reagent_containers/pill/methylphenidate)
	configure(reagents(add = list(REAGENT_ID_METHYLPHENIDATE = 10), tint = TRUE))

