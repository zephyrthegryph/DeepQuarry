/obj/item/voice_changer
	name = "voice changer"
	desc = "A voice scrambling module. If you can see this, report it as a bug on the tracker."
	var/voice = null //If set and item is present in mask/suit, this name will be used for the wearer's speech.
	var/active = TRUE

/obj/item/clothing/mask/gas/voice
	name = "gas mask"
	desc = "A face-covering mask that can be connected to an air supply. It seems to house some odd electronics."
	var/obj/item/voice_changer/changer // owned: the voice changer module, kept in the mask's contents

/// Old verb "Toggle Voice Changer".
/obj/item/clothing/mask/gas/voice/proc/voice_toggle_voice_changer_verb(datum/act/op/A)
	var/mob/user = A.actor
	changer.active = !changer.active
	to_chat(user, span_notice("You [changer.active ? "enable" : "disable"] the voice-changing module in \the [src]."))

/// Old verb "Set Voice".
/obj/item/clothing/mask/gas/voice/proc/voice_set_voice_verb(datum/act/op/A)
	var/mob/user = A.actor
	var/new_name = A.step_answer("a1").answer_value
	if(get(src, /mob) != user)
		return
	var/voice = sanitize(new_name, MAX_NAME_LEN)
	if(!voice || !length(voice)) return
	changer.voice = voice
	to_chat(user, span_notice("You are now mimicking <B>[changer.voice]</B>."))

/// Old verb "Reset Voice".
/obj/item/clothing/mask/gas/voice/proc/voice_reset_voice_verb(datum/act/op/A)
	var/mob/user = A.actor
	changer.voice = null
	to_chat(user, span_notice("You have reset your voice changer's mimicry feature."))

CAPABILITIES(/obj/item/clothing/mask/gas/voice)
	owns_one(nameof(changer), starts = /obj/item/voice_changer)
	op("voice_toggle_voice_changer_verb", menu(), label("Toggle Voice Changer"), needs(carried()), then(PROC_REF(voice_toggle_voice_changer_verb)))
	op("voice_set_voice_verb", menu(), label("Set Voice"), needs(carried()), asks(/datum/prompt/text, fields = list("question" = "Whose voice should it mimic?", "title" = "Set Voice", "max_len" = MAX_NAME_LEN, "name_text" = TRUE, "timeout" = 0), step = "a1"), then(PROC_REF(voice_set_voice_verb)))
	op("voice_reset_voice_verb", menu(), label("Reset Voice"), needs(carried()), then(PROC_REF(voice_reset_voice_verb)))

