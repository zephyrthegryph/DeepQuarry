/obj/structure/closet/crate
	name = "crate"
	desc = "A rectangular steel crate."
	icon = 'icons/obj/closets/bases/crate.dmi'
	closet_appearance = /datum/decl/closet_appearance/crate
	dir = 4 //Spawn facing 'forward' by default.
	var/points_per_crate = 5
	/// A cable runs from the lid to an electropack inside: whoever opens it is shocked. Written through set_rigged().
	var/rigged = 0
	/// Ordinary paper carrying the currently sealed freight ledger.
	var/obj/item/paper/shipping_ledger
	/// Refs of the exact cargo present when the ledger was sealed.
	var/list/shipping_ledger_snapshot

	open_sound = SFX_EFFECTS_CRATE_OPEN
	close_sound = SFX_EFFECTS_CRATE_CLOSE

TRACKED(/obj/structure/closet/crate, rigged)

MSG_DEF_SELF(crate/already_rigged, "It is already rigged!")
MSG_DEF_SELF(crate/no_grabs, "You can't stuff anyone into that.")
MSG_DEF(crate/rigged, "You rig %T%.", "%U% rigs %T%.")
MSG_DEF(crate/unrigged, "You cut away the wiring.", "%U% cuts away the wiring.")
MSG_DEF(crate/pack_attached, "You attach %I% to %T%.", "%U% attaches %I% to %T%.")

// A crate is a closet that takes objects but never people (each object costs one unit), is climbed onto by a mob that drags itself on it while it is shut, can be
// rigged with a cable and an electropack so that whoever opens it is shocked, and has the closet's door, weld and bolts. It is opened and closed by hand even with
// something in the way, and wirecutters work it as a hand does (they cut the rigging first).
CAPABILITIES(/obj/structure/closet/crate)
	climb()
	extend("climb.climb", when(cond_not(nameof(opened))))
	extend("climb.climb_menu", when(cond_not(nameof(opened))))
	without("empty_basket")
	op("rig", item(/obj/item/stack/cable_coil), label("Rig"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_PART),
		needs(req_is(nameof(rigged), FALSE, because = MSG(crate/already_rigged))), then(PROC_REF(rig_with_cable)), says(MSG(crate/rigged)))
	op("attach_pack", item(/obj/item/radio/electropack), label("Attach"), when(cond_not(nameof(opened))), when(nameof(rigged)), priority(OP_PRIORITY_PART),
		then(PROC_REF(pack_attached)), says(MSG(crate/pack_attached)))
	op("cut_rigging", tool(TOOL_WIRECUTTER), label("Cut the rigging"), when(nameof(rigged)), priority(OP_PRIORITY_PART), wait(0),
		then(PROC_REF(rigging_cut)), says(MSG(crate/unrigged)))
	op("cutters_touch", tool(TOOL_WIRECUTTER), label("Open"), when(cond_not(nameof(rigged))), priority(OP_PRIORITY_PART), wait(0),
		then(PROC_REF(touched_with_cutters)))

/obj/structure/closet/crate/Initialize(mapload)
	. = ..()
	make_rotatable()

/obj/structure/closet/crate/can_close()
	return 1

/obj/structure/closet/crate/open(mob/user)
	if(src.opened)
		return 0
	if(!src.can_open())
		return 0
	void_shipping_ledger("crate opened")

	var/obj/item/radio/electropack/rig
	if(rigged)
		for(var/obj/item/radio/electropack/E in slot_contents())
			rig = E
			break
	if(rigged && rig)
		if(isliving(user))
			var/mob/living/L = user
			if(L.electrocute_act(17, src))
				fx_sparks(src, 5)
				if(user.has_status(STAT_STUNNED))
					return 2

	playsound(src, open_sound, 50, 1, -3)
	slot_empty(CONTAINER_SLOT_INTERIOR, get_turf(src))
	climb_shake_off(src, null) // before the door moves: the climb waits on it being shut
	set_opened(TRUE)
	return 1

