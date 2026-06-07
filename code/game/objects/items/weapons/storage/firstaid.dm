/* First aid storage
 * Contains:
 *		First Aid Kits
 * 		Pill Bottles
 */

/*
 * First Aid Kits
 */
/obj/item/storage/firstaid
	name = "first aid kit"
	desc = "It's an emergency medical kit for those serious boo-boos."
	icon = 'icons/obj/storage.dmi'
	icon_state = "firstaid"
	throw_speed = 2
	throw_range = 8
	max_storage_space = ITEMSIZE_COST_SMALL * 7 // 14
	var/list/icon_variety
	drop_sound = 'sound/items/drop/cardboardbox.ogg'
	pickup_sound = 'sound/items/pickup/cardboardbox.ogg'

/obj/item/storage/firstaid/Initialize(mapload)
	. = ..()
	if(icon_variety)
		icon_state = pick(icon_variety)
		icon_variety = null

/obj/item/storage/firstaid/fire
	name = "fire first aid kit"
	desc = "It's an emergency medical kit for when the toxins lab <i>spontaneously</i> burns down."
	icon_state = "ointment"
	item_state_slots = list(slot_r_hand_str = "firstaid-ointment", slot_l_hand_str = "firstaid-ointment")
	//icon_variety = list("ointment","firefirstaid") //VOREStation Removal
	starts_with = list(
		/obj/item/healthanalyzer,
		/obj/item/reagent_containers/hypospray/autoinjector,
		/obj/item/stack/medical/ointment,
		/obj/item/stack/medical/ointment,
		/obj/item/reagent_containers/pill/kelotane,
		/obj/item/reagent_containers/pill/kelotane,
		/obj/item/reagent_containers/pill/kelotane
	)

/obj/item/storage/firstaid/regular
	icon_state = "firstaid"
	starts_with = list(
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/ointment,
		/obj/item/stack/medical/ointment,
		/obj/item/healthanalyzer,
		/obj/item/reagent_containers/hypospray/autoinjector
	)

/obj/item/storage/firstaid/toxin
	name = "poison first aid kit" //IRL the term used would be poison first aid kit.
	desc = "Used to treat when one has a high amount of toxins in their body."
	icon_state = "antitoxin"
	item_state_slots = list(slot_r_hand_str = "firstaid-toxin", slot_l_hand_str = "firstaid-toxin")
	//icon_variety = list("antitoxin","antitoxfirstaid","antitoxfirstaid2","antitoxfirstaid3") //VOREStation Removal
	starts_with = list(
		/obj/item/reagent_containers/syringe/antitoxin,
		/obj/item/reagent_containers/syringe/antitoxin,
		/obj/item/reagent_containers/syringe/antitoxin,
		/obj/item/reagent_containers/pill/antitox,
		/obj/item/reagent_containers/pill/antitox,
		/obj/item/reagent_containers/pill/antitox,
		/obj/item/healthanalyzer
	)

/obj/item/storage/firstaid/o2
	name = "oxygen deprivation first aid kit"
	desc = "A box full of oxygen goodies."
	icon_state = "o2"
	item_state_slots = list(slot_r_hand_str = "firstaid-o2", slot_l_hand_str = "firstaid-o2")
	starts_with = list(
		/obj/item/reagent_containers/pill/dexalin,
		/obj/item/reagent_containers/pill/dexalin,
		/obj/item/reagent_containers/pill/dexalin,
		/obj/item/reagent_containers/pill/dexalin,
		/obj/item/reagent_containers/hypospray/autoinjector,
		/obj/item/reagent_containers/syringe/inaprovaline,
		/obj/item/healthanalyzer
	)

/obj/item/storage/firstaid/adv
	name = "advanced first aid kit"
	desc = "Contains advanced medical treatments, for <b>serious</b> boo-boos."
	icon_state = "advfirstaid"
	item_state_slots = list(slot_r_hand_str = "firstaid-advanced", slot_l_hand_str = "firstaid-advanced")
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/ointment,
		/obj/item/stack/medical/advanced/ointment,
		/obj/item/stack/medical/splint
	)

