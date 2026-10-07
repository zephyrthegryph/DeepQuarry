/obj/machinery/maint_vendor
	name = "\improper Large Decrepit Machine"
	desc = "A long since abandoned \"trash 4 cash\" rewards kiosk. Now featuring a state of the art, monochrome holographic tube display!"
	icon = 'code/modules/maint_recycler/icons/maint_vendor.dmi'
	icon_state = "default"
	clicksound = SFX_RECYCLER_TYPING

	anchored = TRUE
	density = TRUE
	unacidable = TRUE
	resistance_flags = INDESTRUCTIBLE
	use_power = USE_POWER_IDLE
	idle_power_usage = 10

	description_fluff = "While RSG's \"Trash 4 Cash\" recycling campaign came to an end decades ago, the underlying systems still work as well as ever thanks to an underground network of mega-dweebs and other assorted idiots maintaining it."

	//wide sprite
	pixel_x = -8

	var/item_creation_energy_use = 400 //old and clunky

	// ALLOW(instance_list): d: filled in Initialize with the vendor stock and shuffled
	var/list/product_datums = list() //assoc list of obj spawn type to datum
	var/is_on = FALSE
	var/light_range_on = 2
	var/light_power_on = 1
	light_color = "#0f8f0f"

	var/obj/effect/overlay/recycler/monitor_screen

CAPABILITIES(/obj/machinery/maint_vendor)
	after_init(0, then(PROC_REF(move_after_init)))
	owns_one(nameof(monitor_screen), /obj/effect/overlay/recycler)
	owns_many(nameof(product_datums))
	interface("RecyclerVendor")
	op("purchase", ui_act("purchase", arg("index", num())), then(PROC_REF(ui_act_purchase)))
	op("open_ui_impl", hand(), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), then(PROC_REF(interaction_open_ui_impl)))

/obj/machinery/maint_vendor/dismantle()
	return FALSE //we don't want something as important as this to be able to be disassembled. it's a scene tool, technically.

/obj/machinery/maint_vendor/Initialize(mapload)
	. = ..()
	for(var/t in subtypesof(/datum/maint_recycler_vendor_entry) - /datum/maint_recycler_vendor_entry)
		var/datum/maint_recycler_vendor_entry/entry = new t()
		entry.initialize()
		rel_add(src, nameof(product_datums), entry)
	//move to relevant location
	rel_set(src, nameof(monitor_screen), new /obj/effect/overlay/recycler)
	monitor_screen.plane = PLANE_LIGHTING_ABOVE
	monitor_screen.layer = src.layer + 0.1
	monitor_screen.icon = src.icon
	monitor_screen.icon_state = "screen_off"

	src.vis_contents |= monitor_screen
	shuffle_inplace(product_datums) //looks weird to have a billion carpet entries right next to eachother

/// A mapped one moves to a marker, once the markers exist.
/obj/machinery/maint_vendor/proc/move_after_init(datum/act/timer/A)
	if(!A.mapload)
		return
	move_to_marker()

/obj/machinery/maint_vendor/proc/move_to_marker()
	if(GLOB.recycler_vendor_locations.len > 0)
		var/turf/spot = pick(GLOB.recycler_vendor_locations)
		forceMove(spot)
		dir = SOUTH
		log_admin("[src] has been placed at [loc], [x],[y],[z]")
		testing("[src] has been placed at [loc], [x],[y],[z]")
	else
		log_and_message_admins("[src] tried to move itself, but there was nowhere for it to go! (<A href='byond://?_src_=holder;[HrefToken()];adminplayerobservecoodjump=1;X=[x];Y=[y];Z=[z]'>JMP</a>)", null)


/obj/machinery/maint_vendor/proc/interaction_open_ui_impl(datum/act/op/A)
	var/mob/user = A.actor
	add_fingerprint(user)
	tgui_interact(user)

	if(!is_on)
		set_on_state(TRUE)
	return TRUE

/obj/machinery/maint_vendor/proc/attempt_purchase(mob/user, datum/maint_recycler_vendor_entry/entry)
	if(!istype(entry))
		return
	if(entry.purchased_by == null)
		entry.purchased_by = list()
	if(!entry.purchased_by[user.client.ckey])
		entry.purchased_by[user.client.ckey] = 0
	if(!can_user_purchase(user,entry))
		return

	dispense_item_from_datum(user,entry)
	credit_user(user,-entry.item_cost)
	entry.purchased_by[user.client.ckey] += 1

/obj/machinery/maint_vendor/proc/purchase_failed(mob/user, reason)
	if(prob(95))
		set_screen_state("screen_deny",10)
	else
		set_screen_state("screen_mad",10)
	audible_message("[src] states, \"PURCHASE DENIED: [reason].\" ", "\The [src]'s screen briefly flashes to an X!" , runemessage = "X")
	play_sfx(src, SFX_RECYCLER_GENERALDENY)
	return