/obj/structure/closet/crate/close()
	if(!src.opened)
		return 0
	if(!src.can_close())
		return 0

	playsound(src, close_sound, 50, 1, -3)
	// Each object costs one unit (storage_cost_of); the ledger stops at storage_capacity.
	for(var/obj/O in get_turf(src))
		if(O.density || O.anchored || istype(O,/obj/structure/closet) || istype(O,/obj/effect/abstract))
			continue
		if(istype(O, /obj/structure/bed)) //This is only necessary because of rollerbeds and swivel chairs.
			var/obj/structure/bed/B = O
			if(B.has_buckled_mobs())
				continue
		move_into(src, null, O)

	set_opened(FALSE)
	return 1

/// Crates count objects, not sizes.
/obj/structure/closet/crate/storage_cost_of(atom/movable/thing)
	return 1

/// A crate takes no person a grab holds.
/obj/structure/closet/crate/grab_fits(datum/act/op/A)
	return FALSE

/obj/structure/closet/crate/grab_refusal(datum/act/op/A)
	return /datum/msg/crate/no_grabs

/// A length of cable rigs it.
/obj/structure/closet/crate/proc/rig_with_cable(datum/act/op/A)
	var/obj/item/stack/cable_coil/C = A.held
	if(!C.use(1))
		return OP_REFUSED
	set_rigged(TRUE)
	return OP_OK

/// An electropack goes in beside the cable.
/obj/structure/closet/crate/proc/pack_attached(datum/act/op/A)
	if(!own_bring_in(src, nameof(contents), A.held, null, A.actor, TRUE, null, FALSE))
		return OP_REFUSED
	return OP_OK

/obj/structure/closet/crate/proc/rigging_cut(datum/act/op/A)
	playsound(src, A.held.usesound, 100, 1)
	set_rigged(FALSE)
	return OP_OK

/// Wirecutters on a crate with nothing to cut work it as a hand does.
/obj/structure/closet/crate/proc/touched_with_cutters(datum/act/op/A)
	perform_op(A.actor, src, "door", origin = ORIGIN_SYSTEM)
	return OP_OK

/obj/structure/closet/crate/secure
	desc = "A secure crate."
	name = "Secure crate"
	closet_appearance = /datum/decl/closet_appearance/crate/secure
	var/broken = 0
	/// Whether it starts locked (a map says `locked = 0` for one that does not). The lock itself is the lock() capability's key: read it with lock_locked().
	var/locked = 1

TRACKED(/obj/structure/closet/crate/secure, broken)

MSG_DEF_SELF(crate/close_first, "Close the crate first.")
MSG_DEF_SELF(crate/broken, "The crate appears to be broken.")
MSG_DEF_SELF(crate/inside, "You can't reach the lock from inside.")

// A secure crate is a crate with the same ID lock and breakable lock as a locker. A blade or an emag breaks it for good; any item in the hand of somebody whose own ID
// has the access works the lock of a shut one, as a card does. It holds somebody in only while it is both locked and sealed.
CAPABILITIES(/obj/structure/closet/crate/secure)
	lock(starts_locked = nameof(locked))
	extend(CAP_LOCK, needs(req_is(nameof(opened), FALSE, because = MSG(crate/close_first)), req_is(nameof(broken), FALSE, because = MSG(crate/broken)), req(PROC_REF(actor_outside), because = MSG(crate/inside))))
	extend("lock.toggle_worn", binds(menu()), label("Toggle Lock"))
	extend("door", when(cond_not(LOCK_LOCKED)), priority(above("lock.toggle_worn")))
	emag(then(PROC_REF(on_emag)), repeatable = TRUE)
	extend("emag.use", needs(req_is(nameof(broken), FALSE, because = MSG(emag/already))))
	extend("emag.subvert", needs(req_is(nameof(broken), FALSE, because = MSG(emag/already))))
	op("slice", item(/obj/item/melee/energy/blade), label("Slice open"), when(cond_not(nameof(opened))), priority(OP_PRIORITY_SUBVERT - 1), then(PROC_REF(blade_emagged)))
	op("lock_with_item", item(/obj/item), label("Toggle Lock"), when(cond_not(nameof(opened))), when(req_credential_worn(null)), priority(OP_PRIORITY_DEFAULT + 1),
		needs(req_is(nameof(broken), FALSE, because = MSG(crate/broken)), req(PROC_REF(actor_outside), because = MSG(crate/inside))), toggles(LOCK_LOCKED), says(PROC_REF(lock_toggled_message)))
	on_notice(/datum/notice/hit/emp, then(PROC_REF(secure_crate_emp)))