/obj/item/storage/firstaid/combat
	name = "combat medical kit"
	desc = "Contains advanced medical treatments."
	icon_state = "bezerk"
	item_state_slots = list(slot_r_hand_str = "firstaid-advanced", slot_l_hand_str = "firstaid-advanced")
	starts_with = list(
		/obj/item/storage/pill_bottle/bicaridine,
		/obj/item/storage/pill_bottle/dermaline,
		/obj/item/storage/pill_bottle/dexalin_plus,
		/obj/item/storage/pill_bottle/dylovene,
		/obj/item/storage/pill_bottle/tramadol,
		/obj/item/storage/pill_bottle/spaceacillin,
		/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting,
		/obj/item/stack/medical/splint,
		/obj/item/healthanalyzer/advanced
	)

/obj/item/storage/firstaid/surgery
	name = "surgery kit"
	desc = "Contains tools for surgery. Has precise foam fitting for safe transport and automatically sterilizes the content between uses."
	icon = 'icons/obj/storage.dmi' // VOREStation edit
	icon_state = "surgerykit"
	item_state = "firstaid-surgery"
	max_w_class = ITEMSIZE_NORMAL

	can_hold = list(
		/obj/item/surgical/bonesetter,
		/obj/item/surgical/cautery,
		/obj/item/surgical/circular_saw,
		/obj/item/surgical/hemostat,
		/obj/item/surgical/retractor,
		/obj/item/surgical/scalpel,
		/obj/item/surgical/surgicaldrill,
		/obj/item/surgical/bonegel,
		/obj/item/surgical/FixOVein,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/nanopaste,
		/obj/item/healthanalyzer/advanced,
		/obj/item/autopsy_scanner
		)

	starts_with = list(
		/obj/item/surgical/bonesetter,
		/obj/item/surgical/cautery,
		/obj/item/surgical/circular_saw,
		/obj/item/surgical/hemostat,
		/obj/item/surgical/retractor,
		/obj/item/surgical/scalpel,
		/obj/item/surgical/surgicaldrill,
		/obj/item/surgical/bonegel,
		/obj/item/surgical/FixOVein,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/healthanalyzer/advanced,
		/obj/item/autopsy_scanner
		)

/obj/item/storage/firstaid/clotting
	name = "clotting kit"
	desc = "Contains chemicals to stop bleeding."
	max_storage_space = ITEMSIZE_COST_SMALL * 7
	starts_with = list(/obj/item/reagent_containers/hypospray/autoinjector/biginjector/clotting = 8)

/obj/item/storage/firstaid/bonemed
	name = "bone repair kit"
	desc = "Contains chemicals to mend broken bones."
	max_storage_space = ITEMSIZE_COST_SMALL * 7
	starts_with = list(/obj/item/reagent_containers/hypospray/autoinjector/bonemed = 8)

/*
 * Pill Bottles
 */
/obj/item/storage/pill_bottle
	name = "pill bottle"
	desc = "It's an airtight container for storing medication."
	icon_state = "pill_canister"
	icon = 'icons/obj/chemical.dmi'
	drop_sound = 'sound/items/drop/pillbottle.ogg'
	pickup_sound = 'sound/items/pickup/pillbottle.ogg'
	item_state_slots = list(slot_r_hand_str = "contsolid", slot_l_hand_str = "contsolid")
	w_class = ITEMSIZE_SMALL
	can_hold = list(/obj/item/reagent_containers/pill,/obj/item/dice,/obj/item/paper)
	allow_quick_gather = 1
	allow_quick_empty = 1
	use_to_pickup = TRUE
	use_sound = 'sound/items/storage/pillbottle.ogg'
	max_storage_space = ITEMSIZE_COST_TINY * 14
	max_w_class = ITEMSIZE_TINY
	var/wrapper_color
	var/label

	var/label_text = ""
	var/base_name = " "
	var/base_desc = " "

/obj/item/storage/pill_bottle/Initialize(mapload)
	. = ..()
	base_name = name
	base_desc = desc
	update_icon()

/obj/item/storage/pill_bottle/update_icon()
	cut_overlays()
	if(wrapper_color)
		var/image/I = image(icon, "pillbottle_wrap")
		I.color = wrapper_color
		add_overlay(I)

