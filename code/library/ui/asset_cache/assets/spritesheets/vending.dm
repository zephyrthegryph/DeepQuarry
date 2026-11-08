/datum/asset/spritesheet_batched/vending
	name = "vending"

/datum/asset/spritesheet_batched/vending/entry_sources()
	. = list()
	for(var/product_ref in product_types())
		. += product_ref

/datum/asset/spritesheet_batched/vending/add_entry_for(product_ref)
	// A product is a path, or a VARIANT() reference (a collapsed type's old path): the picture is the parent's, the id is the reference's.
	var/atom/item = saved_type_path(product_ref)
	if(!ispath(item, /atom))
		return

	var/icon_file = initial(item.icon)
	var/icon_state = initial(item.icon_state)

	// I really don't like the fact that I have to do this, but what the hell else *can* I do to make all of these
	// random special items work?
	if(ispath(item, /obj/item/reagent_containers/food/drinks/glass2) && !ispath(item, /obj/item/reagent_containers/food/drinks/glass2/fitnessflask))
		var/obj/item/reagent_containers/food/drinks/glass2/G = item
		icon_state = initial(G.base_icon)
	if(ispath(item, /obj/item/reagent_containers/hypospray/autoinjector))
		icon_state += "0"
	if(ispath(item, /obj/item/melee/shock_maul))
		icon_state += "0"

	var/datum/universal_icon/I

	var/icon_states_list = icon_states_fast(icon_file)
	if(icon_state in icon_states_list)
		I = uni_icon(icon_file, icon_state, SOUTH)
		var/c = initial(item.color)
		if(!isnull(c) && c != "#FFFFFF")
			I.blend_color(c, ICON_MULTIPLY)
	else
		var/icon_states_string
		for(var/an_icon_state in icon_states_list)
			if(!icon_states_string)
				icon_states_string = "[json_encode(an_icon_state)]([REF(an_icon_state)])"
			else
				icon_states_string += ", [json_encode(an_icon_state)]([REF(an_icon_state)])"
		// Logged, not thrown: the sheet is built inside the asset loading service's generate step (deferred since the boot move), where a runtime
		// aborts the generation half way and leaves the service waiting for it for ever (deferred assets never settle). The product shows a blank.
		log_world("vending spritesheet: [item] does not have a valid icon state, icon=[icon_file], icon_state=[json_encode(icon_state)]([REF(icon_state)]), icon_states=[icon_states_string]; using a blank")
		I = uni_icon('icons/turf/floors.dmi', "", SOUTH)

	var/imgid = replacetext(replacetext("[product_ref]", "/obj/item/", ""), "/", "-")

	insert_icon(imgid, I)

/// Every product type a vendor stocks, as an assoc list (type -> TRUE). Vendors are content: their file overrides this
/// (code/content/economy/vending.dm), so the sheet knows every vendor's stock, mapped or not, without the library naming them.
/datum/asset/spritesheet_batched/vending/proc/product_types()
	return list()
