/* Pens!
 * Contains:
 *		Pens
 *		Coloured Pens
 *		Fountain Pens
 *		Multi Pen
 *		Reagent Pens
 *		Blade Pens
 *		Sleepy Pens
 *		Parapens
 *		Chameleon Pen
 *		Crayons
 */

/*
 * Pens
 */
/obj/item/pen
	name = "pen"
	desc = "It's a normal black ink pen."
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "pen"
	item_state = "pen"
	slot_flags = SLOT_BELT | SLOT_EARS
	throwforce = 0
	w_class = ITEMSIZE_TINY
	throw_speed = 7
	throw_range = 15
	MATERIAL_BULK(MAT_STEEL, 10)
	var/colour = "black"	//what colour the ink is!
	pressure_resistance = 2
	drop_sound = 'sound/items/drop/accessory.ogg'
	pickup_sound = 'sound/items/pickup/accessory.ogg'
	var/can_click = TRUE

	///Var for attack_self chain
	var/special_handling = FALSE

DECLARE_INTERACTIONS(/obj/item/pen, \
	INTERACT_SELF("Click", PROC_REF(interaction_click)), \
	INTERACT_ALT("Click", PROC_REF(interaction_click_alt)), \
)

/// Old attack_self: click the pen. Specially handled pens leave it to their own self-use.
/obj/item/pen/proc/interaction_click(mob/user, obj/item/held, datum/interaction/interaction)
	if(special_handling)
		return FALSE
	if(!user.checkClickCooldown())
		return TRUE
	if(!can_click)
		return TRUE
	user.setClickCooldown(1 SECOND)
	to_chat(user, span_notice("Click."))
	playsound(src, 'sound/items/penclick.ogg', 50, 1)
	return TRUE

/*
 * Coloured Pens
 */
/obj/item/pen/blue
	desc = "It's a normal blue ink pen."
	icon_state = "pen_blue"
	colour = "blue"

/obj/item/pen/red
	desc = "It's a normal red ink pen."
	icon_state = "pen_red"
	colour = "red"

/*
 * Fountain Pens
 */
/obj/item/pen/fountain
	desc = "A well made fountain pen, with a faux wood body."
	icon_state = "pen_fountain"

/obj/item/pen/fountain2
	desc = "A well made fountain pen, with a faux wood body. This one has golden accents."
	icon_state = "pen_fountain"

/obj/item/pen/fountain3
	desc = "A well made expesive rosewood pen with golden accents. Very pretty."
	icon_state = "pen_fountain"

/obj/item/pen/fountain4
	desc = "A well made and expensive fountain pen. This one has silver accents."
	icon_state = "blues_fountain"

/obj/item/pen/fountain5
	desc = "A well made and expensive fountain pen. This one has gold accents."
	icon_state = "blueg_fountain"

/obj/item/pen/fountain6
	desc = "A well made and expensive fountain pen. The nib is quite sharp."
	icon_state = "command_fountain"

/obj/item/pen/fountain7
	desc = "A well made and expensive fountain pen made from gold."
	icon_state = "gold_fountain"

/obj/item/pen/fountain8
	desc = "A well made and expensive fountain pen."
	icon_state = "black_fountain"

/obj/item/pen/fountain9
	desc = "A well made and expensive fountain pen made for gesturing."
	icon_state = "mime_fountain"


/*
 * Multi Pen
 */
/obj/item/pen/multi
	desc = "It's a pen with multiple colors of ink!"
	var/selectedColor = 1
	var/colors = list("black","blue","red")
	special_handling = TRUE

/// Old click_alt.
/obj/item/pen/proc/interaction_click_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(!Adjacent(user))
		return TRUE
	to_chat(user, span_notice("Click."))
	playsound(src, 'sound/items/penclick.ogg', 50, 1)
	return TRUE

EXTEND_INTERACTIONS(/obj/item/pen/multi, INTERACT_USE("Change colour", PROC_REF(interaction_cycle_colour)))

/// Old attack_self.
/obj/item/pen/multi/proc/interaction_cycle_colour(mob/user, obj/item/held, datum/interaction/interaction)
	if(++selectedColor > 3)
		selectedColor = 1

	colour = colors[selectedColor]

	if(colour == "black")
		icon_state = "pen"
	else
		icon_state = "pen_[colour]"

	to_chat(user, span_notice("Changed color to '[colour].'"))

/obj/item/pen/invisible
	desc = "It's an invisble pen marker."
	icon_state = "pen"
	colour = "white"

/*
 * Reagent Pens
 */

/obj/item/pen/reagent
	flags = OPENCONTAINER

