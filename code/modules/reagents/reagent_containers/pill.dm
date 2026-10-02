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

/obj/item/reagent_containers/pill/Initialize(mapload)
	. = ..()
	if(!icon_state)
		icon_state = "[base_state][rand(1, 4)]" //preset pills only use colour changing or unique icons

/obj/item/reagent_containers/pill/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	if(!M.consume_liquid_belly)
		if(liquid_belly_check())
			to_chat(user, span_infoplain("[user == M ? "You can't" : "\The [M] can't"] consume that, it contains something produced from a belly!"))
			return ITEM_INTERACT_FAILURE
	if(M == user)
		if(ishuman(M))
			var/mob/living/carbon/human/H = M
			if(!H.check_has_mouth())
				to_chat(user, "Where do you intend to put \the [src]? You don't have a mouth!")
				return ITEM_INTERACT_FAILURE
			var/obj/item/blocked = H.check_mouth_coverage()
			if(blocked)
				balloon_alert(user, "\the [blocked] is in the way!")
				return ITEM_INTERACT_FAILURE

			balloon_alert(user, "swallowed \the [src]")
			M.drop_from_inventory(src) //icon update
			if(reagents.total_volume)
				reagents.trans_to_mob(M, reagents.total_volume, CHEM_INGEST)
			consume(src, user)
			return ITEM_INTERACT_SUCCESS

	else if(ishuman(M))

		var/mob/living/carbon/human/H = M
		if(!H.check_has_mouth())
			balloon_alert(user, "\the [H] doesn't have a mouth.")
			return ITEM_INTERACT_FAILURE
		var/obj/item/blocked = H.check_mouth_coverage()
		if(blocked)
			balloon_alert(user, "\the [blocked] is in the way!")
			return ITEM_INTERACT_FAILURE

		user.balloon_alert_visible("[user] attempts to force [M] to swallow \the [src].")

		user.setClickCooldown(user.get_attack_speed(src))
		om_task_timed(user, 3 SECONDS, M, src, PROC_REF(force_swallow_done), list(user, M))
		return ITEM_INTERACT_SUCCESS

	return ITEM_INTERACT_FAILURE

/obj/item/reagent_containers/pill/proc/force_swallow_done(mob/living/user, mob/living/M)
	user.drop_from_inventory(src) //icon update
	user.balloon_alert_visible("[user] forces [M] to swallow \the [src].")

	var/contained = reagentlist()
	add_attack_logs(user,M,"Fed a pill containing [contained]")

	if(reagents && reagents.total_volume)
		reagents.trans_to_mob(M, reagents.total_volume, CHEM_INGEST)
	consume(src, user)

/obj/item/reagent_containers/pill/afterattack(obj/target, mob/user, proximity)
	if(!proximity) return

	if(target.is_open_container() && target.reagents)
		if(!target.reagents.total_volume)
			balloon_alert(user, "[target] is empty.")
			return
		user.balloon_alert_visible("[user] puts something in \the [target]", "[target] dissolves in \the [src]", 2)

		add_attack_logs(user,target,"Spiked [target.name] with a pill containing [reagentlist()]")

		reagents.trans_to(target, reagents.total_volume)
		/* for(var/mob/O in viewers(2, user)) // balloon_alert_visible handles this
			O.show_message(span_warning("[user] puts something in \the [target]."), 1)
		*/
		consume(src, user)

	return

DECLARE_INTERACTIONS(/obj/item/reagent_containers/pill, INTERACT_ITEM(null, PROC_REF(interaction_item)))

/// Old attackby.
/obj/item/reagent_containers/pill/proc/interaction_item(mob/user, obj/item/W, datum/interaction/interaction)
	if(is_sharp(W))
		var/obj/item/reagent_containers/powder/J = new /obj/item/reagent_containers/powder(src.loc)
		user.balloon_alert_visible("[user] cuts up [src] with [W]!", "cut up \the [src] with [W]")
		play_sfx(src.loc, SFX_EFFECTS_CHOP)

		if(reagents)
			reagents.trans_to_obj(J, reagents.total_volume)
		J.get_appearance()
		consume(src, user)

	if(istype(W, /obj/item/card/id))
		var/obj/item/reagent_containers/powder/J = new /obj/item/reagent_containers/powder(src.loc)
		user.balloon_alert_visible("[user] clumsily cuts up [src] with [W]!", "You clumsily cut up \the [src] with [W]")
		play_sfx(src.loc, SFX_EFFECTS_CHOP)

		if(reagents)
			reagents.trans_to_obj(J, reagents.total_volume)
		J.get_appearance()
		consume(src, user)

	return FALSE