/obj/item/storage/pill_bottle/attackby(obj/item/W as obj, mob/user as mob)
	if(istype(W, /obj/item/pen) || istype(W, /obj/item/flashlight/pen))
		var/tmp_label = sanitizeSafe(tgui_input_text(user, "Enter a label for [name]", "Label", label_text, MAX_NAME_LEN, encode = FALSE), MAX_NAME_LEN)
		if(length(tmp_label) > 50)
			to_chat(user, span_notice("The label can be at most 50 characters long."))
		else if(length(tmp_label) > 10)
			to_chat(user, span_notice("You set the label."))
			label_text = tmp_label
			update_name_label()
		else
			to_chat(user, span_notice("You set the label to \"[tmp_label]\"."))
			label_text = tmp_label
			update_name_label()
	else
		..()

/obj/item/storage/pill_bottle/proc/update_name_label()
	if(!label_text)
		name = base_name
		desc = base_desc
		return
	else if(length(label_text) > 10)
		var/short_label_text = copytext(label_text, 1, 11)
		name = "[base_name] ([short_label_text]...)"
	else
		name = "[base_name] ([label_text])"
	desc = "[base_desc] It is labeled \"[label_text]\"."

/obj/item/storage/pill_bottle/antitox
	name = "pill bottle (Dylovene)"
	desc = "Contains pills used to counter toxins."
	starts_with = list(/obj/item/reagent_containers/pill/antitox = 7)
	wrapper_color = COLOR_GREEN

/obj/item/storage/pill_bottle/bicaridine
	name = "pill bottle (Bicaridine)"
	desc = "Contains pills used to stabilize the severely injured."
	starts_with = list(/obj/item/reagent_containers/pill/bicaridine = 7)
	wrapper_color = COLOR_MAROON

/obj/item/storage/pill_bottle/dexalin_plus
	name = "pill bottle (Dexalin Plus)"
	desc = "Contains pills used to treat extreme cases of oxygen deprivation."
	starts_with = list(/obj/item/reagent_containers/pill/dexalin_plus = 7)
	wrapper_color = "#3366cc"

/obj/item/storage/pill_bottle/dermaline
	name = "pill bottle (Dermaline)"
	desc = "Contains pills used to treat burn wounds."
	starts_with = list(/obj/item/reagent_containers/pill/dermaline = 7)
	wrapper_color = "#e8d131"

/obj/item/storage/pill_bottle/dylovene
	name = "pill bottle (Dylovene)"
	desc = "Contains pills used to treat toxic substances in the blood."
	starts_with = list(/obj/item/reagent_containers/pill/dylovene = 7)
	wrapper_color = COLOR_GREEN

/obj/item/storage/pill_bottle/inaprovaline
	name = "pill bottle (Inaprovaline)"
	desc = "Contains pills used to stabilize patients."
	starts_with = list(/obj/item/reagent_containers/pill/inaprovaline = 7)
	wrapper_color = COLOR_PALE_BLUE_GRAY

/obj/item/storage/pill_bottle/kelotane
	name = "pill bottle (Kelotane)"
	desc = "Contains pills used to treat burns."
	starts_with = list(/obj/item/reagent_containers/pill/kelotane = 7)
	wrapper_color = "#ec8b2f"

/obj/item/storage/pill_bottle/spaceacillin
	name = "pill bottle (Spaceacillin)"
	desc = "A theta-lactam antibiotic. Effective against many diseases likely to be encountered in space."
	starts_with = list(/obj/item/reagent_containers/pill/spaceacillin = 7)
	wrapper_color = COLOR_PALE_GREEN_GRAY

/obj/item/storage/pill_bottle/tramadol
	name = "pill bottle (Tramadol)"
	desc = "Contains pills used to relieve pain."
	starts_with = list(/obj/item/reagent_containers/pill/tramadol = 7)
	wrapper_color = COLOR_PURPLE_GRAY

/obj/item/storage/pill_bottle/citalopram
	name = "pill bottle (Citalopram)"
	desc = "Contains pills used to stabilize a patient's mood."
	starts_with = list(/obj/item/reagent_containers/pill/citalopram = 7)
	wrapper_color = COLOR_GRAY

/obj/item/storage/pill_bottle/carbon
	name = "pill bottle (Carbon)"
	desc = "Contains pills used to neutralise chemicals in the stomach."
	starts_with = list(/obj/item/reagent_containers/pill/carbon = 7)

