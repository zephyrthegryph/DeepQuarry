// I placed this here because of how relevant it is.
// You place this in your uplinkable item to check if an uplink is active or not.
// If it is, it will display the uplink menu and return 1, else it'll return false.
// If it returns true, I recommend closing the item's normal menu
/obj/item/proc/active_uplink_check(mob/user as mob)
	// Activates the uplink if it's active
	if(item_hidden_uplink(src))
		if(item_hidden_uplink(src).active)
			item_hidden_uplink(src).trigger(user)
			return TRUE
	return FALSE

/obj/item/uplink
	var/welcome = "Welcome, Operative"	// Welcoming menu message
	var/list/ItemsCategory				// List of categories with lists of items
	var/list/ItemsReference				// List of references with an associated item
	var/list/nanoui_items				// List of items for NanoUI use
	var/faction = ""					//Antag faction holder.

	var/offer_time = 10 MINUTES			//The time increment per discount offered
	EXPIRY_DECLARE(next_offer_time)
	var/datum/uplink_item/discount_item_static	//The item to be discounted
	var/discount_amount					//The amount as a percent the item will be discounted by
	var/compact_mode = FALSE

	icon = 'icons/obj/device.dmi'
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

// A new discount every offer_time (only /hidden makes use of this; the base proc is a stub).
DECLARE_REPEAT(/obj/item/uplink, "offer_time", next_offer, null)

/obj/item/uplink/get_item_cost(item_type, item_cost)
	return (discount_item() && (item_type == discount_item())) ? max(1, round(item_cost*discount_amount)) : item_cost

/obj/item/uplink/proc/next_offer()
	return //Stub, used on children.

// HIDDEN UPLINK - Can be stored in anything but the host item has to have a trigger for it.
/** How to create an uplink in 3 easy steps!
 *
 * 1. All obj/item 's have a hidden_uplink var. By default it's null. Give the item one with "new(src)", it must be in it's contents. Feel free to add "uses".
 *
 * 2. Code in the triggers. Use check_trigger for this, I recommend closing the item's menu if it returns true.
 * The var/value is the value that will be compared with the var/target. If they are equal it will activate the menu.
 *
 * 3. If you want the menu to stay until the users locks his uplink, add an active_uplink_check(mob/user as mob) in your interact/attack_hand proc.
 * Then check if it's true, if true return. This will stop the normal menu appearing and will instead show the uplink menu.
 */

/obj/item/uplink/hidden
	name = "hidden uplink"
	desc = "There is something wrong if you're examining this."
	var/active = 0
	var/exploit_id								// Id of the current exploit record we are viewing
	var/selected_cat

// The hidden uplink MUST be inside an obj/item's contents.
/obj/item/uplink/hidden/Initialize(mapload)
	. = ..()
	if(!isitem(loc))
		return INITIALIZE_HINT_QDEL

/obj/item/uplink/hidden/next_offer()
	discount_item_static = GLOB.default_uplink_selection.get_random_item(INFINITY)
	discount_amount = pick(90;0.9, 80;0.8, 70;0.7, 60;0.6, 50;0.5, 40;0.4, 30;0.3, 20;0.2, 10;0.1)
	EXPIRY_SET(src, next_offer_time, offer_time, CLOCK_WORLD)
	SStgui.update_uis(src)

// Toggles the uplink on and off. Normally this will bypass the item's normal functions and go to the uplink menu, if activated.
/obj/item/uplink/hidden/proc/toggle()
	active = !active

// Directly trigger the uplink. Turn on if it isn't already.
/obj/item/uplink/hidden/proc/trigger(mob/user as mob)
	if(!active)
		toggle()
	tgui_interact(user)

// Checks to see if the value meets the target. Like a frequency being a traitor_frequency, in order to unlock a headset.
// If true, it accesses trigger() and returns 1. If it fails, it returns false. Use this to see if you need to close the
// current item's menu.
/obj/item/uplink/hidden/proc/check_trigger(mob/user as mob, value, target)
	if(value == target)
		trigger(user)
		return TRUE
	return FALSE

// Legacy
/obj/item/uplink/hidden/interact(mob/user)
	tgui_interact(user)

/*****************
 * Uplink TGUI
 *****************/
/obj/item/uplink/tgui_host()
	return loc

/obj/item/uplink/hidden/ui_prepare(mob/user, datum/tgui/ui)
	if(!active)
		toggle()
	return TRUE

/obj/item/uplink/hidden/ui_data(datum/act/eval/A)
	var/list/data = list()
	data["compactMode"] = compact_mode
	var/list/merged_1 = ui_data_obj_item_uplink_hidden(A.actor, null, null)
	if(islist(merged_1))
		for(var/merged_key_1 in merged_1)
			data[merged_key_1] = merged_1[merged_key_1]
	return data