////////////////////////////////////////////////////////////////////////////////
/// Pills. END
////////////////////////////////////////////////////////////////////////////////

//Pills
/obj/item/reagent_containers/pill/antitox
	name = REAGENT_ANTITOXIN + " (30u)"
	desc = "Neutralizes many common toxins."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/antitox, null, list(REAGENT_ID_ANTITOXIN = 30))

/obj/item/reagent_containers/pill/tox
	name = "Toxins pill"
	desc = "Highly toxic."
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/tox, null, list(REAGENT_ID_TOXIN = 50))

/obj/item/reagent_containers/pill/cyanide
	name = "Strange pill"
	desc = "It's marked 'KCN'. Smells vaguely of almonds."
	icon_state = "pill9"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/cyanide, null, list(REAGENT_ID_CYANIDE = 50))


/obj/item/reagent_containers/pill/adminordrazine
	name = REAGENT_ADMINORDRAZINE + " pill"
	desc = "It's magic. We don't have to explain it."
	icon_state = "pillA"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/adminordrazine, null, list(REAGENT_ID_ADMINORDRAZINE = 5))


/obj/item/reagent_containers/pill/stox
	name = REAGENT_STOXIN + " (15u)"
	desc = "Commonly used to treat insomnia."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/stox, null, list(REAGENT_ID_STOXIN = 15))

/obj/item/reagent_containers/pill/kelotane
	name = REAGENT_KELOTANE + " (20u)"
	desc = "Used to treat burns."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/kelotane, null, list(REAGENT_ID_KELOTANE = 20))

/obj/item/reagent_containers/pill/paracetamol
	name = REAGENT_PARACETAMOL + " (15u)"
	desc = REAGENT_PARACETAMOL + "! A painkiller for the ages. Chewables!"
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/paracetamol, null, list(REAGENT_ID_PARACETAMOL = 15))

/obj/item/reagent_containers/pill/tramadol
	name = REAGENT_TRAMADOL + " (15u)"
	desc = "A simple painkiller."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/tramadol, null, list(REAGENT_ID_TRAMADOL = 15))

/obj/item/reagent_containers/pill/methylphenidate
	name = REAGENT_METHYLPHENIDATE + " (15u)"
	desc = "Improves the ability to concentrate."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/citalopram
	name = REAGENT_CITALOPRAM + " (15u)"
	desc = "Mild anti-depressant."
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/citalopram, null, list(REAGENT_ID_CITALOPRAM = 15))

/obj/item/reagent_containers/pill/dexalin
	name = REAGENT_DEXALIN + " (7.5u)"
	desc = "Used to treat oxygen deprivation."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/dexalin, null, list(REAGENT_ID_DEXALIN = 7.5))

/obj/item/reagent_containers/pill/dexalin_plus
	name = REAGENT_DEXALINP + " (15u)"
	desc = "Used to treat extreme oxygen deprivation."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/dexalin_plus, null, list(REAGENT_ID_DEXALINP = 15))

/obj/item/reagent_containers/pill/dermaline
	name = REAGENT_DERMALINE + " (15u)"
	desc = "Used to treat burn wounds."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/dermaline, null, list(REAGENT_ID_DERMALINE = 15))

/obj/item/reagent_containers/pill/dylovene
	name = REAGENT_ANTITOXIN + " (15u)"
	desc = "A broad-spectrum anti-toxin."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/dylovene, null, list(REAGENT_ID_ANTITOXIN = 15))

/obj/item/reagent_containers/pill/inaprovaline
	name = REAGENT_INAPROVALINE + " (30u)"
	desc = "Used to stabilize patients."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/inaprovaline, null, list(REAGENT_ID_INAPROVALINE = 30))

/obj/item/reagent_containers/pill/bicaridine
	name = REAGENT_BICARIDINE + " (20u)"
	desc = "Used to treat physical injuries."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/bicaridine, null, list(REAGENT_ID_BICARIDINE = 20))

/obj/item/reagent_containers/pill/spaceacillin
	name = REAGENT_SPACEACILLIN + " (15u)"
	desc = "A theta-lactam antibiotic. Effective against many diseases likely to be encountered in space."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/spaceacillin, null, list(REAGENT_ID_SPACEACILLIN = 15))

