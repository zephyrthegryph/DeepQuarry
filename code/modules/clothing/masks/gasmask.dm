/obj/item/clothing/mask/gas
	name = "gas mask"
	desc = "A face-covering mask that can be connected to an air supply. Filters harmful gases from the air."
	icon_state = "gas_alt"
	w_class = ITEMSIZE_NORMAL
	item_state_slots = list(slot_r_hand_str = "gas_alt", slot_l_hand_str = "gas_alt")
	var/gas_filter_strength = 1			//For gas mask filters
	armor_spec = "bio=75"
	resistance_flags = FIRE_PROOF

CAPABILITIES(/obj/item/clothing/mask/gas)
	configure(item_worn(flags = BLOCK_GAS_SMOKE_EFFECT | AIRTIGHT | ALLOW_SURVIVALFOOD, hides = HIDEEARS|HIDEEYES|HIDEFACE, covers = FACE|EYES))
	configure(item_protection(gas_transfer = 0.01, permeability = 0.01, siemens = 0.9))
	configure(item_sounds(pickup = SFX_ITEMS_PICKUP_RUBBER))

TYPE_TABLE_DECLARE(/obj/item/clothing/mask/gas, gasmask_filtered_gases, list(GAS_PHORON, GAS_N2O))

/obj/item/clothing/mask/gas/filter_air(datum/gas_mixture/air)
	var/datum/gas_mixture/gas_filtered = new

	// LINDA_GAS_AMT is a read-only ternary expression macro; the old
	// `LINDA_GAS_AMT(air, g) -=` line is not assignable. Rewrite as a paired
	// adjust_gas: transfer the filtered moles, then remove the same from air.
	for(var/g in TYPE_TABLE_GET(src, gasmask_filtered_gases))
		var/source_amt = LINDA_GAS_AMT(air, g)
		if(source_amt)
			var/transferred = (source_amt * gas_filter_strength) - LINDA_GAS_AMT(gas_filtered, g)
			gas_filtered.adjust_gas(g, transferred)
			air.adjust_gas(g, -transferred)

	return gas_filtered

/obj/item/clothing/mask/gas/clear
	name = "gas mask"
	desc = "A face-covering mask with a transparent faceplate that can be connected to an air supply."
	icon_state = "gas_clear"

CAPABILITIES(/obj/item/clothing/mask/gas/clear)
	configure(item_worn(hides = TRAIT_NONE))

/obj/item/clothing/mask/gas/half
	name = "face mask"
	desc = "A compact, durable gas mask that can be connected to an air supply."
	icon_state = "halfgas"
	w_class = ITEMSIZE_SMALL
	armor_spec = "melee=10;bullet=10;laser=10;bio=55"

//Turn it into a hailer mask
CAPABILITIES(/obj/item/clothing/mask/gas/half)
	configure(item_worn(covers = FACE))
	configure(item_protection(siemens = 0.7))
	op("half_mask_add_hailer_item", item(/obj/item), label("Half mask add hailer item"), then(PROC_REF(half_mask_add_hailer_item)))

/// Both ingredients must be releasable before fitting a hailer changes either one.
/obj/item/clothing/mask/gas/half/proc/can_fit_hailer(mob/user, atom/target, obj/item/held)
	if(!istype(held, /obj/item/hailer))
		return TRUE
	var/reason = loc?.release_refusal(src, user)
	if(reason)
		return reason
	reason = held.loc?.release_refusal(held, user)
	if(reason)
		return reason
	return TRUE

/// Fit a hailer, retaining the original mask's slot and forensic evidence.

/obj/item/clothing/mask/gas/half/proc/half_mask_add_hailer_item(datum/act/op/A)
	var/refusal = can_fit_hailer(A.actor, src, A.held)
	if(refusal != TRUE)
		if(istext(refusal))
			to_chat(A.actor, span_warning(refusal))
		return OP_DECLINE
	var/mob/user = A.actor
	var/obj/item/I = A.held
	if(istype(I, /obj/item/hailer))
		if(can_fit_hailer(user, src, I) != TRUE)
			return OP_DECLINE
		var/obj/item/clothing/mask/gas/sechailer/N = new /obj/item/clothing/mask/gas/sechailer(get_turf(src))
		if(!I.loc.release_to(I, N, null, user))
			consume(N, user)
			return OP_DECLINE
		play_sfx(src, SFX_ITEMS_SCREWDRIVER)
		transfer_blooddna_to(N)
		transfer_fingerprints_to(N)
		transfer_fibres_to(N)
		rel_set(N, nameof(N.hailer), I)
		replace_with(src, N)
	return OP_DECLINE

