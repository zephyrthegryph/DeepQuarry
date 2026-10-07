/obj/item/organ/internal/eyes
	name = "eyeballs"
	icon_state = "eyes"
	gender = PLURAL
	organ_tag = O_EYES
	parent_organ = BP_HEAD
	/// r, g, b; null until update_colour() (black).
	var/list/eye_colour
	var/innate_flash_protection = FLASH_PROTECTION_NONE

/obj/item/organ/internal/eyes/robotize()
	..()
	name = "optical sensor"
	grant(src, granted_verb(/obj/item/organ/internal/eyes/proc/change_eye_color), src)
	organ_verbs = list(/obj/item/organ/internal/eyes/proc/change_eye_color)
	handle_organ_mod_special()

/obj/item/organ/internal/eyes/robot
	name = "optical sensor"

/obj/item/organ/internal/eyes/robot/Initialize(mapload, internal)
	. = ..()
	robotize()

/obj/item/organ/internal/eyes/grey
	icon_state = "eyes_grey"


CAPABILITIES(/obj/item/organ/internal/eyes/grey/colormatch)
	after_init(0, then(PROC_REF(match_blood_color)))

/// Takes its owner's blood colour, once the body has placed it.
/obj/item/organ/internal/eyes/grey/colormatch/proc/match_blood_color(datum/act/timer/A)
	if(ishuman(owner)) // placed in its limb by now
		var/mob/living/carbon/human/H = owner
		color = H.species.blood_color

/obj/item/organ/internal/eyes/proc/change_eye_color()
	set name = "Change Eye Color"
	set desc = "Changes your robotic eye color instantly."
	set category = VERB_CAT_IC_SETTINGS
	set src in usr

	if(!owner)
		return
	open_request(src, /datum/prompt/color/eye_color, PROC_REF(eye_color_picked), answerer = owner, default = eye_rgb())

/datum/prompt/color/eye_color
	timeout = 0
	title = "Eye Color"
	question = "Pick a new color for your eyes."

/datum/prompt/color/eye_color/recheck_extra()
	. = ..()
	if(.)
		return
	var/obj/item/organ/internal/eyes/E = owner
	if(!istype(E) || E.owner != answerer)
		return "no longer your eyes"
	return null

/obj/item/organ/internal/eyes/proc/eye_color_picked(datum/act/request/A)
	if(!A.answer)
		return
	var/new_color = A.answer.value
	if(new_color && owner)
		// input() supplies us with a hex color, which we can't use, so we convert it to rbg values.
		var/list/new_color_rgb_list = hex2rgb(new_color)
		// First, update mob vars.
		owner.r_eyes = new_color_rgb_list[1]
		owner.g_eyes = new_color_rgb_list[2]
		owner.b_eyes = new_color_rgb_list[3]
		// Now sync the organ's eye_colour list.
		update_colour()
		// Finally, update the eye icon on the mob.
		owner.regenerate_icons()

/obj/item/organ/internal/eyes/replaced(mob/living/carbon/human/target)

	// Apply our eye colour to the target.
	if(istype(target) && eye_colour)
		target.r_eyes = eye_colour[1]
		target.g_eyes = eye_colour[2]
		target.b_eyes = eye_colour[3]
		target.update_eyes()
	..()

/// The eye colour as a hex string.
/obj/item/organ/internal/eyes/proc/eye_rgb()
	return eye_colour ? rgb(eye_colour[1], eye_colour[2], eye_colour[3]) : rgb(0, 0, 0)

/obj/item/organ/internal/eyes/proc/update_colour()
	if(!owner)
		return
	eye_colour = list(
		owner.r_eyes ? owner.r_eyes : 0,
		owner.g_eyes ? owner.g_eyes : 0,
		owner.b_eyes ? owner.b_eyes : 0
		)

/obj/item/organ/internal/eyes/apply_lesion_damage(amount, lesion_type = null, silent = FALSE)
	var/oldbroken = is_broken()
	. = ..()
	if(is_broken() && !oldbroken && owner && !owner.stat)
		to_chat(owner, span_danger("You go blind!"))

/obj/item/organ/internal/eyes/organ_tick(cycles) //Eye damage replaces the old eye_stat var.
	..()
	if(!owner) return

	if(is_bruised())
		owner.status_set(STAT_BLURRY, 20)
	if(is_broken())
		owner.status_at_least(STAT_BLINDED, 20)

/obj/item/organ/internal/eyes/handle_germ_effects(cycles)
	. = ..() //Up should return an infection level as an integer
	if(!.) return

	//Conjunctivitis
	if (. >= 1)
		if(prob(1))
			owner.custom_pain("The corners of your eyes itch! It's quite frustrating.",0)
	if (. >= 2)
		if(prob(1))
			owner.custom_pain("Your eyes are watering, making it harder to see clearly for a moment.",1)
			owner.status_adjust(STAT_BLURRY, 10)

/obj/item/organ/internal/eyes/proc/get_total_protection(flash_protection = FLASH_PROTECTION_NONE)
	return (flash_protection + innate_flash_protection)

/obj/item/organ/internal/eyes/proc/additional_flash_effects(intensity)
	return -1

/// Robotic eyes blur their owner's sight on a pulse.
/obj/item/organ/internal/eyes/organ_emp(datum/act/A)
	..()
	var/datum/notice/hit/emp/N = A
	var/datum/damage_packet/packet = N.packet
	if(!robotic || !owner)
		return
	owner.status_adjust(STAT_BLURRY, (4/packet.severity))

// When this organ's organ_tick() has nothing to do: the organ clock may park (/obj/item/organ/proc/life_step_idle()).
/obj/item/organ/internal/eyes/life_step_idle()
	return ..() && !is_bruised()
