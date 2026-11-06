CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar)
	configure(atom_rules(description_fluff = "While the label does say that this is a 'premium cigar', it \
	really cannot match other types of cigars on the market. Is it a quality \
	cigarette? Perhaps. Was it hand-made with care? No."))
	configure(movable_motion(throw_speed = 0.5))
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 2))) // 4 total

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba)
	configure(atom_rules(description_fluff = "Cohiba has been a popular cigar company for centuries. \
	They are still based out of Cuba and refuse to expand and therefore have a very \
	limited quantity, making their cigars coveted all through known space. Robusto \
	is one of their most popular shapes of cigars."))
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 3))) // 7 total

CAPABILITIES(/obj/item/clothing/mask/smokable/cigarette/cigar/havana)
	configure(atom_rules(description_fluff = "'Havanian' is an umbrella term for any cigar made in the \
	typical handmade style of Cuba. This particular cigar is from Gilthari's cigar \
	manufacturers and produced galaxy-wide. While this way of making quality cigars \
	has become slightly bastardized over the years, overall quality has remained \
	relatively the same, even if there is a large quantity of 'Havanian' cigars."))
	configure(reagents(add = list(REAGENT_ID_NICOTINE = 6))) // 10 total

////////////
// CIGARS //
////////////
/obj/item/clothing/mask/smokable/cigarette/cigar
	name = "premium cigar"
	desc = "A brown roll of tobacco and... well, you're not quite sure. This thing's huge!"
	icon_state = "cigar2"
	type_butt = /obj/item/trash/cigbutt/cigarbutt
	item_state = "cigar"
	max_smoketime = 1500
	smoketime = 1500
	chem_volume = 20
	matchmes = span_notice("USER lights their NAME with their FLAME.")
	lightermes = span_notice("USER manages to offend their NAME by lighting it with FLAME.")
	zippomes = span_notice(span_rose("With a flick of their wrist, USER lights their NAME with their FLAME."))
	weldermes = span_notice("USER insults NAME by lighting it with FLAME.")
	ignitermes = span_notice("USER fiddles with FLAME, and manages to light their NAME with the power of science.")

/obj/item/clothing/mask/smokable/cigarette/cigar/cohiba
	name = "\improper Cohiba Robusto cigar"
	desc = "There's little more you could want from a cigar."
	icon_state = "cigar2"

/obj/item/clothing/mask/smokable/cigarette/cigar/havana
	name = "premium Havanian cigar"
	desc = "Save these for the fancy-pantses at the next CentCom black tie reception. \
	You can't blow the smoke from such majestic stogies in just anyone's face."
	icon_state = "cigar2"
	max_smoketime = 7200
	smoketime = 7200
	chem_volume = 30

/// A cigar redraws the user's mask and hands after the cigarette handling.
/obj/item/clothing/mask/smokable/cigarette/cigar/item_applied(datum/act/op/A)
	..()
	return OP_OK