/obj/item/storage/pill_bottle/iron
	name = "pill bottle (Iron)"
	desc = "Contains pills used to aid in blood regeneration."
	starts_with = list(/obj/item/reagent_containers/pill/iron = 7)


// === merged from firstaid_vr.dm during hard-fork de-suffix (verified no override-order change) ===
/obj/item/storage/firstaid
	icon = 'icons/obj/storage_vr.dmi'

/obj/item/storage/firstaid/fire
	starts_with = list(
		/obj/item/storage/pill_bottle/kelotane,
		/obj/item/stack/medical/ointment,
		/obj/item/stack/medical/ointment,
		/obj/item/reagent_containers/hypospray/autoinjector/burn,
		/obj/item/reagent_containers/hypospray/autoinjector/burn,
		/obj/item/reagent_containers/hypospray/autoinjector/burn,
		/obj/item/reagent_containers/hypospray/autoinjector/burn
	)

/obj/item/storage/firstaid/regular
	starts_with = list(
		/obj/item/healthanalyzer, /*YW EDIT*/
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/bruise_pack,
		/obj/item/stack/medical/ointment,
		/obj/item/stack/medical/ointment,
		/obj/item/storage/pill_bottle/paracetamol
	)

/obj/item/storage/firstaid/toxin
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/detox,
		/obj/item/reagent_containers/hypospray/autoinjector/detox,
		/obj/item/reagent_containers/hypospray/autoinjector/detox,
		/obj/item/reagent_containers/hypospray/autoinjector/detox,
		/obj/item/reagent_containers/hypospray/autoinjector/rad,
		/obj/item/reagent_containers/hypospray/autoinjector/rad,
		/obj/item/storage/pill_bottle/antitox
	)

/obj/item/storage/firstaid/o2
	starts_with = list(
		/obj/item/reagent_containers/hypospray/autoinjector/oxy,
		/obj/item/reagent_containers/hypospray/autoinjector/oxy,
		/obj/item/reagent_containers/hypospray/autoinjector/oxy,
		/obj/item/reagent_containers/hypospray/autoinjector/oxy,
		/obj/item/storage/pill_bottle/inaprovaline,
		/obj/item/storage/pill_bottle/blood_regen,
		/obj/item/storage/pill_bottle/dexalin
	)

/obj/item/storage/firstaid/adv
	starts_with = list(
		/obj/item/storage/pill_bottle/assorted,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/medical/advanced/ointment,
		/obj/item/stack/medical/advanced/ointment,
		/obj/item/stack/medical/splint
	)

/obj/item/storage/firstaid/combat
	starts_with = list(
		/obj/item/storage/pill_bottle/vermicetol,
		/obj/item/storage/pill_bottle/dermaline,
		/obj/item/storage/pill_bottle/dexalin_plus,
		/obj/item/storage/pill_bottle/carthatoline,
		/obj/item/storage/pill_bottle/tramadol,
		/obj/item/storage/pill_bottle/corophizine,
		/obj/item/storage/pill_bottle/combat,
		/obj/item/stack/medical/splint,
		/obj/item/healthanalyzer/phasic
	)

/obj/item/storage/firstaid/surgery
	can_hold = list(
		/obj/item/surgical/bone_clamp,
		/obj/item/surgical/bonesetter,
		/obj/item/surgical/cautery,
		/obj/item/surgical/circular_saw,
		/obj/item/surgical/hemostat,
		/obj/item/surgical/retractor,
		/obj/item/surgical/scalpel,
		/obj/item/surgical/surgicaldrill,
		/obj/item/surgical/bonegel,
		/obj/item/surgical/FixOVein,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/stack/nanopaste,
		/obj/item/healthanalyzer,
		/obj/item/autopsy_scanner,
		/obj/item/surgical/bioregen
		)

	starts_with = list(
		/obj/item/surgical/bonesetter,
		/obj/item/surgical/cautery,
		/obj/item/surgical/circular_saw,
		/obj/item/surgical/hemostat,
		/obj/item/surgical/retractor,
		/obj/item/surgical/scalpel,
		/obj/item/surgical/surgicaldrill,
		/obj/item/surgical/bonegel,
		/obj/item/surgical/FixOVein,
		/obj/item/stack/medical/advanced/bruise_pack,
		/obj/item/healthanalyzer,
		/obj/item/autopsy_scanner,
		/obj/item/surgical/bioregen
		)


