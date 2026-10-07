/obj/item/clothing/mask/gas
	name = "gas mask"
	desc = "A face-covering mask that can be connected to an air supply. Filters harmful gases from the air."
	icon_state = "gas_alt"
	item_flags = BLOCK_GAS_SMOKE_EFFECT | AIRTIGHT | ALLOW_SURVIVALFOOD
	flags_inv = HIDEEARS|HIDEEYES|HIDEFACE
	body_parts_covered = FACE|EYES
	w_class = ITEMSIZE_NORMAL
	item_state_slots = list(slot_r_hand_str = "gas_alt", slot_l_hand_str = "gas_alt")
	gas_transfer_coefficient = 0.01
	permeability_coefficient = 0.01
	siemens_coefficient = 0.9
	var/gas_filter_strength = 1			//For gas mask filters
	armor_spec = "bio=75"
	pickup_sound = SFX_ITEMS_PICKUP_RUBBER
	resistance_flags = FIRE_PROOF

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
	flags_inv = null

/obj/item/clothing/mask/gas/half
	name = "face mask"
	desc = "A compact, durable gas mask that can be connected to an air supply."
	icon_state = "halfgas"
	siemens_coefficient = 0.7
	body_parts_covered = FACE
	w_class = ITEMSIZE_SMALL
	armor_spec = "melee=10;bullet=10;laser=10;bio=55"

//Turn it into a hailer mask
CAPABILITIES(/obj/item/clothing/mask/gas/half)
	op("half_mask_add_hailer_item", item(/obj/item), label("Half mask add hailer item"), needs(req(PROC_REF(can_fit_hailer_holds), because = PROC_REF(can_fit_hailer_refusal))), then(PROC_REF(half_mask_add_hailer_item)))

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
/// Requirement (was REQ_* can_fit_hailer): the legacy check answers TRUE to pass.
/obj/item/clothing/mask/gas/half/proc/can_fit_hailer_holds(datum/act/op/A)
	var/answer = can_fit_hailer(A.actor, src, A.held)
	return !istext(answer) && !!answer

/// Why can_fit_hailer_holds refuses: the legacy check's text, else the clause's own reason.
/obj/item/clothing/mask/gas/half/proc/can_fit_hailer_refusal(datum/act/op/A)
	var/answer = can_fit_hailer(A.actor, src, A.held)
	return istext(answer) ? answer : /datum/msg/req_failed

/obj/item/clothing/mask/gas/half/proc/half_mask_add_hailer_item(datum/act/op/A)
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
	body_parts_covered = HEAD|FACE|EYES
	heat_protection = HEAD
	cold_protection = HEAD

/obj/item/clothing/mask/gas/plaguedoctor/gold
	name = "gold plague doctor mask"
	desc = "A modernised version of the classic design, this mask will not only filter out phoron but it can also be connected to an air supply. This one is gold."
	icon_state = "plaguedoctor2"

/obj/item/clothing/mask/gas/swat
	name = "\improper SWAT mask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "swat"
	siemens_coefficient = 0.7
	body_parts_covered = FACE|EYES

// Vox mask, has special code for eating
/obj/item/clothing/mask/gas/swat/vox
	name = "\improper alien mask"
	desc = "Clearly not designed for a human face."
	flags = PHORONGUARD
	item_flags = BLOCK_GAS_SMOKE_EFFECT | AIRTIGHT
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
			body_parts_covered = EYES
			to_chat(user, "Your mask moves to allow you to eat.")
		else
			body_parts_covered = FACE|EYES
			to_chat(user, "Your mask moves to cover your mouth.")
	return

CAPABILITIES(/obj/item/clothing/mask/gas/swat/vox)
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
	flags_inv = HIDEEARS //semi-transparent

TYPE_TABLE(/obj/item/clothing/mask/gas/zaddat, gasmask_filtered_gases, list(GAS_PHORON, GAS_N2, GAS_N2O))

TYPE_TABLE(/obj/item/clothing/mask/gas/zaddat, fit_spec, list(REQ_FITS_BODYTYPES(list(SPECIES_ZADDAT))))

/obj/item/clothing/mask/gas/syndicate
	name = "tactical mask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "swat"
	siemens_coefficient = 0.7

/obj/item/clothing/mask/gas/explorer
	name = "explorer gas mask"
	desc = "A military-grade gas mask that can be connected to an air supply."
	icon_state = "explorer"
	item_state_slots = list(slot_r_hand_str = "gas", slot_l_hand_str = "gas")
	armor_spec = "melee=10;bullet=5;laser=5;energy=5;bio=50"
	siemens_coefficient = 0.9

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
	body_parts_covered = HEAD|FACE|EYES

/obj/item/clothing/mask/gas/sexymime
	name = "sexy mime mask"
	desc = "A traditional female mime's mask."
	icon_state = "sexymime"
	item_state_slots = list(slot_r_hand_str = "mime", slot_l_hand_str = "mime")

/obj/item/clothing/mask/gas/guy
	name = "guy fawkes mask"
	desc = "A mask stylised to depict Guy Fawkes."
	icon_state = "guyfawkes"
	flags_inv = HIDEEARS|HIDEFACE
	item_state_slots = list(slot_r_hand_str = "mime", slot_l_hand_str = "mime")

/obj/item/clothing/mask/gas/commando
	name = "commando mask"
	icon_state = "fullgas"
	item_state_slots = list(slot_r_hand_str = "swat", slot_l_hand_str = "swat")
	siemens_coefficient = 0.2

/obj/item/clothing/mask/gas/cyborg
	name = "cyborg visor"
	desc = "Beep boop"
	icon_state = "death"

/obj/item/clothing/mask/gas/owl_mask
	name = "owl mask"
	desc = "Twoooo!"
	icon_state = "owl"
	body_parts_covered = HEAD|FACE|EYES


/* ChompRemoval: Oops that's a glogged implementation (intentional). Im going to properly implement obj/clothing/mask/gas/clear instead.
// Our clear gas masks don't hide faces, but changing the var on mask/gas would require un-chaging it on all children. This is nicer.
/obj/item/clothing/mask/gas/Initialize(mapload)
	. = ..()
	if(type == /obj/item/clothing/mask/gas)
		flags_inv &= ~HIDEFACE
*/

// Since we changed the gas mask sprite, if we want the old one for some reason use this.
/obj/item/clothing/mask/gas/wwii
	icon = 'icons/inventory/face/item.dmi'
	icon_override = 'icons/inventory/face/mob.dmi'
	flags_inv = HIDEEARS|HIDEEYES|HIDEFACE

/obj/item/clothing/mask/gas/imperial
	name = "imperial soldier facemask"
	desc = "A close-fitting tactical mask that can be connected to an air supply."
	icon_state = "ge_visor"
	body_parts_covered = FACE|EYES
	flags_inv = HIDEEARS|HIDEEYES|HIDEFACE
