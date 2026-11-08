/datum/asset/spritesheet_batched/vending
	name = "vending"

/datum/asset/spritesheet_batched/vending/entry_sources()
	. = list()
	for(var/product_ref in product_types())
		. += product_ref

/datum/asset/spritesheet_batched/vending/add_entry_for(product_ref)
	var/list/spec = vending_product_icon_spec(product_ref)
	if(!spec)
		return
	var/datum/universal_icon/I
	if(spec[4])
		I = uni_icon(spec[1], spec[2], SOUTH)
		if(spec[3])
			I.blend_color(spec[3], ICON_MULTIPLY)
	else
		I = uni_icon('icons/turf/floors.dmi', "", SOUTH)
	insert_icon(vending_product_image_id(product_ref), I)

/// The picture of a vendor product (a path, or a VARIANT() reference: the picture is the parent's): list(icon file, state, colour to multiply
/// or null, whether the state exists), or null for a reference that is no atom. A state that does not exist is logged; the picture is a blank.
/proc/vending_product_icon_spec(product_ref)
	var/atom/item = saved_type_path(product_ref)
	if(!ispath(item, /atom))
		return null
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
	var/c = initial(item.color)
	var/list/states = icon_states_fast(icon_file)
	var/valid = (icon_state in states)
	if(!valid)
		// Logged, not thrown: the sheet is built inside the asset loading service's generate step, where a runtime would end the build.
		log_world("vending product picture: [item] does not have a valid icon state, icon=[icon_file], icon_state=[json_encode(icon_state)]; using a blank")
	return list(icon_file, icon_state, (!isnull(c) && c != "#FFFFFF") ? c : null, valid)

/// The id a product's picture has in the sheet (and as its own asset): its path without /obj/item/, slashes as dashes.
/proc/vending_product_image_id(product_ref)
	return replacetext(replacetext("[product_ref]", "/obj/item/", ""), "/", "-")

/// The product's picture as an asset of its own (cut, coloured, hashed and registered once for the life of the world): its asset name. What the
/// vendor window shows, so opening a vendor sends a few small pictures and not the whole sheet of every vendor's stock.
DECLARE_SHARED_CACHE(vending_product_asset, GLOBAL_PROC_REF(build_vending_product_asset), SC_NEVER)

/proc/build_vending_product_asset(product_ref)
	var/list/spec = vending_product_icon_spec(product_ref)
	var/icon/picture = (spec && spec[4]) ? icon(spec[1], spec[2], SOUTH, 1) : icon('icons/turf/floors.dmi', "", SOUTH, 1)
	if(spec?[3])
		picture.Blend(spec[3], ICON_MULTIPLY)
	// An uncoloured state of a compiled-in file hashes its rsc copy directly; a coloured one needs the slower copy-to-file hash.
	var/icon_path = (spec && spec[4] && !spec[3]) ? get_icon_dmi_path(spec[1]) : null
	var/list/name_and_ref = generate_and_hash_rsc_file(picture, icon_path)
	var/key = "vendprod.[name_and_ref[3]].png"
	if(!SSassets.cached_asset(key))
		SSassets.register_asset(key, name_and_ref[1], name_and_ref[2], icon_path)
	return key

/// The address of the product's picture for `viewer`, the picture sent to that client (once: the transport remembers what it sent).
/proc/vending_product_image_url(product_ref, client/viewer)
	if(!viewer)
		return null
	var/key = CACHED_KEY(vending_product_asset, "[product_ref]", product_ref)
	SSassets.send_assets(viewer, key)
	return SSassets.get_asset_url(key)

/// Every product type a vendor stocks, as an assoc list (type -> TRUE). Vendors are content: their file overrides this
/// (code/content/economy/vending.dm), so the sheet knows every vendor's stock, mapped or not, without the library naming them.
/datum/asset/spritesheet_batched/vending/proc/product_types()
	return list()
