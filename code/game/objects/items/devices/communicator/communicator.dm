// Communicators
//
// Allows ghosts to roleplay with crewmembers without having to commit to joining the round, and also allows communications between two communicators.

// List of core tabs the communicator can switch to
#define HOMETAB 1
#define PHONTAB 2
#define CONTTAB 3
#define MESSTAB 4
#define NEWSTAB 5
#define NOTETAB 6
#define WTHRTAB 7
#define MANITAB 8
#define SETTTAB 9

MATERIAL_MIX(/obj/item/communicator, list(MAT_STEEL = 30,MAT_GLASS = 10))
/obj/item/communicator
	name = "communicator"
	desc = "A personal device used to enable long range dialog between two people, utilizing existing telecommunications infrastructure to allow \
	communications across different stations, planets, or even star systems."
	icon = 'icons/obj/device.dmi'
	icon_state = "communicator"
	w_class = ITEMSIZE_SMALL
	slot_flags = SLOT_ID | SLOT_BELT
	show_messages = 1


	var/video_range = 3
	var/obj/machinery/camera/communicator/video_source	// Their camera
	var/obj/machinery/camera/communicator/camera		// Our camera

	var/list/voice_mobs
	var/list/voice_requests
	var/list/voice_invites

	var/list/im_contacts
	var/list/im_list

	var/note = "Thank you for choosing the T-14.2 Communicator, this is your notepad!" //Current note in the notepad function
	var/notehtml = ""

	var/fon = 0 // Internal light
	var/flum = 2 // Brightness

	var/list/modules = list( // ALLOW(instance_list): d: edited in place per instance (346 writers)
							list("module" = "Phone", "icon" = "phone", "number" = PHONTAB),
							list("module" = "Contacts", "icon" = "user", "number" = CONTTAB),
							list("module" = "Messaging", "icon" = "comment-alt", "number" = MESSTAB),
							list("module" = "News", "icon" = "newspaper", "number" = NEWSTAB), // Need a different icon,
							list("module" = "Note", "icon" = "sticky-note", "number" = NOTETAB),
							list("module" = "Weather", "icon" = "sun", "number" = WTHRTAB),
							list("module" = "Crew Manifest", "icon" = "crown", "number" = MANITAB), // Need a different icon,
							list("module" = "Settings", "icon" = "cog", "number" = SETTTAB),
							)	//list("module" = "Name of Module", "icon" = "icon name64", "number" = "what tab is the module")

	var/selected_tab = HOMETAB
	var/owner = ""
	var/occupation = ""
	var/alert_called = 0
	var/obj/machinery/exonet_node/node = null //Reference to the Exonet node, to avoid having to look it up so often.

	var/target_address = ""
	var/target_address_name = ""
	var/network_visibility = 1
	var/ringer = 1
	var/list/known_devices
	var/datum/exonet_protocol/exonet = null
	var/list/communicating
	var/update_ticks = 0
	var/newsfeed_channel = 0

	var/obj/item/card/id/id = null // ITION: Making it possible to slot an ID card into the Communicator so it can function as both.

	// If you turn this on, it changes the way communicator video works. User configurable option.
	var/selfie_mode = FALSE

	// Ringtones! (Based on the PDA ones)
	var/ttone = "beep" //The ringtone!
	pickup_sound = SFX_ITEMS_PICKUP_DEVICE
	drop_sound = SFX_ITEMS_DROP_DEVICE

// Proc: New()
// Parameters: None
// Description: Adds the new communicator to the global list of all communicators, sorts the list, obtains a reference to the Exonet node, then tries to
//				assign the device to the holder's name automatically in a spectacularly shitty way.
REGISTRY_MEMBERSHIP(/obj/item/communicator, REGISTRY_COMMUNICATORS)

/obj/item/communicator/Initialize(mapload)
	. = ..()
	rel_set(src, nameof(node), get_exonet_node())
	camera.name = "[src] #[rand(100,999)]"
	camera.c_tag = camera.name

	setup_tgui_camera()

/// The open connections (communicating is a relation list, voice_mobs an owned list): fields, so the
/// accessors and the framework's auto-clears (a partner or voice destroyed) re-evaluate the watchdog.
OM_FIELD_VIEW_OF(/obj/item/communicator, communicating, CHANGE_EXPLICIT)
OM_FIELD_VIEW_OF(/obj/item/communicator, voice_mobs, CHANGE_EXPLICIT)
/// The connection watchdog runs while a connection is open.
OM_DERIVE_FIELD(/obj/item/communicator, has_connections, list("communicating", "voice_mobs"))
/obj/item/communicator/proc/has_connections()
	return length(voice_mobs) || length(communicating)
DECLARE_PERIODIC_WHILE(/obj/item/communicator, PERIODIC_SLOW, "has_connections")
//This is a pretty terrible way of doing this.