//Plague Dr suit can be found in clothing/suits/bio.dm
/obj/item/clothing/mask/gas/plaguedoctor
	name = "plague doctor mask"
	desc = "A modernised version of the classic design, this mask will not only filter out phoron but it can also be connected to an air supply."
	icon_state = "plaguedoctor"
	item_state_slots = list(slot_r_hand_str = "gas", slot_l_hand_str = "gas")
	armor_spec = "laser=2;energy=2;bio=90"

CAPABILITIES(/obj/item/clothing/mask/gas/plaguedoctor)
	configure(item_worn(covers = HEAD|FACE|EYES))
	configure(item_protection(heat_parts = HEAD, cold_parts = HEAD))

/obj/item/clothing/mask/gas/plaguedoctor/gold
	name = "gold plague doctor mask"
	desc = "A modernised version of the classic design, this mask will not only filter out phoron but it can also be connected to an air supply. This one is gold."
	icon_state = "plaguedoctor2"

/obj/item/clothing/mask/gas/swat
	name = "\improper SWAT mask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "swat"

CAPABILITIES(/obj/item/clothing/mask/gas/swat)
	configure(item_worn(covers = FACE|EYES))
	configure(item_protection(siemens = 0.7))

// Vox mask, has special code for eating
/obj/item/clothing/mask/gas/swat/vox
	name = "\improper alien mask"
	desc = "Clearly not designed for a human face."
	flags = PHORONGUARD
	var/mask_open = FALSE	// Controls if the Vox can eat through this mask
	actions_types = list(/datum/action/item_action/toggle_feeding_port)
	helmet_handling = TRUE
	special_handling = TRUE

TYPE_TABLE(/obj/item/clothing/mask/gas/swat/vox, gasmask_filtered_gases, list(GAS_O2, GAS_N2O))
TYPE_TABLE(/obj/item/clothing/mask/gas/swat/vox, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_VOX))))

/obj/item/clothing/mask/gas/swat/vox/proc/feeding_port(mob/user)
	if(user.canmove && !user.stat)
		mask_open = !mask_open
		if(mask_open)
			set_body_parts_covered(EYES)
			to_chat(user, "Your mask moves to allow you to eat.")
		else
			set_body_parts_covered(FACE|EYES)
			to_chat(user, "Your mask moves to cover your mouth.")
	return

CAPABILITIES(/obj/item/clothing/mask/gas/swat/vox)
	configure(item_worn(flags = BLOCK_GAS_SMOKE_EFFECT | AIRTIGHT))
	op("vox_mask_port_self", in_hand(), label("Feeding port"), then(PROC_REF(vox_mask_port_self)))

/// Old attack_self.
/obj/item/clothing/mask/gas/swat/vox/proc/vox_mask_port_self(datum/act/op/A)
	var/mob/user = A.actor
	feeding_port(user)

/obj/item/clothing/mask/gas/zaddat
	name = "Zaddat Veil"
	desc = "A clear survival mask used by the Zaddat to filter out harmful nitrogen. Can be connected to an air supply and reconfigured to allow for safe eating."
	icon_state = "zaddat_mask"
	item_state = "vax_mask"

CAPABILITIES(/obj/item/clothing/mask/gas/zaddat)
	configure(item_worn(hides = HIDEEARS))

TYPE_TABLE(/obj/item/clothing/mask/gas/zaddat, gasmask_filtered_gases, list(GAS_PHORON, GAS_N2, GAS_N2O))

TYPE_TABLE(/obj/item/clothing/mask/gas/zaddat, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_ZADDAT))))

/obj/item/clothing/mask/gas/syndicate
	name = "tactical mask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "swat"

CAPABILITIES(/obj/item/clothing/mask/gas/syndicate)
	configure(item_protection(siemens = 0.7))