/obj/item/storage/firstaid/clotting
	icon_state = "clottingkit"

/obj/item/storage/firstaid/bonemed
	icon_state = "pinky"

/obj/item/storage/pill_bottle/antitox
	starts_with = list(/obj/item/reagent_containers/pill/antitox = 14)

/obj/item/storage/pill_bottle/bicaridine
	starts_with = list(/obj/item/reagent_containers/pill/bicaridine = 14)

/obj/item/storage/pill_bottle/dexalin_plus
	starts_with = list(/obj/item/reagent_containers/pill/dexalin_plus = 14)

/obj/item/storage/pill_bottle/dermaline
	starts_with = list(/obj/item/reagent_containers/pill/dermaline = 14)

/obj/item/storage/pill_bottle/dylovene
	starts_with = list(/obj/item/reagent_containers/pill/dylovene = 14)

/obj/item/storage/pill_bottle/inaprovaline
	starts_with = list(/obj/item/reagent_containers/pill/inaprovaline = 14)

/obj/item/storage/pill_bottle/kelotane
	starts_with = list(/obj/item/reagent_containers/pill/kelotane = 14)

/obj/item/storage/pill_bottle/spaceacillin
	starts_with = list(/obj/item/reagent_containers/pill/spaceacillin = 14)

/obj/item/storage/pill_bottle/tramadol
	starts_with = list(/obj/item/reagent_containers/pill/tramadol = 14)

/obj/item/storage/pill_bottle/citalopram
	starts_with = list(/obj/item/reagent_containers/pill/citalopram = 14)

/obj/item/storage/pill_bottle/carbon
	starts_with = list(/obj/item/reagent_containers/pill/carbon = 14)

/obj/item/storage/pill_bottle/iron
	starts_with = list(/obj/item/reagent_containers/pill/iron = 14)

/obj/item/storage/pill_bottle/blood_regen
	name = "pill bottle (blood regeneration)"
	desc = "Contains iron and copper pills for treating bloodloss by employed species."
	starts_with = list(/obj/item/reagent_containers/pill/iron = 9,
	/obj/item/reagent_containers/pill/copper = 5)

/obj/item/storage/pill_bottle/adminordrazine
	name = "pill bottle (" + REAGENT_ADMINORDRAZINE + ")"
	desc = "It's magic. We don't have to explain it."
	starts_with = list(/obj/item/reagent_containers/pill/adminordrazine = 21)

/obj/item/storage/pill_bottle/nutriment
	name = "pill bottle (Food)"
	desc = "Contains pills used to feed people."
	starts_with = list(/obj/item/reagent_containers/pill/nutriment = 7, /obj/item/reagent_containers/pill/protein = 7)

/obj/item/storage/pill_bottle/rezadone
	name = "pill bottle (" + REAGENT_REZADONE + ")"
	desc = "A powder with almost magical properties, this substance can effectively treat genetic damage in humanoids, though excessive consumption has side effects."
	starts_with = list(/obj/item/reagent_containers/pill/rezadone = 14)
	wrapper_color = COLOR_GREEN_GRAY

/obj/item/storage/pill_bottle/peridaxon
	name = "pill bottle (" + REAGENT_PERIDAXON + ")"
	desc = "Used to encourage recovery of internal organs and nervous systems. Medicate cautiously."
	starts_with = list(/obj/item/reagent_containers/pill/peridaxon = 14)
	wrapper_color = COLOR_PURPLE

/obj/item/storage/pill_bottle/carthatoline
	name = "pill bottle (" + REAGENT_CARTHATOLINE + ")"
	desc = REAGENT_CARTHATOLINE + " is strong evacuant used to treat severe poisoning."
	starts_with = list(/obj/item/reagent_containers/pill/carthatoline = 14)
	wrapper_color = COLOR_GREEN_GRAY

/obj/item/storage/pill_bottle/alkysine
	name = "pill bottle (" + REAGENT_ALKYSINE + ")"
	desc = REAGENT_ALKYSINE + " is a drug used to lessen the damage to neurological tissue after a catastrophic injury. Can heal brain tissue."
	starts_with = list(/obj/item/reagent_containers/pill/alkysine = 14)
	wrapper_color = COLOR_YELLOW