/obj/item/pen/reagent/Initialize(mapload)
	. = ..()
	create_reagents(30)

/obj/item/pen/reagent/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)
	. = ..()

	if(M.can_inject(user,1))
		if(reagents.total_volume)
			if(M.reagents)
				var/contained = reagents.get_reagents()
				var/trans = reagents.trans_to_mob(M, 30, CHEM_BLOOD)
				add_attack_logs(user,M,"Injected with [src.name] containing [contained], trasferred [trans] units")
				return ITEM_INTERACT_SUCCESS

/*
 * Blade Pens
 */
/obj/item/pen/blade
	desc = "It's a normal black ink pen."
	description_antag = "This pen can be transformed into a dangerous melee and thrown assassination weapon with an Alt-Click.\
	When active, it cannot be caught safely."
	name = "pen"
	icon = 'icons/obj/bureaucracy.dmi'
	icon_state = "pen"
	item_state = "pen"
	slot_flags = SLOT_BELT | SLOT_EARS
	throwforce = 3
	w_class = ITEMSIZE_TINY
	throw_speed = 7
	throw_range = 15
	armor_penetration = 20

	var/active = 0
	var/active_embed_chance = 0
	var/active_force = 15
	var/active_throwforce = 30
	var/active_w_class = ITEMSIZE_NORMAL
	var/active_icon_state
	var/default_icon_state

/obj/item/pen/blade/Initialize(mapload)
	. = ..()
	active_icon_state = "[icon_state]-x"
	default_icon_state = icon_state

EXTEND_INTERACTIONS(/obj/item/pen/blade, INTERACT_ALT("Toggle blade", PROC_REF(interaction_toggle_blade)))

/// Old click_alt: the pen's click, then the blade toggles.
/obj/item/pen/blade/proc/interaction_toggle_blade(mob/user, obj/item/held, datum/interaction/interaction)
	interaction_click_alt(user, held, interaction)
	if(active)
		deactivate(user)
	else
		activate(user)

	to_chat(user, span_notice("You [active ? "de" : ""]activate \the [src]'s blade."))
	return TRUE

/obj/item/pen/blade/proc/activate(mob/living/user)
	if(active)
		return
	active = 1
	icon_state = active_icon_state
	embed_chance = active_embed_chance
	force = active_force
	throwforce = active_throwforce
	sharp = TRUE
	edge = TRUE
	w_class = active_w_class
	playsound(src, 'sound/weapons/saberon.ogg', 15, 1)
	injury_kind = INJURY_CUT
	injury_kinds = alist(INJURY_BURN = 1/3, INJURY_CUT = 2/3)
	catchable = FALSE

	attack_verb = attack_verb | list(\
		"slashed",\
		"cut",\
		"shredded",\
		"stabbed"\
		)

/obj/item/pen/blade/proc/deactivate(mob/living/user)
	if(!active)
		return
	playsound(src, 'sound/weapons/saberoff.ogg', 15, 1)
	active = 0
	icon_state = default_icon_state
	embed_chance = initial(embed_chance)
	force = initial(force)
	throwforce = initial(throwforce)
	sharp = initial(sharp)
	edge = initial(edge)
	w_class = initial(w_class)
	injury_kind = initial(injury_kind)
	injury_kinds = null
	catchable = TRUE

/obj/item/pen/blade/blue
	desc = "It's a normal blue ink pen."
	icon_state = "pen_blue"
	colour = "blue"

/obj/item/pen/blade/red
	desc = "It's a normal red ink pen."
	icon_state = "pen_red"
	colour = "red"

/obj/item/pen/blade/fountain
	desc = "A well made fountain pen, with a faux wood body."
	icon_state = "pen_fountain"

/*
 * Sleepy Pens
 */
/obj/item/pen/reagent/sleepy
	desc = "It's a black ink pen with a sharp point and a carefully engraved \"Waffle Co.\""

/obj/item/pen/reagent/sleepy/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_CHLORALHYDRATE, 22)


/*
 * Parapens
 */
/obj/item/pen/reagent/paralysis

/obj/item/pen/reagent/paralysis/Initialize(mapload)
	. = ..()
	reagents.add_reagent(REAGENT_ID_ZOMBIEPOWDER, 5)
	reagents.add_reagent(REAGENT_ID_CRYPTOBIOLIN, 10)

/*
 * Chameleon Pen
 */
/obj/item/pen/chameleon
	var/signature = ""
	special_handling = TRUE

EXTEND_INTERACTIONS(/obj/item/pen/chameleon, \
	INTERACT_USE("Set signature", PROC_REF(interaction_signature)), \
	INTERACT_VERB("Change Pen Colour", PROC_REF(chameleon_pen_verb_colour), REQ_IN_INVENTORY), \
)