// ITION START: Ayo communicator are better than PDAs /obj/item/communicator
// Proc: AltClick()
// Parameters: None
// Description: Checks if the user is made of silicon and returns if they are. If the user is not made of silicon and can use the communicator,
//              removes the ID from the communicator if it has one, or sends a chat message indicating that the communicator does not have an ID.

DECLARE_INTERACTIONS(/obj/item/communicator, \
	INTERACT_ALT("Remove ID", PROC_REF(interaction_alt)), \
	INTERACT_ITEM("Scan ID", PROC_REF(interaction_item)), \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_OBSERVER("View", PROC_REF(communicator_observer_use)), \
)

/// Old click_alt: eject the loaded ID.
/obj/item/communicator/proc/interaction_alt(mob/user, obj/item/held, datum/interaction/interaction)
	if(issilicon(user))
		return FALSE

	if(id)
		remove_id()
	else
		to_chat(user, span_notice("This Communicator does not have an ID in it."))
	return TRUE
// Proc: GetAccess()
// Parameters: None
// Description: Returns the access level of the communicator's ID, if it has one. If the communicator does not have an ID, the procedure returns the
//              access level of the object that contains the communicator.
/obj/item/communicator/GetAccess()
	if(id)
		return id.GetAccess()
	else
		return ..()

// Proc: GetID()
// Parameters: None
// Description: Returns the ID object associated with the communicator. If the communicator does not have an ID, the procedure returns null.
/obj/item/communicator/GetID()
	return id

// Proc: remove_id()
// Parameters: None
// Description: If the communicator has an ID, and it is held by a mob, the ID is placed in the mob's hands, a chat message is sent indicating that
//              the ID has been removed, and a sound effect is played. If the ID is not held by a mob, it is moved to the turf where the communicator
//              is located. The "pda-id" overlay is removed, and the communicator's ID is set to null.
/obj/item/communicator/proc/remove_id()
	if (id)
		if (ismob(loc))
			var/mob/M = loc
			M.put_in_hands(id)
			to_chat(M, span_notice("You remove the ID from the [name].")) // usr --> M
			play_sfx(src, SFX_MACHINES_ID_SWIPE, 2)
		else
			id.forceMove(get_turf(src))
		cut_overlay("pda-id")
		own_take(src, nameof(id))

// Proc: id_check(mob/user as mob, choice as num)
// Parameters: mob/user - the user who is attempting to check for an ID
//             choice - an integer indicating whether the check is for in-pda use (1) or out-of-pda use (2)
// Description: Checks for an ID in the communicator. If choice is 1 and an ID is present, the ID is removed and the procedure returns 1.
//              If choice is 1 and no ID is present, the user's active hand is checked for an ID card. If an ID card is found and unequipped
//              successfully, it is added to the communicator's inventory and the procedure returns 1. If choice is 2 and the user's active hand
//              contains a valid registered ID card that can be unequipped, the card is moved to the communicator's inventory and replaces the
//              current ID, which is moved to the user's hands. The procedure returns 1. If no ID card can be found or equipped, the procedure
//              returns 0.
/obj/item/communicator/proc/id_check(mob/user as mob, choice as num)
	if(choice == 1)
		if (id)
			remove_id()
			return 1
		else
			var/obj/item/I = user.get_active_hand()
			if (istype(I, /obj/item/card/id))
				move_into(src, nameof(src.id), I, user)
			return 1
	else
		var/obj/item/card/I = user.get_active_hand()
		if (istype(I, /obj/item/card/id) && I:registered_name)
			var/obj/old_id = own_take(src, nameof(src.id))
			if(!move_into(src, nameof(src.id), I, user))
				rel_set(src, nameof(src.id), old_id)
				return 0
			user.put_in_hands(old_id)
			return 1
	return 0

// ITION END

// Proc: register_to_holder()
// Parameters: None
// Description: Tries to register ourselves to the mob that we've presumably spawned in. Not the most amazing way of doing this.
/obj/item/communicator/proc/register_to_holder(datum/act/A)
	if(ismob(loc))
		register_device(loc.name)
		initialize_exonet(loc)
	else if(istype(loc, /obj/item/storage))
		var/obj/item/storage/S = loc
		if(ismob(S.loc))
			register_device(S.loc.name)
			initialize_exonet(S.loc)

// Proc: initialize_exonet()
// Parameters: 1 (user - the person the communicator belongs to)
// Description: Sets up the exonet datum, gives the device an address, and then gets a node reference.  Afterwards, populates the device
//				list.
/obj/item/communicator/proc/initialize_exonet(mob/user)
	if(!user || !isliving(user))
		return
	if(!exonet)
		rel_set(src, nameof(exonet), new /datum/exonet_protocol(src))
	if(!exonet.address)
		exonet.make_address("communicator-[user.client]-[user.name]")
	if(!node)
		rel_set(src, nameof(node), get_exonet_node())
	populate_known_devices()