/// Whoever works the lock is not shut in with it.
/obj/structure/closet/crate/secure/proc/actor_outside(datum/act/op/A)
	return A.actor?.loc != src // ALLOW(reads): where the one at the lock is, read when the entry is offered and again at the click

/// A hand's work on a locked crate is its lock; on an unlocked one, its door.
/obj/structure/closet/crate/secure/touched_with_cutters(datum/act/op/A)
	perform_op(A.actor, src, lock_locked(src) ? "lock.toggle_worn" : "door", origin = ORIGIN_SYSTEM)
	return OP_OK

/obj/structure/closet/crate/secure/req_breakout()
	if(opened || !lock_locked(src) || !is_welded(src))
		return FALSE
	return TRUE

/obj/structure/closet/crate/secure/can_open()
	return !lock_locked(src)

/// A broken lock shows emagged, a working one by whether it holds.
/obj/structure/closet/crate/secure/closet_lock_look()
	if(broken)
		return "emagged"
	return lock_locked(src) ? "locked" : "unlocked"

/// An energy blade emags it.
/obj/structure/closet/crate/secure/proc/blade_emagged(datum/act/op/A)
	emag_target(src, INFINITY, A.actor)
	return OP_OK

/// An emag breaks the lock for good (a second does nothing).
/obj/structure/closet/crate/secure/proc/on_emag(datum/act/op/A)
	if(!broken)
		play_sfx(src, SFX_SPARKS, 1.2)
		force_lock(FALSE)
		set_broken(TRUE)
		to_chat(A.actor, span_notice("You unlock \the [src]."))
	return OP_OK

/// An EMP may toggle the lock, pop the crate or scramble its access.
/obj/structure/closet/crate/secure/proc/secure_crate_emp(datum/act/A)
	var/datum/notice/hit/emp/N = A
	var/severity = max(N.packet?.severity, 1)
	if(!broken && !opened && prob(50/severity))
		if(!lock_locked(src))
			force_lock(TRUE)
		else
			play_sfx(src, SFX_EFFECTS_SPARKS4)
			force_lock(FALSE)
	if(!opened && prob(20/severity))
		if(!lock_locked(src))
			open()
		else
			req_access = list()
			req_access += pick(SSaccess.get_all_station_access())

/obj/structure/closet/crate/plastic
	name = "plastic crate"
	desc = "A rectangular plastic crate."
	closet_appearance = /datum/decl/closet_appearance/crate/plastic
	points_per_crate = 1	//5 crates per ordered crate, +5 for the crate it comes in.

/obj/structure/closet/crate/internals
	name = "internals crate"
	desc = "A internals crate."

/obj/structure/closet/crate/trashcart
	name = "trash cart"
	desc = "A heavy, metal trashcart with wheels."
	closet_appearance = /datum/decl/closet_appearance/cart/trash

/*these aren't needed anymore
/obj/structure/closet/crate/hat
	desc = "A crate filled with Valuable Collector's Hats!."
	name = "Hat Crate"

/obj/structure/closet/crate/contraband
	name = "Poster crate"
	desc = "A random assortment of posters manufactured by providers NOT listed under NanoTrasen's whitelist."
*/

/obj/structure/closet/crate/medical
	name = "medical crate"
	desc = "A medical crate."
	closet_appearance = /datum/decl/closet_appearance/crate/medical

/obj/structure/closet/crate/rcd
	name = "\improper RCD crate"
	desc = "A crate with rapid construction device."

	starts_with = list(
		/obj/item/rcd_ammo = 3,
		/obj/item/rcd)

/obj/structure/closet/crate/solar
	name = "solar pack crate"

	starts_with = list(
		/obj/item/solar_assembly = 21,
		/obj/item/circuitboard/solar_control,
		/obj/item/tracker_electronics,
		/obj/item/paper/solar)

