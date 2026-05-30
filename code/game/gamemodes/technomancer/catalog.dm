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
	var/list/spell_instances = list()
	var/list/equipment_instances = list()
	var/list/consumable_instances = list()
	var/list/assistance_instances = list()
	var/tab = 4 // Info tab, so new players can read it before doing anything.
	var/spell_tab = ALL_SPELLS
	var/show_scepter_text = 0
	var/universal = FALSE //VOREStation Add - Allows non-technomancers to use this catalog

/obj/item/technomancer_catalog/apprentice
	name = "apprentice's catalog"
	budget = 700
	max_budget = 700

/obj/item/technomancer_catalog/master //for badmins, I suppose
	name = "master's catalog"
	budget = 2000
	max_budget = 2000

//VOREStation Add
/obj/item/technomancer_catalog/universal
	name = "universal catalog"
	desc = "A catalog to be used with the 'Universal Core', its contents shamelessly \
	copied by an unknown designer from some group of 'technomancers' or another.<br>\
	The back of the book has " + span_italics("'Export Edition'") + " stamped on it."
	budget = 700
	max_budget = 700
	universal = TRUE
//VOREStation Add End

// Proc: bind_to_owner()
// Parameters: 1 (new_owner - mob that the book is trying to bind to)
// Description: Links the catalog to hopefully the technomancer, so that only they can access it.
/obj/item/technomancer_catalog/proc/bind_to_owner(mob/living/carbon/human/new_owner)
	if(!owner && (GLOB.technomancers.is_antagonist(new_owner.mind) || universal)) //VOREStation Edit - Universal catalogs
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
	if(!spell_instances.len)
		for(var/S in GLOB.all_technomancer_spells)
			spell_instances += new S()
	if(!equipment_instances.len)
		for(var/E in GLOB.all_technomancer_equipment)
			equipment_instances += new E()
	if(!consumable_instances.len)
		for(var/C in GLOB.all_technomancer_consumables)
			consumable_instances += new C()
	if(!assistance_instances.len)
		for(var/A in GLOB.all_technomancer_assistance)
			assistance_instances += new A()

/obj/item/technomancer_catalog/apprentice/set_up()
	..()
	for(var/datum/technomancer/assistance/apprentice/A in assistance_instances)
		assistance_instances.Remove(A)

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

// DQEdit Start — TGUI migration: full structured data, no embedded
// byond:// hrefs. All actions dispatched via tgui_act.
/obj/item/technomancer_catalog/attack_self(mob/user)
	. = ..(user)
	if(.)
		return TRUE
	if(!user)
		return
	if(owner && user != owner)
		to_chat(user, span_danger("\The [src] knows that you're not the original owner, and has locked you out of it!"))
		return
	else if(!owner)
		bind_to_owner(user)
	user.set_machine(src)
	tgui_interact(user)

/obj/item/technomancer_catalog/tgui_interact(mob/user, datum/tgui/ui)
	ui = SStgui.try_update_ui(user, src, ui)
	if(!ui)
		ui = new(user, src, "TechnomancerCatalog", "Catalog")
		ui.open()

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

/obj/item/technomancer_catalog/tgui_act(action, list/params)
	. = ..()
	if(.)
		return
	var/mob/living/carbon/human/H = usr
	if(H.stat || H.restrained())
		return TRUE
	if(!ishuman(H))
		return TRUE
	if(H != owner)
		to_chat(H, "\The [src] won't allow you to do that, as you don't own \the [src]!")
		return TRUE
	if(loc != H && !(in_range(src, H) && istype(loc, /turf)))
		return TRUE
	H.set_machine(src)
	switch(action)
		if("tab_choice")
			tab = text2num(params["tab"])
			return TRUE
		if("spell_category")
			spell_tab = params["category"]
			return TRUE
		if("spell_choice")
			var/datum/technomancer/new_spell = null
			for(var/datum/technomancer/spell/s in spell_instances)
				if(s.name == params["name"])
					new_spell = s
					break
			var/obj/item/technomancer_core/core = null
			if(istype(H.back, /obj/item/technomancer_core))
				core = H.back
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
		if("item_choice")
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
					GLOB.technomancer_belongings.Add(O)
				else
					to_chat(H, span_danger("You can't afford that!"))
			return TRUE
		if("refund_functions")
			var/turf/T = get_turf(H)
			if(T.z in using_map.player_levels)
				to_chat(H, span_danger("You can only refund at your base, it's too late now!"))
				return TRUE
			var/obj/item/technomancer_core/core = null
			if(istype(H.back, /obj/item/technomancer_core))
				core = H.back
			if(core)
				for(var/obj/spellbutton/spell in core.spells)
					for(var/datum/technomancer/spell/spell_datum in spell_instances)
						if(spell_datum.obj_path == spell.spellpath)
							budget += spell_datum.cost
							core.remove_spell(spell)
							break
			return TRUE
// DQEdit End

/obj/item/technomancer_catalog/attackby(atom/movable/AM, mob/user)
	var/turf/T = get_turf(user)
	if(T.z in using_map.player_levels)
		to_chat(user, span_danger("You can only refund at your base, it's too late now!"))
		return
	for(var/datum/technomancer/equipment/E in equipment_instances + assistance_instances)
		if(AM.type == E.obj_path) // We got a match.
			if(budget + E.cost > max_budget)
				to_chat(user, span_warning("\The [src] will not allow you to overflow your maximum budget by refunding that."))
				return
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
				return
	to_chat(user, span_warning("\The [src] is unable to refund \the [AM]."))

#undef ALL_SPELLS