/obj/item/clothing/mask/gas/explorer
	name = "explorer gas mask"
	desc = "A military-grade gas mask that can be connected to an air supply."
	icon_state = "explorer"
	item_state_slots = list(slot_r_hand_str = "gas", slot_l_hand_str = "gas")
	armor_spec = "melee=10;bullet=5;laser=5;energy=5;bio=50"

CAPABILITIES(/obj/item/clothing/mask/gas/explorer)
	configure(item_protection(siemens = 0.9))

/obj/item/clothing/mask/gas/clown_hat
	name = "clown wig and mask"
	desc = "A true prankster's facial attire. A clown is incomplete without their wig and mask."
	icon_state = "clown"
	item_state_slots = list(slot_r_hand_str = "clown_hat", slot_l_hand_str = "clown_hat")

/obj/item/clothing/mask/gas/sexyclown
	name = "sexy-clown wig and mask"
	desc = "A feminine clown mask for the dabbling crossdressers or female entertainers."
	icon_state = "sexyclown"
	item_state_slots = list(slot_r_hand_str = "clown_hat", slot_l_hand_str = "clown_hat")

/obj/item/clothing/mask/gas/mime
	name = "mime mask"
	desc = "The traditional mime's mask. It has an eerie facial posture."
	icon_state = "mime"
	item_state_slots = list(slot_r_hand_str = "mime", slot_l_hand_str = "mime")

/obj/item/clothing/mask/gas/monkeymask
	name = "monkey mask"
	desc = "A mask used when acting as a monkey."
	icon_state = "monkeymask"

CAPABILITIES(/obj/item/clothing/mask/gas/monkeymask)
	configure(item_worn(covers = HEAD|FACE|EYES))

/obj/item/clothing/mask/gas/sexymime
	name = "sexy mime mask"
	desc = "A traditional female mime's mask."
	icon_state = "sexymime"
	item_state_slots = list(slot_r_hand_str = "mime", slot_l_hand_str = "mime")

/obj/item/clothing/mask/gas/guy
	name = "guy fawkes mask"
	desc = "A mask stylised to depict Guy Fawkes."
	icon_state = "guyfawkes"
	item_state_slots = list(slot_r_hand_str = "mime", slot_l_hand_str = "mime")

CAPABILITIES(/obj/item/clothing/mask/gas/guy)
	configure(item_worn(hides = HIDEEARS|HIDEFACE))

/obj/item/clothing/mask/gas/commando
	name = "commando mask"
	icon_state = "fullgas"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")

CAPABILITIES(/obj/item/clothing/mask/gas/commando)
	configure(item_protection(siemens = 0.2))

/obj/item/clothing/mask/gas/cyborg
	name = "cyborg visor"
	desc = "Beep boop"
	icon_state = "death"

/obj/item/clothing/mask/gas/owl_mask
	name = "owl mask"
	desc = "Twoooo!"
	icon_state = "owl"

CAPABILITIES(/obj/item/clothing/mask/gas/owl_mask)
	configure(item_worn(covers = HEAD|FACE|EYES))


/* ChompRemoval: Oops that's a glogged implementation (intentional). Im going to properly implement obj/clothing/mask/gas/clear instead.
// Our clear gas masks don't hide faces, but changing the var on mask/gas would require un-chaging it on all children. This is nicer.
/obj/item/clothing/mask/gas/Initialize(mapload)
	. = ..()
	if(type == /obj/item/clothing/mask/gas)
		set_flags_inv(worn_of(src).hides & (~HIDEFACE))
*/

// Since we changed the gas mask sprite, if we want the old one for some reason use this.
/obj/item/clothing/mask/gas/wwii
	icon = 'icons/inventory/face/item.dmi'
	icon_override = 'icons/inventory/face/mob.dmi'

CAPABILITIES(/obj/item/clothing/mask/gas/wwii)
	configure(item_worn(hides = HIDEEARS|HIDEEYES|HIDEFACE))

/obj/item/clothing/mask/gas/imperial
	name = "imperial soldier facemask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "ge_visor"

CAPABILITIES(/obj/item/clothing/mask/gas/imperial)
	configure(item_worn(covers = FACE|EYES, hides = HIDEEARS|HIDEEYES|HIDEFACE))