/obj/structure/closet/crate/cooper
	name = "Cooper's Stache"

	starts_with = list(
		/obj/item/reagent_containers/food/snacks/cheesewedge = 6,
		/obj/item/stack/material/gold = 1)
/obj/structure/closet/crate/freezer
	name = "freezer"
	desc = "A freezer."
	closet_appearance = /datum/decl/closet_appearance/crate/freezer
	var/target_temp = T0C - 40
	var/cooling_power = 40

/obj/structure/closet/crate/freezer/centauri
	desc = "A freezer stamped with the logo of Centauri Provisions."
	closet_appearance = /datum/decl/closet_appearance/crate/freezer/centauri

/obj/structure/closet/crate/freezer/nanotrasen
	desc = "A freezer stamped with the logo of NanoTrasen."
	closet_appearance = /datum/decl/closet_appearance/crate/freezer/nanotrasen

/obj/structure/closet/crate/freezer/veymed
	desc = "A freezer stamped with the logo of Vey-Medical."
	closet_appearance = /datum/decl/closet_appearance/crate/freezer/veymed

/obj/structure/closet/crate/freezer/zenghu
	desc = "A freezer stamped with the logo of Zeng-Hu Pharmaceuticals."
	closet_appearance = /datum/decl/closet_appearance/crate/freezer/zenghu

/obj/structure/closet/crate/freezer/return_air()
	var/datum/gas_mixture/gas = (..())
	if(!gas)	return null
	var/datum/gas_mixture/newgas = new/datum/gas_mixture()
	newgas.copy_from(gas)
	var/newgas_temperature = newgas.return_temperature()
	if(newgas_temperature <= target_temp)	return

	if((newgas_temperature - cooling_power) > target_temp)
		heat_set(newgas, newgas_temperature - cooling_power, HEAT_SOURCE_DEVICE)
	else
		heat_set(newgas, target_temp, HEAT_SOURCE_DEVICE)
	return newgas

/obj/structure/closet/crate/freezer/Entered(atom/movable/AM)
	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 1
		for(var/obj/item/organ/organ in O)
			organ.preserved = 1
	..()

/obj/structure/closet/crate/freezer/Exited(atom/movable/AM)
	if(istype(AM, /obj/item/organ))
		var/obj/item/organ/O = AM
		O.preserved = 0
		for(var/obj/item/organ/organ in O)
			organ.preserved = 0
	..()

/obj/structure/closet/crate/weapon
	name = "weapons crate"
	desc = "A barely secured weapons crate."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/weapon

/obj/structure/closet/crate/freezer/rations //Fpr use in the escape shuttle
	name = "emergency rations"
	desc = "A crate of emergency rations."

	starts_with = list(
		/obj/random/mre = 6)

/obj/structure/closet/crate/bin
	name = "large bin"
	desc = "A large bin."
	closet_appearance = null
	icon = 'icons/obj/closets/largebin.dmi'
	icon_state = ""

/obj/structure/closet/crate/radiation
	name = "radioactive gear crate"
	desc = "A crate with a radiation sign on it."
	closet_appearance = /datum/decl/closet_appearance/crate/radiation

	starts_with = list(
		/obj/item/clothing/suit/radiation = 4,
		/obj/item/clothing/head/radiation = 4)

//TSCs

/obj/structure/closet/crate/aether
	desc = "A crate painted in the colours of Aether Atmospherics and Recycling."
	closet_appearance = /datum/decl/closet_appearance/crate/aether

/obj/structure/closet/crate/centauri
	desc = "A crate decorated with the logo of Centauri Provisions."
	closet_appearance = /datum/decl/closet_appearance/crate/centauri

/obj/structure/closet/crate/einstein
	desc = "A crate labelled with an Einstein Engines sticker."
	closet_appearance = /datum/decl/closet_appearance/crate/einstein

/obj/structure/closet/crate/focalpoint
	desc = "A crate marked with the decal of Focal Point Energistics."
	closet_appearance = /datum/decl/closet_appearance/crate/focalpoint

/obj/structure/closet/crate/gilthari
	desc = "A crate embossed with the logo of Gilthari Exports."
	closet_appearance = /datum/decl/closet_appearance/crate/gilthari