/// /obj/item/uplink/hidden's window data.
/obj/item/uplink/hidden/proc/ui_data_obj_item_uplink_hidden(mob/user, datum/tgui/ui, datum/tgui_state/state)
	if(!user.mind)
		return

	var/list/data = list()

	data["telecrystals"] = user.mind.tcrystals
	data["lockable"] = TRUE

	data["discount_name"] = discount_item() ? discount_item().name : ""
	data["discount_amount"] = (1-discount_amount)*100
	data["offer_expiry"] = worldtime2stationtime(next_offer_time)

	data["exploit"] = null
	data["locked_records"] = null

	if(exploit_id)
		for(var/datum/data/record/L in GLOB.data_core.locked)
			if(L.fields["id"] == exploit_id)
				data["exploit"] = list()  // Setting this to equal L.fields passes it's variables that are lists as reference instead of value.
								// We trade off being able to automatically add shit for more control over what gets passed to json
								// and if it's sanitized for html.
				data["exploit"]["nanoui_exploit_record"] = html_encode(L.fields["exploit_record"])                         		// Change stuff into html
				data["exploit"]["nanoui_exploit_record"] = replacetext(data["exploit"]["nanoui_exploit_record"], "\n", "<br>")    // change line breaks into <br>
				data["exploit"]["name"] =  html_encode(L.fields["name"])
				data["exploit"]["sex"] =  html_encode(L.fields["sex"])
				data["exploit"]["age"] =  html_encode(L.fields["age"])
				data["exploit"]["species"] =  html_encode(L.fields["species"])
				data["exploit"]["rank"] =  html_encode(L.fields["rank"])
				data["exploit"]["home_system"] =  html_encode(L.fields["home_system"])
				data["exploit"]["birthplace"] =  html_encode(L.fields["birthplace"])
				data["exploit"]["citizenship"] =  html_encode(L.fields["citizenship"])
				data["exploit"]["faction"] =  html_encode(L.fields["faction"])
				data["exploit"]["religion"] =  html_encode(L.fields["religion"])
				data["exploit"]["fingerprint"] =  html_encode(L.fields["fingerprint"])
				if(L.fields["antagvis"] == ANTAG_KNOWN || (faction == L.fields["antagfac"] && (L.fields["antagvis"] == ANTAG_SHARED)))
					data["exploit"]["antagfaction"] = html_encode(L.fields["antagfac"])
				else
					data["exploit"]["antagfaction"] = html_encode("None")
				break
	else
		var/list/permanentData = list()
		for(var/datum/data/record/L in sortRecord(GLOB.data_core.locked))
			permanentData.Add(list(list(
				"name" = L.fields["name"],
				"id" = L.fields["id"]
			)))
		data["locked_records"] = permanentData

	return data

/obj/item/uplink/hidden/tgui_static_data(mob/user)
	var/list/data = ..()

	data["categories"] = list()
	for(var/datum/uplink_category/category in GLOB.uplink.categories)
		var/list/cat = list(
				"name" = category.name,
				"items" = (category == selected_cat ? list() : null)
			)
		for(var/datum/uplink_item/item in category.items)
			var/cost = item.cost(src, user.mind.tcrystals) || "???"
			cat["items"] += list(list(
				"name" = item.name,
				"cost" = cost,
				"desc" = item.description(),
				"ref" = REF(item),
			))
		data["categories"] += list(cat)

	return data

/obj/item/uplink/hidden/tgui_status(mob/user, datum/tgui_state/state)
	if(!active)
		return STATUS_CLOSE
	return ..()

/obj/item/uplink/hidden/proc/ui_act_buy(datum/act/op/A, ref)
	var/mob/user = A.actor
	if(!isnull(ref) && !(ref in ui_source_glob_uplink_items()))
		return FALSE
	if(isnull(ref))
		return FALSE
	var/datum/uplink_item/UI = (ref)
	UI.buy(src, user)
	return TRUE

/obj/item/uplink/hidden/proc/ui_act_lock(datum/act/op/A)
	toggle()
	SStgui.close_uis(src)

CAPABILITIES(/obj/item/uplink/hidden)
	op("compact_toggle", ui_act(), then(PROC_REF(ui_act_compact_toggle)))
	interface("Uplink", title = "Remote Uplink", state = nameof(GLOB.tgui_deep_inventory_state))
	without("ui_open")
	op("buy", ui_act("buy", arg("ref", schema_ref())), then(PROC_REF(ui_act_buy)))
	op("lock", ui_act("lock"), then(PROC_REF(ui_act_lock)))
	op("select", ui_act("select", arg("category")), then(PROC_REF(ui_act_select)))
	op("view_exploits", ui_act("view_exploits", arg("id", num())), then(PROC_REF(ui_act_view_exploits)))

/obj/item/uplink/hidden/proc/ui_act_select(datum/act/op/A, category)
	selected_cat = category
	return TRUE

/obj/item/uplink/hidden/proc/ui_act_compact_toggle(datum/act/op/A)
	compact_mode = !compact_mode
	return OP_OK

/obj/item/uplink/hidden/proc/ui_act_view_exploits(datum/act/op/A, id)
	exploit_id = id
	return TRUE

/// The list the UI_ARG_REF rows resolve refs in.
/obj/item/uplink/hidden/proc/ui_source_glob_uplink_items()
	return GLOB.uplink.items

// PRESET UPLINKS
// A collection of preset uplinks.
//
// Includes normal radio uplink, multitool uplink,
// implant uplink (not the implant tool) and a preset headset uplink.

/obj/item/radio/uplink
	icon_state = "radio"
	uplink = TRUE

/obj/item/radio/uplink/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(hidden_uplink), new /obj/item/uplink/hidden(src))

/obj/item/radio/uplink/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE
	if(item_hidden_uplink(src))
		item_hidden_uplink(src).trigger(user)

/obj/item/multitool/uplink
	uplink = TRUE

/obj/item/multitool/uplink/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(hidden_uplink), new /obj/item/uplink/hidden(src))

/obj/item/multitool/uplink/interaction_self(mob/living/user, obj/item/held, datum/interaction/interaction)
	. = ..()
	if(.)
		return TRUE
	if(item_hidden_uplink(src))
		item_hidden_uplink(src).trigger(user)

/obj/item/radio/headset/uplink
	traitor_frequency = BEACON_FREQ

/obj/item/radio/headset/uplink/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(hidden_uplink), new /obj/item/uplink/hidden(src))

/// A shared definition (registered: never owned or cleared).
/obj/item/uplink/proc/discount_item() as /datum/uplink_item
	return discount_item_static
