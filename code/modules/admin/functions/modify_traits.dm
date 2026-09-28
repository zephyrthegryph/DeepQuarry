/// Allow admin to add or remove traits of datum
/datum/admins/proc/modify_traits(datum/D)
	if(!D)
		return

	om_ask(usr, /datum/om/prompt/choice/modify_trait, PROC_REF(ask_trait), message = "Remove/Add?", choices = list("Add","Remove"), target = D)

/// One step of modifying a datum's traits; the answers so far ride along to the next step.
/datum/om/prompt/choice/modify_trait
	title = "Trait Remove/Add"
	requires = PROMPT_ADMIN(R_VAREDIT)
	var/datum/target
	/// "Add" or "Remove".
	var/mode
	/// The trait's name.
	var/trait
	/// "All" or "Specific" (removing).
	var/specific

/// The traits of D that can be added ("Add") or removed ("Remove"), by name.
/datum/admins/proc/modifiable_traits(datum/D, add_or_remove)
	var/list/availible_traits = list()

	switch(add_or_remove)
		if("Add")
			for(var/key in GLOB.traits_by_type)
				if(istype(D,key))
					var/list/traits_for_type = GLOB.traits_by_type[key]
					for(var/trait_name in traits_for_type)
						availible_traits[trait_name] = traits_for_type[trait_name]
		if("Remove")
			if(!GLOB.trait_name_map)
				GLOB.trait_name_map = generate_trait_name_map()
			for(var/trait in trait_list(D))
				var/name = GLOB.trait_name_map[trait] || trait
				availible_traits[name] = trait

	return availible_traits

/datum/admins/proc/ask_trait(datum/om/prompt/choice/modify_trait/ask)
	om_ask(ask.answerer, /datum/om/prompt/choice/modify_trait, PROC_REF(ask_trait_source_kind), title = "Trait", message = "Select trait to modify", choices = modifiable_traits(ask.target, ask.choice), target = ask.target, mode = ask.choice)

/datum/admins/proc/ask_trait_source_kind(datum/om/prompt/choice/modify_trait/ask)
	if(ask.mode != "Remove")
		traits_answered(ask.target, ask.mode, ask.choice)
		return
	om_ask(ask.answerer, /datum/om/prompt/choice/modify_trait, PROC_REF(ask_trait_source), message = "All or specific source ?", choices = list("All","Specific"), target = ask.target, mode = ask.mode, trait = ask.choice)

/datum/admins/proc/ask_trait_source(datum/om/prompt/choice/modify_trait/ask)
	if(ask.choice != "Specific")
		traits_answered(ask.target, ask.mode, ask.trait)
		return
	var/list/traits = modifiable_traits(ask.target, "Remove")
	om_ask(ask.answerer, /datum/om/prompt/choice/modify_trait, PROC_REF(trait_source_chosen), message = "Source to be removed", choices = trait_source_names(ask.target, traits[ask.trait]), target = ask.target, mode = ask.mode, trait = ask.trait, specific = ask.choice)

/datum/admins/proc/trait_source_chosen(datum/om/prompt/choice/modify_trait/ask)
	var/list/traits = modifiable_traits(ask.target, "Remove")
	for(var/datum/source as anything in trait_sources(ask.target, traits[ask.trait]))
		if("[source]" == ask.choice)
			traits_answered(ask.target, ask.mode, ask.trait, source)
			return

/// The names of the sources granting `trait`, for the pick list.
/datum/admins/proc/trait_source_names(datum/D, trait)
	. = list()
	for(var/datum/source as anything in trait_sources(D, trait))
		. |= "[source]"

/// Applies the answers: `source` is null to remove the trait from every source.
/datum/admins/proc/traits_answered(datum/D, mode, trait_name, source)
	var/list/availible_traits = modifiable_traits(D, mode)
	var/chosen_trait = availible_traits[trait_name]
	if(!chosen_trait)
		return
	switch(mode)
		if("Add") //Not doing source choosing here intentionally to make this bit faster to use, you can always vv it.
			add_trait(D,chosen_trait,"adminabuse")
		if("Remove")
			remove_trait(D,chosen_trait,source)
