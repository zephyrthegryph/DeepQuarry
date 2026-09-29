#define ALL_SPELLS "All"

GLOBAL_LIST_INIT(all_technomancer_spells, subtypesof(/datum/technomancer/spell))
GLOBAL_LIST_INIT(all_technomancer_equipment, subtypesof(/datum/technomancer/equipment))
GLOBAL_LIST_INIT(all_technomancer_consumables, subtypesof(/datum/technomancer/consumable))
GLOBAL_LIST_INIT(all_technomancer_assistance, subtypesof(/datum/technomancer/assistance))

/datum/technomancer
	var/name = "technomancer thing"
	var/desc = "If you can see this, something broke."
	var/cost = 100
	var/hidden = 0
	var/obj_path = null
	var/ability_icon_state = null

/datum/technomancer/spell
	var/category = ALL_SPELLS
	var/enhancement_desc = null
	var/spell_power_desc = null

/obj/item/technomancer_catalog
	name = "catalog"
	desc = "A \"book\" featuring a holographic display, metal cover, and miniaturized teleportation device, allowing the user to \
	requisition various things from... wherever they came from."
	icon = 'icons/obj/storage.dmi'
	icon_state ="scientology" //placeholder
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_BELT
	var/budget = 1000
	var/max_budget = 1000
	var/mob/living/carbon/human/owner = null
	var/list/spell_instances
	var/list/equipment_instances
	var/list/consumable_instances
	var/list/assistance_instances
	var/tab = 4 // Info tab, so new players can read it before doing anything.
	var/spell_tab = ALL_SPELLS
	var/show_scepter_text = 0
	var/universal = FALSE // Allows non-technomancers to use this catalog

/obj/item/technomancer_catalog/apprentice
	name = "apprentice's catalog"
	budget = 700
	max_budget = 700

/obj/item/technomancer_catalog/master //for badmins, I suppose
	name = "master's catalog"
	budget = 2000
	max_budget = 2000

/obj/item/technomancer_catalog/universal
	name = "universal catalog"
	desc = "A catalog to be used with the 'Universal Core', its contents shamelessly \
	copied by an unknown designer from some group of 'technomancers' or another.<br>\
	The back of the book has " + span_italics("'Export Edition'") + " stamped on it."
	budget = 700
	max_budget = 700
	universal = TRUE

// Proc: bind_to_owner()
// Parameters: 1 (new_owner - mob that the book is trying to bind to)
// Description: Links the catalog to hopefully the technomancer, so that only they can access it.
/obj/item/technomancer_catalog/proc/bind_to_owner(mob/living/carbon/human/new_owner)
	if(!owner && (GLOB.technomancers.is_antagonist(new_owner.mind) || universal)) // Universal catalogs
		owner = new_owner

// Proc: New()
// Parameters: 0
// Description: Sets up the catalog, as shown below.
/obj/item/technomancer_catalog/Initialize(mapload)
	. = ..()
	set_up()

// Proc: set_up()
// Parameters: 0
// Description: Instantiates all the catalog datums for everything that can be bought.
/obj/item/technomancer_catalog/proc/set_up()
	if(!length(spell_instances))
		for(var/S in GLOB.all_technomancer_spells)
			LAZYADD(spell_instances, new S())
	if(!length(equipment_instances))
		for(var/E in GLOB.all_technomancer_equipment)
			LAZYADD(equipment_instances, new E())
	if(!length(consumable_instances))
		for(var/C in GLOB.all_technomancer_consumables)
			LAZYADD(consumable_instances, new C())
	if(!length(assistance_instances))
		for(var/A in GLOB.all_technomancer_assistance)
			LAZYADD(assistance_instances, new A())

/obj/item/technomancer_catalog/apprentice/set_up()
	..()
	for(var/datum/technomancer/assistance/apprentice/A in assistance_instances)
		LAZYREMOVE(assistance_instances, A)

// Proc: show_categories()
// Parameters: 1 (category - the category link to display)
// Description: Shows an href link to go to a spell subcategory if the category is not already selected, otherwise is bold, to reduce
// code duplicating.
/obj/item/technomancer_catalog/proc/show_categories(category)
	if(category)
		if(spell_tab != category)
			return "<a href='byond://?src=\ref[src];spell_category=[category]'>[category]</a>"
		else
			return span_bold("[category]")