/// Old attack_self.
/obj/item/pen/chameleon/proc/interaction_signature(mob/user, obj/item/held, datum/interaction/interaction)
	/*
	// Limit signatures to official crew members
	var/personnel_list[] = list()
	for(var/datum/data/record/t in GLOB.data_core.locked) //Look in data core locked.
		personnel_list.Add(t.fields["name"])
	personnel_list.Add("Anonymous")

	var/new_signature = tgui_input_list(user, "Enter new signature pattern.", "New Signature", personnel_list)
	if(new_signature)
		signature = new_signature
	*/
	var/_answer_k301 = rerun_ask(user, "k301", PROC_REF(interaction_signature), args, /datum/om/prompt/text, message = "Enter new signature. Leave blank for 'Anonymous'", title = "New Signature", default = signature)
	if(isnull(_answer_k301))
		return TRUE
	signature = _answer_k301

/obj/item/pen/proc/get_signature(mob/user)
	return (user && user.real_name) ? user.real_name : "Anonymous"

/obj/item/pen/chameleon/get_signature(mob/user)
	return signature ? signature : "Anonymous"

/// Old Change Pen Colour verb.
/obj/item/pen/chameleon/proc/chameleon_pen_verb_colour(mob/user, obj/item/held, datum/interaction/interaction)
	var/list/possible_colours = list ("Yellow", "Green", "Pink", "Blue", "Orange", "Cyan", "Red", "Invisible", "Black")
	var/selected_type = rerun_ask(user, "k314", PROC_REF(chameleon_pen_verb_colour), args, /datum/om/prompt/choice, message = "Pick new colour.", title = "Pen Colour", choices = possible_colours)
	if(isnull(selected_type))
		return

	if(selected_type)
		switch(selected_type)
			if("Yellow")
				colour = COLOR_YELLOW
			if("Green")
				colour = COLOR_LIME
			if("Pink")
				colour = COLOR_PINK
			if("Blue")
				colour = COLOR_BLUE
			if("Orange")
				colour = COLOR_ORANGE
			if("Cyan")
				colour = COLOR_CYAN
			if("Red")
				colour = COLOR_RED
			if("Invisible")
				colour = COLOR_WHITE
			else
				colour = COLOR_BLACK
		to_chat(user, span_info("You select the [lowertext(selected_type)] ink container."))


/*
 * Crayons
 */
/obj/item/pen/crayon
	name = "crayon"
	desc = "A colourful crayon. Please refrain from eating it or putting it in your nose."
	icon = 'icons/obj/crayons.dmi'
	icon_state = "crayonred"
	w_class = ITEMSIZE_TINY
	attack_verb = list("attacked", "coloured")
	colour = "#FF0000" //RGB
	var/shadeColour = "#220000" //RGB
	var/uses = 30 //0 for unlimited uses
	var/instant = 0
	var/colourName = "red" //for updateIcon purposes
	drop_sound = 'sound/items/drop/gloves.ogg'
	pickup_sound = 'sound/items/pickup/gloves.ogg'
	can_click = FALSE
	special_handling = TRUE

/obj/item/pen/crayon/Initialize(mapload)
	. = ..()
	name = "[colourName] [name]"

/obj/item/pen/crayon/marker
	name = "marker"
	desc = "A chisel-tip permanent marker. Hopefully non-toxic."
	icon_state = "markerred"


//Adminspawn item for hunters who're doing kidnaps during events
/obj/item/pen/autostun
	desc = "A well made and expensive fountain pen. This one has gold accents."
	icon_state = "blueg_fountain"
	var/stun_duration = 10

/obj/item/pen/autostun/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(!istype(M))
		return ITEM_INTERACT_FAILURE
	M.status_at_least(EFFECT_STUNNED, stun_duration)
	return ITEM_INTERACT_SUCCESS

/obj/item/pen/autostun/paralyse
	desc = "A well made and expensive fountain pen. This one has gold accents."

/obj/item/pen/autostun/paralyse/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(!istype(M))
		return ITEM_INTERACT_FAILURE
	M.status_at_least(EFFECT_PARALYZED, stun_duration)
	return ITEM_INTERACT_SUCCESS

/obj/item/pen/autostun/weaken
	desc = "A well made and expensive fountain pen. This one has gold accents."

/obj/item/pen/autostun/weaken/attack(mob/living/M, mob/living/user, target_zone, attack_modifier)

	if(!istype(M))
		return ITEM_INTERACT_FAILURE
	M.status_at_least(EFFECT_WEAKENED, stun_duration)
	return ITEM_INTERACT_SUCCESS
