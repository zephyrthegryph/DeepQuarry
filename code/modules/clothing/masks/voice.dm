/obj/item/voice_changer
	name = "voice changer"
	desc = "A voice scrambling module. If you can see this, report it as a bug on the tracker."
	var/voice = null //If set and item is present in mask/suit, this name will be used for the wearer's speech.
	var/active = TRUE

/obj/item/clothing/mask/gas/voice
	name = "gas mask"
	desc = "A face-covering mask that can be connected to an air supply. It seems to house some odd electronics."
	var/obj/item/voice_changer/changer // owned: the voice changer module, kept in the mask's contents

EXTEND_INTERACTIONS(/obj/item/clothing/mask/gas/voice, \
	INTERACT_VERB("Toggle Voice Changer", PROC_REF(voice_toggle_voice_changer_verb), REQ_IN_INVENTORY), \
	INTERACT_VERB("Set Voice", PROC_REF(voice_set_voice_verb), REQ_IN_INVENTORY), \
	INTERACT_VERB("Reset Voice", PROC_REF(voice_reset_voice_verb), REQ_IN_INVENTORY), \
)

/// Old verb "Toggle Voice Changer".
/obj/item/clothing/mask/gas/voice/proc/voice_toggle_voice_changer_verb(mob/user, obj/item/held, datum/interaction/interaction)
	changer.active = !changer.active
	to_chat(user, span_notice("You [changer.active ? "enable" : "disable"] the voice-changing module in \the [src]."))

/// Old verb "Set Voice".
/obj/item/clothing/mask/gas/voice/proc/voice_set_voice_verb(mob/user, obj/item/held, datum/interaction/interaction)
	open_request(src, /datum/prompt/text, PROC_REF(voice_name_entered), answerer = user, question = "Whose voice should it mimic?", title = "Set Voice", max_len = MAX_NAME_LEN, name_text = TRUE, timeout = 0)

/obj/item/clothing/mask/gas/voice/proc/voice_name_entered(datum/act/request/A)
	if(!A.answer)
		return
	var/mob/user = A.request.answerer
	var/new_name = A.answer.answer_value
	if(isnull(new_name) || get(src, /mob) != user)
		return
	var/voice = sanitize(new_name, MAX_NAME_LEN)
	if(!voice || !length(voice)) return
	changer.voice = voice
	to_chat(user, span_notice("You are now mimicking <B>[changer.voice]</B>."))

/// Old verb "Reset Voice".
/obj/item/clothing/mask/gas/voice/proc/voice_reset_voice_verb(mob/user, obj/item/held, datum/interaction/interaction)
	changer.voice = null
	to_chat(user, span_notice("You have reset your voice changer's mimicry feature."))

CAPABILITIES(/obj/item/clothing/mask/gas/voice)
	owns_one(nameof(changer), starts = /obj/item/voice_changer)