// TGUI migration: full structured data, no embedded
// byond:// hrefs. All actions dispatched via tgui_act.
DECLARE_INTERACTIONS(/obj/item/technomancer_catalog, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ITEM(null, PROC_REF(interaction_item)), \
)

/// Old attack_self.
/obj/item/technomancer_catalog/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(!user)
		return TRUE
	if(owner && user != owner)
		to_chat(user, span_danger("\The [src] knows that you're not the original owner, and has locked you out of it!"))
		return TRUE
	else if(!owner)
		bind_to_owner(user)
	user.set_machine(src)
	tgui_interact(user)
	return TRUE

DECLARE_UI(/obj/item/technomancer_catalog, "TechnomancerCatalog", UI_TITLE("Catalog"))

/obj/item/technomancer_catalog/tgui_data(mob/user)
	var/list/data = list()
	data["tab"] = tab
	data["spell_tab"] = spell_tab
	data["budget"] = budget
	data["max_budget"] = max_budget
	data["spell_categories"] = list(ALL_SPELLS, OFFENSIVE_SPELLS, DEFENSIVE_SPELLS, UTILITY_SPELLS, SUPPORT_SPELLS)
	var/list/spells = list()
	for(var/datum/technomancer/spell/s in spell_instances)
		spells += list(list(
			"name" = s.name,
			"desc" = s.desc,
			"cost" = s.cost,
			"spell_power_desc" = s.spell_power_desc || "",
			"enhancement_desc" = s.enhancement_desc || "",
			"category" = s.category,
			"hidden" = !!s.hidden,
		))
	data["spells"] = spells
	var/list/equipment = list()
	for(var/datum/technomancer/equipment/e in equipment_instances)
		equipment += list(list("name" = e.name, "desc" = e.desc, "cost" = e.cost))
	data["equipment"] = equipment
	var/list/consumables = list()
	for(var/datum/technomancer/consumable/c in consumable_instances)
		consumables += list(list("name" = c.name, "desc" = c.desc, "cost" = c.cost))
	data["consumables"] = consumables
	var/list/assistance = list()
	for(var/datum/technomancer/assistance/a in assistance_instances)
		assistance += list(list("name" = a.name, "desc" = a.desc, "cost" = a.cost))
	data["assistance"] = assistance
	return data

/obj/item/technomancer_catalog/ui_act_allowed(mob/user, action, datum/tgui/ui, datum/tgui_state/state)
	if(!..())
		return FALSE
	var/mob/living/carbon/human/H = ui.user
	H.set_machine(src)
	if(H.stat || H.restrained())
		return FALSE
	if(!ishuman(H))
		return FALSE
	if(H != owner)
		to_chat(H, "\The [src] won't allow you to do that, as you don't own \the [src]!")
		return FALSE
	if(loc != H && !(in_range(src, H) && istype(loc, /turf)))
		return FALSE
	return TRUE

UI_ACT(/obj/item/technomancer_catalog, "tab_choice", ui_act_tab_choice, UI_ARG_NUM("tab"))
UI_ACT_PROC(/obj/item/technomancer_catalog, ui_act_tab_choice)
	tab = params["tab"]
	return TRUE

UI_ACT(/obj/item/technomancer_catalog, "spell_category", ui_act_spell_category, UI_ARG_VALUE("category"))
UI_ACT_PROC(/obj/item/technomancer_catalog, ui_act_spell_category)
	spell_tab = params["category"]
	return TRUE