/obj/structure/closet/crate/grayson
	desc = "A bare metal crate spraypainted with Grayson Manufactories decals."
	closet_appearance = /datum/decl/closet_appearance/crate/grayson

/obj/structure/closet/crate/heph
	desc = "A sturdy crate marked with the logo of Hephaestus Industries."
	closet_appearance = /datum/decl/closet_appearance/crate/heph

/obj/structure/closet/crate/morpheus
	desc = "A crate crudely imprinted with 'MORPHEUS CYBERKINETICS'."
	closet_appearance = /datum/decl/closet_appearance/crate/morpheus

/obj/structure/closet/crate/nanotrasen
	desc = "A crate emblazoned with the standard NanoTrasen livery."
	closet_appearance = /datum/decl/closet_appearance/crate/nanotrasen

/obj/structure/closet/crate/nanothreads
	desc = "A crate emblazoned with the NanoThreads Garments livery, a subsidary of the NanoTrasen Corporation."
	closet_appearance = /datum/decl/closet_appearance/crate/nanotrasenclothing

/obj/structure/closet/crate/nanomed
	desc = "A crate emblazoned with the NanoMed Medical livery, a subsidary of the NanoTrasen Corporation."
	closet_appearance = /datum/decl/closet_appearance/crate/nanotrasenmedical

/obj/structure/closet/crate/oculum
	desc = "A crate minimally decorated with the logo of media giant Oculum Broadcast."
	closet_appearance = /datum/decl/closet_appearance/crate/oculum

/obj/structure/closet/crate/veymed
	desc = "A sterile crate extensively detailed in Veymed colours."
	closet_appearance = /datum/decl/closet_appearance/crate/veymed

/obj/structure/closet/crate/ward
	desc = "A crate decaled with the logo of Ward-Takahashi."
	closet_appearance = /datum/decl/closet_appearance/crate/ward

/obj/structure/closet/crate/xion
	desc = "A crate painted in Xion Manufacturing Group orange."
	closet_appearance = /datum/decl/closet_appearance/crate/xion

/obj/structure/closet/crate/zenghu
	desc = "A sterile crate marked with the logo of Zeng-Hu Pharmaceuticals."
	closet_appearance = /datum/decl/closet_appearance/crate/zenghu

/obj/structure/closet/crate/coyote_salvage
	desc = "A supply crate marked with Coyote Salvage Corp colours."
	closet_appearance = /datum/decl/closet_appearance/crate/coyotesalvage

/obj/structure/closet/crate/nukies
	desc = "A luridly-coloured supply crate with Nukies! branding. Is it legal to have this here?"
	closet_appearance = /datum/decl/closet_appearance/crate/nukies

/obj/structure/closet/crate/desatti
	desc = "A strikingly-coloured supply crate with Desatti Catering branding."
	closet_appearance = /datum/decl/closet_appearance/crate/desatti

// Brands/subsidiaries

/obj/structure/closet/crate/allico
	desc = "A crate painted in the distinctive cheerful colours of AlliCo. Ltd."
	closet_appearance = /datum/decl/closet_appearance/crate/allico

/obj/structure/closet/crate/carp
	desc = "A crate painted with the garish livery of Consolidated Agricultural Resources Plc."
	closet_appearance = /datum/decl/closet_appearance/crate/carp

/obj/structure/closet/crate/hedberg
	name = "weapons crate"
	desc = "A weapons crate stamped with the logo of Hedberg-Hammarstrom and the lock conspicuously absent."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/hedberg

/obj/structure/closet/crate/galaksi
	desc = "A crate printed with the markings of Ward-Takahashi's Galaksi Appliance branding."
	closet_appearance = /datum/decl/closet_appearance/crate/galaksi

/obj/structure/closet/crate/thinktronic
	desc = "A crate printed with the markings of Thinktronic Systems."
	closet_appearance = /datum/decl/closet_appearance/crate/thinktronic

/obj/structure/closet/crate/ummarcar
	desc = "A flimsy crate marked labelled 'UmMarcar Office Supply'."
	closet_appearance = /datum/decl/closet_appearance/crate/ummarcar