/obj/item/reagent_containers/pill/carbon
	name = REAGENT_CARBON + " (30u)"
	desc = "Used to neutralise chemicals in the stomach."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/carbon, null, list(REAGENT_ID_CARBON = 30))

/obj/item/reagent_containers/pill/iron
	name = REAGENT_IRON + " (30u)"
	desc = "Used to aid in blood regeneration after bleeding for red-blooded crew."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/iron, null, list(REAGENT_ID_IRON = 30))

/obj/item/reagent_containers/pill/copper
	name = REAGENT_COPPER + " (30u)"
	desc = "Used to aid in blood regeneration after bleeding for blue-blooded crew."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/copper, null, list(REAGENT_ID_COPPER = 30))

//Not-quite-medicine
/obj/item/reagent_containers/pill/happy
	name = "Happy pill"
	desc = "Happy happy joy joy!"
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/happy, null, list(REAGENT_ID_BLISS = 15, REAGENT_ID_SUGAR = 15))

/obj/item/reagent_containers/pill/zoom
	name = "Zoom pill"
	desc = "Zoooom!"
	icon_state = "pill4"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/zoom, null, list(REAGENT_ID_EXPIREDMEDICINE = 5, REAGENT_ID_STIMM = 5))

/obj/item/reagent_containers/pill/zoom/Initialize(mapload)
	. = ..()
	if(prob(50)) // Zoom pill: chance to be more dangerous
		reagents.add_reagent(REAGENT_ID_MOLD, 2) // ALLOW(decl): Initialize rolls a random amount per instance; a declaration has no random form
	color = reagents.get_color()

/obj/item/reagent_containers/pill/diet
	name = "diet pill"
	desc = "Guaranteed to get you slim!"
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/diet, null, list(REAGENT_ID_LIPOZINE = 15))

// DISPENSER PILLS!
// These are smaller variants of pills that the medical kiosk gives!
/obj/item/reagent_containers/pill/small_blood_restoration
	name = "blood restoration pill"
	desc = "Used to aid in blood regeneration after or during bleeding for crew with commonly found blood types."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_blood_restoration, null, list(REAGENT_ID_IRON = 5, REAGENT_ID_COPPER = 5, REAGENT_ID_SILVER = 5, REAGENT_ID_GOLD = 5))

/obj/item/reagent_containers/pill/small_inaprovaline
	name = REAGENT_INAPROVALINE + " (5u)"
	desc = "Used to stabilize patients."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_inaprovaline, null, list(REAGENT_ID_INAPROVALINE = 5))

/obj/item/reagent_containers/pill/small_prussian_blue
	name = REAGENT_PRUSSIANBLUE + " (5u)"
	desc = "Used for the temporary cessation of radiation effects."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_prussian_blue, null, list(REAGENT_ID_PRUSSIANBLUE = 5))

/obj/item/reagent_containers/pill/small_tramadol
	name = REAGENT_TRAMADOL + " (5u)"
	desc = "A reelatively moderate painkiller typically given for more severe injuries."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_tramadol, null, list(REAGENT_ID_TRAMADOL = 5))

/obj/item/reagent_containers/pill/small_paracetamol
	name = REAGENT_PARACETAMOL + " (5u)"
	desc = "A rather weak painkiller typically given for minor injuries."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_paracetamol, null, list(REAGENT_ID_PARACETAMOL = 5))

/obj/item/reagent_containers/pill/small_dylovene
	name = REAGENT_ANTITOXIN + " (5u)"
	desc = "A broad-spectrum anti-toxin."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/small_dylovene, null, list(REAGENT_ID_ANTITOXIN = 5))


/obj/item/reagent_containers/pill/nutriment
	name = REAGENT_NUTRIMENT + " (30u)"
	desc = "Used to feed people on the field. Contains 30 units of " + REAGENT_NUTRIMENT + "."
	icon_state = "pill10"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/nutriment, null, list(REAGENT_ID_NUTRIMENT = 30))

/obj/item/reagent_containers/pill/protein
	name = REAGENT_PROTEIN + " (30u)"
	desc = "Used to feed carnivores on the field. Contains 30 units of " + REAGENT_PROTEIN + "."
	icon_state = "pill24"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/protein, null, list(REAGENT_ID_PROTEIN = 30))

/obj/item/reagent_containers/pill/rezadone
	name = REAGENT_REZADONE + " (5u)"
	desc = "A powder with almost magical properties, this substance can effectively treat genetic damage in humanoids, though excessive consumption has side effects."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/rezadone, null, list(REAGENT_ID_REZADONE = 5))