UI_ACT(/obj/item/technomancer_catalog, "spell_choice", ui_act_spell_choice, UI_ARG_VALUE("name"))
UI_ACT_PROC(/obj/item/technomancer_catalog, ui_act_spell_choice)
	var/mob/living/carbon/human/H = ui.user
	H.set_machine(src)
	var/datum/technomancer/new_spell = null
	for(var/datum/technomancer/spell/s in spell_instances)
		if(s.name == params["name"])
			new_spell = s
			break
	var/obj/item/technomancer_core/core = null
	if(istype(H.get_equipped_item(SLOT_ID_BACK), /obj/item/technomancer_core))
		core = H.get_equipped_item(SLOT_ID_BACK)
	if(new_spell && core)
		if(new_spell.cost <= budget)
			if(!core.has_spell(new_spell))
				budget -= new_spell.cost
				to_chat(H, span_notice("You have just bought [new_spell.name]."))
				core.add_spell(new_spell.obj_path, new_spell.name, new_spell.ability_icon_state)
			else
				to_chat(H, span_danger("You already have [new_spell.name]!"))
		else
			to_chat(H, span_danger("You can't afford that!"))
	return TRUE

UI_ACT(/obj/item/technomancer_catalog, "item_choice", ui_act_item_choice, UI_ARG_VALUE("name"))
UI_ACT_PROC(/obj/item/technomancer_catalog, ui_act_item_choice)
	var/mob/living/carbon/human/H = ui.user
	H.set_machine(src)
	var/datum/technomancer/desired = null
	for(var/datum/technomancer/o in equipment_instances + consumable_instances + assistance_instances)
		if(o.name == params["name"])
			desired = o
			break
	if(desired)
		if(desired.cost <= budget)
			budget -= desired.cost
			to_chat(H, span_notice("You have just bought \a [desired.name]."))
			var/obj/O = new desired.obj_path(get_turf(H))
			registry_join(REGISTRY_TECHNOMANCER_BELONGINGS, O)
		else
			to_chat(H, span_danger("You can't afford that!"))
	return TRUE

UI_ACT(/obj/item/technomancer_catalog, "refund_functions", ui_act_refund_functions)
UI_ACT_PROC(/obj/item/technomancer_catalog, ui_act_refund_functions)
	var/mob/living/carbon/human/H = ui.user
	H.set_machine(src)
	var/turf/T = get_turf(H)
	if(T && (T.z in using_map.player_levels))
		to_chat(H, span_danger("You can only refund at your base, it's too late now!"))
		return TRUE
	var/obj/item/technomancer_core/core = null
	if(istype(H.get_equipped_item(SLOT_ID_BACK), /obj/item/technomancer_core))
		core = H.get_equipped_item(SLOT_ID_BACK)
	if(core)
		for(var/obj/spellbutton/spell in core.spells)
			for(var/datum/technomancer/spell/spell_datum in spell_instances)
				if(spell_datum.obj_path == spell.spellpath)
					budget += spell_datum.cost
					core.remove_spell(spell)
					break
	return TRUE

/// Old attackby.
/obj/item/technomancer_catalog/proc/interaction_item(mob/user, atom/movable/AM, datum/interaction/interaction)
	var/turf/T = get_turf(user)
	if(T && (T.z in using_map.player_levels))
		to_chat(user, span_danger("You can only refund at your base, it's too late now!"))
		return INTERACTION_HANDLED_PASS
	for(var/datum/technomancer/equipment/E in equipment_instances + assistance_instances)
		if(AM.type == E.obj_path) // We got a match.
			if(budget + E.cost > max_budget)
				to_chat(user, span_warning("\The [src] will not allow you to overflow your maximum budget by refunding that."))
				return INTERACTION_HANDLED_PASS
			else
				budget = budget + E.cost
				to_chat(user, span_notice("You've refunded \the [AM]."))

				// We sadly need to do special stuff here or else people who refund cores with spells will lose points permanently.
				if(istype(AM, /obj/item/technomancer_core))
					var/obj/item/technomancer_core/core = AM
					for(var/obj/spellbutton/spell in core.spells)
						for(var/datum/technomancer/spell/spell_datum in spell_instances)
							if(spell_datum.obj_path == spell.spellpath)
								budget += spell_datum.cost
								to_chat(user, span_notice("[spell.name] was inside \the [core], and was refunded."))
								core.remove_spell(spell)
								break
				qdel(AM)
				return INTERACTION_HANDLED_PASS
	to_chat(user, span_warning("\The [src] is unable to refund \the [AM]."))
	return INTERACTION_HANDLED_PASS

#undef ALL_SPELLS