/obj/machinery/maint_vendor/proc/dispense_item_from_datum(mob/user, datum/maint_recycler_vendor_entry/used_entry)
	if(!used_entry || !used_entry.object_type_to_spawn)
		to_chat(user,span_warning("What the fuck?? this is a scam! Nothing happened!"))
		return;

	play_sfx(src, SFX_RECYCLER_EJECTGOODIES)
	used_entry.spawn_with_delay(src);
	audible_message("[src] states, \"[used_entry.tagline]\" ", "\The [src]'s screen briefly flashes a $!" , runemessage = "$$$")
	if(prob(95))
		set_screen_state("screen_cashout",10)
	else
		set_screen_state("screen_happy",10)

/obj/machinery/maint_vendor/proc/can_user_purchase(mob/user,datum/maint_recycler_vendor_entry/attempted_entry)
	if(!user_balance(user) || user_balance(user) < attempted_entry.item_cost)
		purchase_failed(user, "Insufficent Balance")
		return FALSE
	if(attempted_entry.per_person_cap > 0 && attempted_entry.purchased_by[user.client.ckey] >= attempted_entry.per_person_cap)
		purchase_failed(user, "Limited Per-Person Supply")
		return FALSE
	if(attempted_entry.per_round_cap > 0 && attempted_entry.getPurchasedCount() >= attempted_entry.per_round_cap)
		purchase_failed(user, "Out of Stock")
		return FALSE
	if(LAZYLEN(attempted_entry.required_access)) //access check
		req_one_access = attempted_entry.required_access
		if(!allowed(user))
			purchase_failed(user, "Access Denied")
			req_one_access = list()
			return FALSE
		req_one_access = list()

	return TRUE

/// Appearance reader: TRUE while the vendor has power (product display glow).
/obj/machinery/maint_vendor/proc/appearance_powered()
	return power_lost() ? FALSE : TRUE

//product display. screen is distinct.
DECLARE_APPEARANCE(/obj/machinery/maint_vendor, "appearance_powered", list(
	"1" = list(APPEARANCE_OVERLAYS = list("passiveGlow")),
))
APPEARANCE_EMISSIVE(/obj/machinery/maint_vendor, "appearance_powered", list("1" = "passiveGlow"))

/obj/machinery/maint_vendor/proc/set_screen_state(state, duration = 10)
	if(!is_on) return
	monitor_screen.icon_state = state
	after(src, duration, PROC_REF(reset_screen_state))

/obj/machinery/maint_vendor/proc/reset_screen_state()
	if(!is_on)
		monitor_screen.icon_state = "screen_off"
	else
		monitor_screen.icon_state = "screen_default"

//TGUI junk

/obj/machinery/maint_vendor/ui_assets(mob/user)
	return list(
		get_asset_datum(/datum/asset/simple/maint_recycler), //for the logos
		get_asset_datum(/datum/asset/spritesheet_batched/maint_vendor) //for the item icons
	)

/obj/machinery/maint_vendor/proc/ui_act_purchase(datum/act/op/A, index)
	var/mob/user = A.actor
	var/datum/maint_recycler_vendor_entry/entry = product_datums[index]
	attempt_purchase(user,entry)
	return TRUE

/obj/machinery/maint_vendor/tgui_close(mob/user)
	. = ..()
	if(LAZYLEN(open_tguis) > 0) return
	set_on_state(FALSE)

/// /obj/machinery/maint_vendor's window data.
/obj/machinery/maint_vendor/ui_data(datum/act/eval/A)
	var/mob/user = A.actor
	var/list/data = list()
	var/list/items = list()

	for(var/i = 1 to product_datums.len)
		var/datum/maint_recycler_vendor_entry/entry = product_datums[i]
		UNTYPED_LIST_ADD(items,list(
			"category" = entry.vendor_category,
			"name" = entry.name,
			"cost" = entry.item_cost,
			"desc" = entry.desc,
			"ad" = entry.ad_message,
			"icon" = entry.icon_state,
			"index" = i
		))
	data["items"] = items
	data["userBalance"] = user_balance(user)
	data["userName"] = user.name

	return data

//utility

/obj/machinery/maint_vendor/proc/user_balance(mob/user)
	return user.client?.prefs?.read_preference(/datum/preference/numeric/recycler_points)

/obj/machinery/maint_vendor/proc/credit_user(mob/user, amount)
	if(!user || !user.client || !user.client.prefs) return
	var/currentValue = 	user.client?.prefs?.read_preference(/datum/preference/numeric/recycler_points)
	user.client?.prefs?.write_preference_by_type(/datum/preference/numeric/recycler_points, currentValue + amount)

/obj/machinery/maint_vendor/proc/set_on_state(state)
	if(is_on == state) return
	is_on = state
	if(is_on)
		play_sfx(src, SFX_RECYCLER_INITIALBOOT)
		set_light(light_range_on, light_power_on)
		monitor_screen.icon_state = "screen_default"
	else
		play_sfx(src, SFX_MACHINES_TERMINAL_OFF)
		set_light(0)
		monitor_screen.icon_state = "screen_off"

/obj/machinery/maint_vendor/power_change()
	. = ..()
	if(power_lost())
		set_on_state(FALSE)
