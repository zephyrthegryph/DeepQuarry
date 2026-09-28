/obj/item/voice_changer
	name = "voice changer"
	desc = "A voice scrambling module. If you can see this, report it as a bug on the tracker."
	var/voice = null //If set and item is present in mask/suit, this name will be used for the wearer's speech.
	var/active = TRUE

/obj/item/clothing/mask/gas/voice
	name = "gas mask"
	desc = "A face-covering mask that can be connected to an air supply. It seems to house some odd electronics."
	var/obj/item/voice_changer/changer // ALLOW(state_ref): baseline when CI was wired (2026-09-26); convert or give a real reason

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
	var/new_name = rerun_ask(user, "a1", PROC_REF(voice_set_voice_verb), list(user), /datum/om/prompt/text, message = "Whose voice should it mimic?", title = "Set Voice", max_length = MAX_NAME_LEN)
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

DECLARE_DEFAULT_CHILD(/obj/item/clothing/mask/gas/voice, "changer", /obj/item/voice_changer)

DECLARE_REF(/obj/item/clothing/mask/gas/voice, "changer", OWNED, null)