/obj/item/storage/pill_bottle/imidazoline
	name = "pill bottle (" + REAGENT_IMIDAZOLINE + ")"
	desc = "Heals eye damage."
	starts_with = list(/obj/item/reagent_containers/pill/imidazoline = 14)
	wrapper_color = COLOR_PURPLE_GRAY

/obj/item/storage/pill_bottle/osteodaxon
	name = "pill bottle (" + REAGENT_OSTEODAXON + ")"
	desc = "An experimental drug used to heal bone fractures."
	starts_with = list(/obj/item/reagent_containers/pill/osteodaxon = 14)
	wrapper_color = COLOR_WHITE

/obj/item/storage/pill_bottle/myelamine
	name = "pill bottle (Myelamine)"
	desc = "Used to rapidly clot internal hemorrhages by increasing the effectiveness of platelets."
	starts_with = list(/obj/item/reagent_containers/pill/myelamine = 14)
	wrapper_color = COLOR_PALE_PURPLE_GRAY

/obj/item/storage/pill_bottle/hyronalin
	name = "pill bottle (" + REAGENT_HYRONALIN + ")"
	desc = REAGENT_HYRONALIN + " is a medicinal drug used to counter the effect of radiation poisoning."
	starts_with = list(/obj/item/reagent_containers/pill/hyronalin = 14)
	wrapper_color = COLOR_TEAL

/obj/item/storage/pill_bottle/arithrazine
	name = "pill bottle (" + REAGENT_ARITHRAZINE + ")"
	desc = REAGENT_ARITHRAZINE + " is an unstable medication used for the most extreme cases of radiation poisoning."
	starts_with = list(/obj/item/reagent_containers/pill/arithrazine = 14)
	wrapper_color = COLOR_TEAL

/obj/item/storage/pill_bottle/corophizine
	name = "pill bottle (" + REAGENT_COROPHIZINE + ")"
	desc = "A wide-spectrum antibiotic drug. Powerful and uncomfortable in equal doses."
	starts_with = list(/obj/item/reagent_containers/pill/corophizine = 14)
	wrapper_color = COLOR_PALE_GREEN_GRAY

/obj/item/storage/pill_bottle/vermicetol
	name = "pill bottle (" + REAGENT_VERMICETOL + ")"
	desc = "Contains pills used to stabilize the extremely injured."
	starts_with = list(/obj/item/reagent_containers/pill/vermicetol = 14)
	wrapper_color = COLOR_MAROON

/obj/item/storage/pill_bottle/healing_nanites
	name = "pill bottle (" + REAGENT_HEALINGNANITES + ")"
	desc = "Miniature medical robots that swiftly restore bodily damage."
	starts_with = list(/obj/item/reagent_containers/pill/healing_nanites = 14)

/obj/item/storage/pill_bottle/sleevingcure
	name = "pill bottle (" + REAGENT_SLEEVINGCURE + ")"
	desc = "A rare cure provided by Vey-Medical that helps counteract negative side effects of using imperfect resleeving machinery."
	starts_with = list(/obj/item/reagent_containers/pill/sleevingcure = 7)

/obj/item/storage/pill_bottle/sleevingcure/full
	starts_with = list(/obj/item/reagent_containers/pill/sleevingcure = 14)

/obj/item/storage/mrebag/pill
	name = "vacuum-sealed pill"
	desc = "A small vacuum-sealed package containing a singular pill. For emergencies only."
	icon_state = "pouch_small"
	max_w_class = ITEMSIZE_TINY
	can_hold = list(/obj/item/reagent_containers/pill)

/*CHOMPStation removal begin
/obj/item/storage/mrebag/pill/sleevingcure
	name = "vacuum-sealed pill (" + REAGENT_SLEEVINGCURE + ")"
	desc = "A small vacuum-sealed package containing a singular pill. For emergencies only."
	starts_with = list(/obj/item/reagent_containers/pill/sleevingcure)
*/ //CHOMPStation removal end