// Proc: examine()
// Parameters: 1 (user - the person examining the device)
// Description: Shows all the voice mobs inside the device, and their status.
/obj/item/communicator/examine(mob/user)
	. = ..()

	FOR_REAL_CONTENTS(var/mob/living/voice/voice, src)
		. += span_notice("On the screen, you can see a image feed of [voice].")

		if(voice && voice.key)
			switch(voice.stat)
				if(CONSCIOUS)
					if(!voice.client)
						. += span_warning("[voice] appears to be asleep.") //afk
				if(UNCONSCIOUS)
					. += span_warning("[voice] doesn't appear to be conscious.")
				if(DEAD)
					. += span_deadsay("[voice] appears to have died...") //Hopefully this never has to be used.
		else
			. += span_notice("The device doesn't appear to be transmitting any data.")

// Proc: emp_act(severity, recursive)
// Parameters: None
// Description: Drops all calls when EMPed, so the holder can then get murdered by the antagonist.
/// An EMP drops the call.
/obj/item/communicator/proc/communicator_emp(datum/act/A)
	close_connection(reason = "Hardware error de%#_^@%-BZZZZZZZT")

// Proc: add_to_EPv2()
// Parameters: 1 (hex - a single hexadecimal character)
// Description: Called when someone is manually dialing with nanoUI.  Adds colons when appropiate.
/obj/item/communicator/proc/add_to_EPv2(hex)
	var/length = length(target_address)
	if(length >= 24)
		return
	if(length == 4 || length == 9 || length == 14 || length == 19 || length == 24 || length == 29)
		target_address += ":[hex]"
		return
	target_address += hex

// Proc: populate_known_devices()
// Parameters: 1 (user - the person using the device)
// Description: Searches all communicators and ghosts in the world, and adds them to the known_devices list if they are 'visible'.
/obj/item/communicator/proc/populate_known_devices(mob/user)
	if(!exonet)
		rel_set(src, nameof(exonet), new /datum/exonet_protocol(src))
	rel_clear(src, nameof(known_devices))
	if(!get_connection_to_tcomms()) //If the network's down, we can't see anything.
		return
	for(var/obj/item/communicator/comm in REGISTRY_MEMBERS(REGISTRY_COMMUNICATORS))
		if(!comm || !comm.exonet || !comm.exonet.address || comm.exonet.address == src.exonet.address) //Don't add addressless devices, and don't add ourselves.
			continue
		rel_add(src, nameof(known_devices), comm)
	for(var/mob/observer/dead/O in REGISTRY_MEMBERS(REGISTRY_DEAD_MOBS))
		if(!O.client || !O.client.prefs.read_preference(/datum/preference/toggle/human/communicator_visibility)) // migrated pref
			continue
		rel_add(src, nameof(known_devices), O)

// Proc: get_connection_to_tcomms()
// Parameters: None
// Description: Simple check to see if the exonet node is active.
/obj/item/communicator/proc/get_connection_to_tcomms()
	if(node && node.on && node.allow_external_communicators)
		return can_telecomm(src,node)
	return 0

// Proc: process()
// Parameters: None
// Description: Ticks the update_ticks variable, and checks to see if it needs to disconnect communicators every five ticks..
/obj/item/communicator/periodic_step()
	// The watchdog only guards open connections (declared on has_connections).
	update_ticks++
	// Connection maintenance is the five-tick watchdog, not four of every five
	// ticks. State-changing exonet paths update immediately.
	if(!(update_ticks % 5))
		if(!node)
			rel_set(src, nameof(node), get_exonet_node())
		if(!get_connection_to_tcomms())
			close_connection(reason = "Connection timed out")

// Proc: attackby()
// Parameters: 2 (C - what is used on the communicator. user - the mob that has the communicator)
// Description: When an ID is swiped on the communicator, the communicator reads the job and checks it against the Owner name, if success, the occupation is added.
// ITION: If the ID has already been scanned it is instead inserted into the communicator
/obj/item/communicator/proc/interaction_item(mob/user, obj/item/C, datum/interaction/interaction)
	if(istype(C, /obj/item/card/id))
		var/obj/item/card/id/idcard = C
		if(!idcard.registered_name || !idcard.assignment)
			to_chat(user, span_notice("\The [src] rejects the ID."))
		else if(!owner)
			to_chat(user, span_notice("\The [src] rejects the ID."))
		else if(owner == idcard.registered_name && occupation != idcard.assignment) //CHMPEDIT only edit assigment if different
			occupation = idcard.assignment
			to_chat(user, span_notice(">Occupation updated."))
		// ITION START Communicator ID slotting if we have an ID thats also already scanned
		else if(((is_in_holder(src, user)) && (is_in_holder(C, user))) || (istype(loc, /turf) && in_range(src, user) && (is_in_holder(C, user))) )
			if(id_check(user, 2))
				to_chat(user, span_notice("You put the ID into \the [src]'s slot."))
				add_overlay("pda-id")
		// ITION END
		return TRUE
	return FALSE