/obj/item/reagent_containers/pill/peridaxon
	name = REAGENT_PERIDAXON + " (10u)"
	desc = "Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	icon_state = "pill10"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/peridaxon, null, list(REAGENT_ID_PERIDAXON = 10))

/obj/item/reagent_containers/pill/carthatoline
	name = REAGENT_CARTHATOLINE + " (15u)"
	desc = REAGENT_CARTHATOLINE + " is strong evacuant used to treat severe poisoning."
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/carthatoline, null, list(REAGENT_ID_CARTHATOLINE = 15))

/obj/item/reagent_containers/pill/alkysine
	name = REAGENT_ALKYSINE + " (10u)"
	desc = REAGENT_ALKYSINE + " is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/alkysine, null, list(REAGENT_ID_ALKYSINE = 10))

/obj/item/reagent_containers/pill/imidazoline
	name = REAGENT_IMIDAZOLINE + " (15u)"
	desc = "Heals eye damage."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/imidazoline, null, list(REAGENT_ID_IMIDAZOLINE = 15))

/obj/item/reagent_containers/pill/osteodaxon
	name = REAGENT_OSTEODAXON + " (25u)"
	desc = "An experimental drug used to heal bone fractures."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/osteodaxon, null, list(REAGENT_ID_OSTEODAXON = 15, REAGENT_ID_INAPROVALINE = 10))

/obj/item/reagent_containers/pill/myelamine
	name = REAGENT_MYELAMINE + " (25u)"
	desc = "Used to rapidly clot internal hemorrhages by increasing the effectiveness of platelets."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/myelamine, null, list(REAGENT_ID_MYELAMINE = 15, REAGENT_ID_INAPROVALINE = 10))

/obj/item/reagent_containers/pill/hyronalin
	name = REAGENT_HYRONALIN + " (15u)"
	desc = REAGENT_HYRONALIN + " is a medicinal drug used to counter the effect of radiation poisoning."
	icon_state = "pill4"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/hyronalin, null, list(REAGENT_ID_HYRONALIN = 15))

/obj/item/reagent_containers/pill/arithrazine
	name = REAGENT_ARITHRAZINE + " (5u)"
	desc = REAGENT_ARITHRAZINE + " is an unstable medication used for the most extreme cases of radiation poisoning."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/arithrazine, null, list(REAGENT_ID_ARITHRAZINE = 5))

/obj/item/reagent_containers/pill/corophizine
	name = REAGENT_COROPHIZINE + " (5u)"
	desc = "A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/corophizine, null, list(REAGENT_ID_COROPHIZINE = 5))

/obj/item/reagent_containers/pill/vermicetol
	name = REAGENT_VERMICETOL + " (15u)"
	desc = "An extremely potent drug to treat physical injuries."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/vermicetol, null, list(REAGENT_ID_VERMICETOL = 15))

/obj/item/reagent_containers/pill/healing_nanites
	name = REAGENT_HEALINGNANITES + " (30u)"
	desc = "Miniature medical robots that swiftly restore bodily damage."
	icon_state = "pill1"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/healing_nanites, null, list(REAGENT_ID_HEALINGNANITES = 30))

/obj/item/reagent_containers/pill/sleevingcure
	name = REAGENT_SLEEVINGCURE + " (1u)"
	desc = "A rare cure provided by Vey-Med that helps counteract negative side effects of using imperfect resleeving machinery."
	icon_state = "pill3"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/sleevingcure, null, list(REAGENT_ID_SLEEVINGCURE = 1))

/obj/item/reagent_containers/pill/airlock
	name = "\'Airlock\' Pill"
	desc = "Neutralizes toxins and provides a mild analgesic effect."
	icon_state = "pill2"

DECLARE_REAGENTS(/obj/item/reagent_containers/pill/airlock, null, list(REAGENT_ID_ANTITOXIN = 15, REAGENT_ID_PARACETAMOL = 5))


// === merged from firstaid_chomp.dm (methylphenidate pill re-open; placed by its definer so the override wins) ===
/obj/item/reagent_containers/pill/methylphenidate
	name =  REAGENT_METHYLPHENIDATE + " (10u)"
	desc = "A pill to help you concentrate."
	icon_state = "pill2"

DECLARE_REAGENTS_TINTED(/obj/item/reagent_containers/pill/methylphenidate, null, list(REAGENT_ID_METHYLPHENIDATE = 10))