/obj/item/storage/pill_bottle/paracetamol
	name = "pill bottle (" + REAGENT_PARACETAMOL + ")"
	desc = "Contains over the counter medicine to treat pain."
	starts_with = list(/obj/item/reagent_containers/pill/paracetamol = 14)
	wrapper_color = COLOR_GRAY

/obj/item/storage/pill_bottle/dexalin
	name = "pill bottle (" + REAGENT_DEXALIN + ")"
	desc = "Contains pills used to treat oxygen deprivation."
	starts_with = list(/obj/item/reagent_containers/pill/dexalin = 14)
	wrapper_color = "#3366cc"

/obj/item/storage/pill_bottle/assorted
	name = "pill bottle (Assorted)"
	desc = "Commonly found on paramedics, these assorted pill bottles contain basic treatments for nonstandard injuries."
	starts_with = list(
			/obj/item/reagent_containers/pill/inaprovaline = 3,
			/obj/item/reagent_containers/pill/antitox = 3,
			/obj/item/reagent_containers/pill/iron = 1,
			/obj/item/reagent_containers/pill/copper = 1,
			/obj/item/reagent_containers/pill/tramadol = 2,
			/obj/item/reagent_containers/pill/hyronalin = 3,
			/obj/item/reagent_containers/pill/spaceacillin
		)
	wrapper_color = COLOR_BLACK

/obj/item/storage/pill_bottle/combat
	name = "pill bottle (Combat)"
	desc = "A pill bottle filled with some of the rarest medical treatmeants to exist."
	max_storage_space = ITEMSIZE_COST_TINY * 20
	starts_with = list(
			/obj/item/reagent_containers/pill/peridaxon = 5,
			/obj/item/reagent_containers/pill/rezadone = 5,
			/obj/item/reagent_containers/pill/myelamine = 3,
			/obj/item/reagent_containers/pill/osteodaxon = 3,
			/obj/item/reagent_containers/pill/arithrazine = 2,
			/obj/item/reagent_containers/pill/alkysine = 1,
			/obj/item/reagent_containers/pill/imidazoline = 1
		)
	wrapper_color = COLOR_BLACK


// === merged from firstaid_chomp.dm during hard-fork de-suffix (new kits/bottles) ===
/obj/item/storage/firstaid/experimental
	name = "experimental firstaid kit"
	icon = 'icons/obj/storage.dmi'
	icon_state = "expirmentalaid"
	starts_with = list(
		/obj/item/storage/pill_bottle/neotane,
		/obj/item/storage/pill_bottle/burncard,
		/obj/item/storage/pill_bottle/flamecure,
		/obj/item/storage/pill_bottle/juggernog,
		/obj/item/storage/pill_bottle/curea,
		/obj/item/storage/pill_bottle/souldew,
		/obj/item/storage/pill_bottle/purifyingagent)


/obj/item/storage/pill_bottle/neotane
	name = "pill bottle (" + REAGENT_NEOTANE + ")"
	desc = "Contains experimental pills, good for soothing burns but tends to mangle the flesh."
	starts_with = list(/obj/item/reagent_containers/pill/neotane = 12)
	wrapper_color = COLOR_ORANGE

/obj/item/storage/pill_bottle/burncard
	name = "pill bottle (" + REAGENT_BURNCARD + ")"
	desc = "Contains experimental pills, good for sealing cuts and bruises but is quite searing."
	starts_with = list(/obj/item/reagent_containers/pill/burncard = 12)
	wrapper_color = COLOR_RED

/obj/item/storage/pill_bottle/flamecure
	name = "pill bottle (" + REAGENT_FLAMECURE + ")"
	desc = "Contains experimental pills, good for searing shut internal wounds."
	starts_with = list(/obj/item/reagent_containers/pill/flamecure = 12)
	wrapper_color = COLOR_ORANGE

/obj/item/storage/pill_bottle/juggernog
	name = "pill bottle (" + REAGENT_JUGGERNOG + ")"
	desc = "Contains experimental pills good for letting folks keep standing underneath relentless pummeling."
	starts_with = list(/obj/item/reagent_containers/pill/juggernog = 12)
	wrapper_color = COLOR_RED

/obj/item/storage/pill_bottle/curea
	name = "pill bottle (" + REAGENT_CUREA + ")"
	desc = "Contains experimental pills, very effective for frostfly and poisonfly hunting."
	starts_with = list(/obj/item/reagent_containers/pill/curea = 12)
	wrapper_color = COLOR_BLUE