// Proc: attack_self()
// Parameters: 1 (user - the mob that clicked the device in their hand)
// Description: Makes an exonet datum if one does not exist, allocates an address for it, maintains the lists of all devies, clears the alert icon, and
//				finally makes NanoUI appear.
/obj/item/communicator/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	initialize_exonet(user)
	alert_called = 0
	changed(src)
	tgui_interact(user)
	return TRUE

// Proc: MouseDrop()
//Same thing PDAs do
/obj/item/communicator/MouseDrop(obj/over_object as obj)
	var/mob/M = usr
	if (!(src.loc == M) || (src.loc && src.loc.loc == M))
		return
	if(!istype(over_object, /atom/movable/screen))
		return attack_self(M)
	return

/// Old attack_ghost: recreates the known_devices list, so that the ghost looking at the device
/// can see themselves, then falls through to the ghost's default so that the UI appears.
/obj/item/communicator/proc/communicator_observer_use(mob/user, obj/item/held, datum/interaction/interaction)
	populate_known_devices() //Update the devices so ghosts can see the list on NanoUI.
	return FALSE

/mob/observer/dead
	var/datum/exonet_protocol/exonet = null
	var/list/exonet_messages = list() // ALLOW(instance_list): d: per-mob exonet_messages, filled at runtime; mobs are few

// Proc: New()
// Parameters: None
// Description: Gives ghosts an exonet address based on their key and ghost name.
/mob/observer/dead/Initialize(mapload)
	. = ..()
	if(client)
		exonet.make_address("communicator-[src.client]-[src.client.prefs.read_preference(/datum/preference/name/real_name)]")
	else
		exonet.make_address("communicator-[key]-[src.real_name]")

// Proc: register_device()
// Parameters: 1 (user - the person to use their name for)
// Description: Updates the owner's name and the device's name.
/obj/item/communicator/proc/register_device(new_name)
	if(!new_name)
		return
	owner = new_name

	name = "[new_name]'s [initial(name)]"
	if(camera)
		camera.name = name
		camera.c_tag = name

// Proc: Destroy()
// Parameters: None
// Description: Deletes all the voice mobs, disconnects all linked communicators, and cuts lists to allow successful qdel()
// ITION: Remvovess any slotted in IDs before deleting

// its ID drops out, connected voices time out and its calls close.
/obj/item/communicator/on_destroy(force)
	// Voice mobs are told the line dropped before they go; a policy can't send that.
	for(var/mob/living/voice/voice in contents.Copy()) // ALLOW(decl): per-item message and deletion, not a drop
		own_take_member(src, nameof(voice_mobs), voice)
		to_chat(voice, span_danger("[icon2html(src, voice.client)] Connection timed out with remote host."))
		destroyed(voice)
	close_connection(reason = "Connection timed out")
	..()

// Proc: update_icon()
// Parameters: None
// Description: Self explanatory
/obj/item/communicator/proc/appearance_comm_suffix()
	if(video_source)
		return "-video"
	if(length(voice_mobs) || length(communicating))
		return "-active"
	if(alert_called)
		return "-called"
	return ""

/// The look (the draw sweep: from its template).
/obj/item/communicator/draw(datum/look/look)
	..()
	look.state("[initial(icon_state)][appearance_comm_suffix()]")

// A camera preset for spawning in the communicator
/obj/machinery/camera/communicator
	network = list(NETWORK_COMMUNICATORS)

/obj/machinery/camera/communicator/Initialize(mapload)
	. = ..()
	LAZYOR(client_huds, GLOB.global_hud.whitense)
	LAZYOR(client_huds, GLOB.global_hud.darkMask)

//It's the 26th century. We should have smart watches by now.
/obj/item/communicator/watch
	name = "communicator watch"
	desc = "A personal device used to enable long range dialog between two people, utilizing existing telecommunications infrastructure to allow \
	communications across different stations, planets, or even star systems. You can wear this one on your wrist!"
	icon = 'icons/obj/device.dmi'
	icon_state = "commwatch"
	slot_flags = SLOT_GLOVES | SLOT_ID | SLOT_BELT // Commwatches and Wrtist PDAs can go on ID and belt slots


#undef HOMETAB
#undef PHONTAB
#undef CONTTAB
#undef MESSTAB
#undef NEWSTAB
#undef NOTETAB
#undef WTHRTAB
#undef MANITAB
#undef SETTTAB