/obj/structure/closet/crate/unathi
	name = "import crate"
	desc = "A crate painted with the markings of Moghes Imported Sissalik Jerky."
	closet_appearance = /datum/decl/closet_appearance/crate/unathiimport


// Secure Crates

/obj/structure/closet/crate/secure/weapon
	name = "weapons crate"
	desc = "A secure weapons crate."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/weapon

/obj/structure/closet/crate/secure/aether
	desc = "A secure crate painted in the colours of Aether Atmospherics and Recycling."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/aether

/obj/structure/closet/crate/secure/bishop
	desc = "A secure crate finely decorated with the emblem of Bishop Cybernetics."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/bishop

/obj/structure/closet/crate/secure/cybersolutions
	desc = "An unadorned secure metal crate labelled 'Cyber Solutions'."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/cybersolutions

/obj/structure/closet/crate/secure/einstein
	desc = "A secure crate labelled with an Einstein Engines sticker."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/einstein

/obj/structure/closet/crate/secure/focalpoint
	desc = "A secure crate marked with the decal of Focal Point Energistics."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/focalpoint

/obj/structure/closet/crate/secure/gilthari
	desc = "A secure crate embossed with the logo of Gilthari Exports."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/gilthari

/obj/structure/closet/crate/secure/grayson
	desc = "A secure bare metal crate spraypainted with Grayson Manufactories decals."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/grayson

/obj/structure/closet/crate/secure/hedberg
	name = "weapons crate"
	desc = "A secure weapons crate stamped with the logo of Hedberg-Hammarstrom."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/hedberg

/obj/structure/closet/crate/secure/heph
	name = "weapons crate"
	desc = "A secure weapons crate marked with the logo of Hephaestus Industries."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/heph

/obj/structure/closet/crate/secure/lawson
	name = "weapons crate"
	desc = "A secure weapons crate marked with the logo of Lawson Arms."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/lawson

/obj/structure/closet/crate/secure/morpheus
	desc = "A secure crate crudely imprinted with 'MORPHEUS CYBERKINETICS'."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/morpheus

/obj/structure/closet/crate/secure/nanotrasen
	desc = "A secure crate emblazoned with the standard NanoTrasen livery."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/nanotrasen

/obj/structure/closet/crate/secure/nanomed
	desc = "A secure crate emblazoned with the NanoMed Medical livery, a subsidary of the NanoTrasen Corporation."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/nanotrasenmedical

/obj/structure/closet/crate/secure/scg
	name = "weapons crate"
	desc = "A secure crate in the official colours of the Solar Confederate Government."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/solgov

/obj/structure/closet/crate/secure/saare
	name = "weapons crate"
	desc = "A secure weapons crate plainly stamped with the logo of Stealth Assault Enterprises."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/saare

/obj/structure/closet/crate/secure/veymed
	desc = "A secure sterile crate extensively detailed in Veymed colours."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/veymed

/obj/structure/closet/crate/secure/ward
	desc = "A secure crate decaled with the logo of Ward-Takahashi."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/ward

/obj/structure/closet/crate/secure/xion
	desc = "A secure crate painted in Xion Manufacturing Group orange."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/xion

/obj/structure/closet/crate/secure/zenghu
	desc = "A secure sterile crate marked with the logo of Zeng-Hu Pharmaceuticals."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/zenghu

/obj/structure/closet/crate/secure/phoron
	name = "phoron crate"
	desc = "A secure phoron crate painted in standard NanoTrasen livery."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/hazard

/obj/structure/closet/crate/secure/gear
	name = "gear crate"
	desc = "A secure gear crate."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/weapon

/obj/structure/closet/crate/secure/hydrosec
	name = "secure hydroponics crate"
	desc = "A crate with a lock on it, painted in the scheme of the station's botanists."
	closet_appearance = /datum/decl/closet_appearance/crate/secure/hydroponics

/obj/structure/closet/crate/secure/engineering
	desc = "A crate with a lock on it, painted in the scheme of the station's engineers."
	name = "secure engineering crate"