/obj/item/storage/pill_bottle/souldew
	name = "pill bottle (" + REAGENT_SOULDEW + ")"
	desc = "Contains experimental pills, for feeding the dead."
	starts_with = list(/obj/item/reagent_containers/pill/souldew = 12)
	wrapper_color = COLOR_GREEN

/obj/item/storage/pill_bottle/purifyingagent
	name = "pill bottle (" + REAGENT_PURIFYINGAGENT + ")"
	desc = "Contains experimental pills, having application as an anti-toxin."
	starts_with = list(/obj/item/reagent_containers/pill/purifyingagent = 12)
	wrapper_color = COLOR_GREEN

/obj/item/storage/pill_bottle/methylphenidate
	name = "pill bottle (" + REAGENT_METHYLPHENIDATE + ")"
	desc = "Contains pills used to help a patient concentrate. Usually prescribed for ADHD or similar conditions."
	starts_with = list(/obj/item/reagent_containers/pill/methylphenidate = 7)
	wrapper_color = COLOR_GUNMETAL

/obj/item/storage/pill_bottle/paroxetine
	name = "pill bottle (" + REAGENT_PAROXETINE + ")"
	desc = "Contains pills used to help treat severe depression. Side effects can include hallucinations."
	starts_with = list(/obj/item/reagent_containers/pill/paroxetine = 7)
	wrapper_color = COLOR_GRAY40

/obj/item/storage/pill_bottle/adranol
	name = "pill bottle (" + REAGENT_ADRANOL + ")"
	desc = "Contains pills used to help treat jitters, blurred vision, and confusion."
	starts_with = list(/obj/item/reagent_containers/pill/adranol = 7)
	wrapper_color = COLOR_YELLOW

/obj/item/storage/pill_bottle/aphrodisiac //this is totally first aid shut up
	name = "pill bottle (" + REAGENT_APHRODISIAC + ")"
	desc = "Contains pills used to help get it on."
	starts_with = list(/obj/item/reagent_containers/pill/aphrodisiac = 14)
	wrapper_color = COLOR_PINK

//Pills
/obj/item/reagent_containers/pill/neotane
	name = REAGENT_NEOTANE + " (10u)"
	desc = "An experimental pill."

	icon_state = "pill2"

/obj/item/reagent_containers/pill/neotane/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_NEOTANE, 5)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/burncard
	name = REAGENT_BURNCARD + " (10u)"
	desc = "An experimental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/burncard/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_BURNCARD, 5)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/flamecure
	name = REAGENT_FLAMECURE + " (5u)"
	desc = "An experimental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/flamecure/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_FLAMECURE, 5)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/juggernog
	name = REAGENT_JUGGERNOG + " (5u)"
	desc = "An experimental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/juggernog/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_JUGGERNOG, 5)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/curea
	name = REAGENT_CUREA + " (10u)"
	desc = "An experimental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/curea/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_CUREA, 10)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/souldew
	name = REAGENT_SOULDEW + " (10u)"
	desc = "An experimental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/souldew/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_SOULDEW, 10)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/purifyingagent
	name = REAGENT_PURIFYINGAGENT + " (10u)"

	desc = "An expirmental pill."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/purifyingagent/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_PURIFYINGAGENT, 10)

	color = reagents.get_color()

/obj/item/reagent_containers/pill/paroxetine
	name = REAGENT_PAROXETINE + " (10u)"
	desc = "A pill to help treat severe depression."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/paroxetine/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_PAROXETINE, 10)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/adranol
	name = REAGENT_ADRANOL + " (10u)"
	desc = "A pill to help treat jitters, confusion, and blurred vision."
	icon_state = "pill2"

/obj/item/reagent_containers/pill/adranol/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_ADRANOL, 10)
	color = reagents.get_color()

/obj/item/reagent_containers/pill/aphrodisiac
	name = REAGENT_APHRODISIAC + " (20u)"
	desc = "Just one couldn't hurt, right?"
	icon_state = "pill2"

/obj/item/reagent_containers/pill/aphrodisiac/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_APHRODISIAC, 20)
	color = reagents.get_color()