/obj/structure/closet/crate/secure/science
	name = "secure science crate"
	desc = "A crate with a lock on it, painted in the scheme of the station's scientists."

/obj/structure/closet/crate/secure/bin
	name = "secure bin"
	desc = "A secure bin."

// Large crates

/obj/structure/closet/crate/large
	name = "large crate"
	desc = "A hefty metal crate."
	icon = 'icons/obj/closets/bases/large_crate.dmi'
	closet_appearance = /datum/decl/closet_appearance/large_crate

/obj/structure/closet/crate/large/close()
	. = ..()
	if (.)//we can hold up to one large item
		var/found = 0
		for(var/obj/structure/S in src.loc)
			if(S == src)
				continue
			if(!S.anchored)
				found = 1
				S.forceMove(src)
				break
		if(!found)
			for(var/obj/machinery/M in src.loc)
				if(!M.anchored)
					M.forceMove(src)
					break
	return

/obj/structure/closet/crate/large/critter
	name = "animal crate"
	desc = "A hefty crate for hauling animals."
	closet_appearance = /datum/decl/closet_appearance/large_crate/critter

/obj/structure/closet/crate/large/aether
	name = "large atmospherics crate"
	desc = "A hefty metal crate, painted in Aether Atmospherics and Recycling colours."
	closet_appearance = /datum/decl/closet_appearance/large_crate/aether

/obj/structure/closet/crate/large/einstein
	name = "large crate"
	desc = "A hefty metal crate, painted in Einstein Engines colours."
	closet_appearance = /datum/decl/closet_appearance/large_crate/einstein

/obj/structure/closet/crate/large/nanotrasen
	name = "large crate"
	desc = "A hefty metal crate, painted in standard NanoTrasen livery."
	closet_appearance = /datum/decl/closet_appearance/large_crate/nanotrasen

/obj/structure/closet/crate/large/xion
	name = "large crate"
	desc = "A hefty metal crate, painted in Xion Manufacturing Group orange."
	closet_appearance = /datum/decl/closet_appearance/large_crate/xion

/obj/structure/closet/crate/secure/large
	name = "large crate"
	desc = "A hefty metal crate with an electronic locking system."
	icon = 'icons/obj/closets/bases/large_crate.dmi'
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure


/obj/structure/closet/crate/secure/large/close()
	. = ..()
	if (.)//we can hold up to one large item
		var/found = 0
		for(var/obj/structure/S in src.loc)
			if(S == src)
				continue
			if(!S.anchored)
				found = 1
				S.forceMove(src)
				break
		if(!found)
			for(var/obj/machinery/M in src.loc)
				if(!M.anchored)
					M.forceMove(src)
					break
	return


/obj/structure/closet/crate/secure/large/reinforced
	desc = "A hefty, reinforced metal crate with an electronic locking system."

/obj/structure/closet/crate/secure/large/aether
	name = "secure atmospherics crate"
	desc = "A hefty metal crate with an electronic locking system, painted in Aether Atmospherics and Recycling colours."
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure/aether

/obj/structure/closet/crate/secure/large/einstein
	desc = "A hefty metal crate with an electronic locking system, painted in Einstein Engines colours."
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure/einstein

/obj/structure/closet/crate/large/secure/heph
	desc = "A hefty metal crate with an electronic locking system, marked with Hephaestus Industries colours."
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure/heph

/obj/structure/closet/crate/secure/large/nanotrasen
	desc = "A hefty metal crate with an electronic locking system, painted in standard NanoTrasen livery."
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure/hazard

/obj/structure/closet/crate/large/secure/xion
	desc = "A hefty metal crate with an electronic locking system, painted in Xion Manufacturing Group orange."
	closet_appearance = /datum/decl/closet_appearance/large_crate/secure/xion

/obj/structure/closet/crate/engineering
	name = "engineering crate"

/obj/structure/closet/crate/engineering/electrical

/obj/structure/closet/crate/science
	name = "science crate"

/obj/structure/closet/crate/hydroponics
	name = "hydroponics crate"
	desc = "All you need to destroy those pesky weeds and pests."
	closet_appearance = /datum/decl/closet_appearance/crate/hydroponics


/obj/structure/closet/crate/hydroponics/prespawned
	starts_with = list(
		/obj/item/reagent_containers/spray/plantbgone = 2,
		/obj/item/material/minihoe)

//Laundry Cart
/obj/structure/closet/crate/laundry
	name = "Laundry Cart"
	desc = "A cart with a large fabric bin on it used for transporting large amounts of clothes."
	icon = 'icons/obj/closets/laundry.dmi'
	closet_appearance = null
	open_sound = SFX_EFFECTS_RUSTLE1
	close_sound = SFX_EFFECTS_RUSTLE2
	icon_state = ""

//Wooden Crate
/obj/structure/closet/crate/wooden
	name = "wooden crate"
	desc = "A crate made from wood and lined with straw. Cheapest form of storage."
	icon = 'icons/obj/closets/wooden.dmi'
	closet_appearance = null
	open_sound = SFX_EFFECTS_WOODEN_CLOSET_OPEN
	close_sound = SFX_EFFECTS_WOODEN_CLOSET_CLOSE
	icon_state = ""

//Chest
/obj/structure/closet/crate/chest
	name = "chest"
	desc = "A fancy chest made from wood and lined with red velvet."
	icon = 'icons/obj/closets/chest.dmi'
	closet_appearance = null
	open_sound = SFX_EFFECTS_WOODEN_CLOSET_OPEN
	close_sound = SFX_EFFECTS_WOODEN_CLOSET_CLOSE
	icon_state = ""

//Mining Cart
/obj/structure/closet/crate/miningcar
	name = "mining cart"
	desc = "A mining car. This one doesn't work on rails, but has to be dragged."
	icon = 'icons/obj/closets/miningcar.dmi'
	closet_appearance = null
	open_sound = SFX_EFFECTS_WOODEN_CLOSET_OPEN
	close_sound = SFX_EFFECTS_WOODEN_CLOSET_CLOSE
	icon_state = ""


/obj/structure/closet/crate/secure
	var/tamper_proof = 0

/obj/structure/closet/crate/secure/bullet_act(obj/item/projectile/Proj)
	if(!(Proj.obj_damage_type() == BRUTE || Proj.obj_damage_type() == BURN))
		return

	if(lock_locked(src) && tamper_proof && get_integrity() <= Proj.damage)
		if(loc?.release_refusal(src))
			return
		if(tamper_proof == 2) // Mainly used for events to prevent any chance of opening the box improperly.
			visible_message(span_bolddanger("The anti-tamper mechanism of [src] triggers an explosion!"))
			var/turf/T = get_turf(src.loc)
			explosion(T, 0, 0, 0, 1) // Non-damaging, but it'll alert security.
			consume(src)
			return
		var/open_chance = rand(1,5)
		switch(open_chance)
			if(1)
				visible_message(span_bolddanger("The anti-tamper mechanism of [src] causes an explosion!"))
				var/turf/T = get_turf(src.loc)
				explosion(T, 0, 0, 0, 1) // Non-damaging, but it'll alert security.
				consume(src)
			if(2 to 4)
				visible_message(span_boldwarning("The anti-tamper mechanism of [src] causes a small fire!"))
				for(var/i in 1 to length(slot_contents()) + latent_count()) // For every item in the box, we spawn a pile of ash.
					new /obj/effect/decal/cleanable/ash(src.loc)
				replace_with(src, /obj/effect/hotspot)
			if(5)
				visible_message(span_infoplain(span_green(span_bold("The anti-tamper mechanism of [src] fails!"))))
		return

	..()

	return

/obj/structure/closet/crate/medical/blood
	closet_appearance = /datum/decl/closet_appearance/cart/biohazard/alt

/obj/structure/closet/crate/fennec
	name = "fennec treats crate"
	desc = "A colorful crate filled with specialties catering to fennecs."
	icon = 'icons/obj/closets/bases/fencrate_vr.dmi'
	closet_appearance = /datum/decl/closet_appearance/crate/fennec
	points_per_crate = 0

/obj/structure/closet/crate/ownership()
	. = ..()
	. += owns(nameof(shipping_ledger), policy = OWN_CONTAINED)
