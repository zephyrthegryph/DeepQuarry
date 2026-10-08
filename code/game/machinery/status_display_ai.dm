/datum/ai_emotion
	var/overlay
	var/ckey

/datum/ai_emotion/New(over, key)
	overlay = over
	ckey = key

GLOBAL_LIST_INIT(ai_status_emotions, list(
	"Very Happy" 				= new /datum/ai_emotion("ai_veryhappy"),
	"Happy" 					= new /datum/ai_emotion("ai_happy"),
	"Neutral" 					= new /datum/ai_emotion("ai_neutral"),
	"Unsure" 					= new /datum/ai_emotion("ai_unsure"),
	"Confused" 					= new /datum/ai_emotion("ai_confused"),
	"Sad" 						= new /datum/ai_emotion("ai_sad"),
	"Surprised" 				= new /datum/ai_emotion("ai_surprised"),
	"Upset" 					= new /datum/ai_emotion("ai_upset"),
	"Angry" 					= new /datum/ai_emotion("ai_angry"),
	"BSOD" 						= new /datum/ai_emotion("ai_bsod"),
	"Blank" 					= new /datum/ai_emotion("ai_off"),
	"Problems?" 				= new /datum/ai_emotion("ai_trollface"),
	"Awesome" 					= new /datum/ai_emotion("ai_awesome"),
	"Dorfy" 					= new /datum/ai_emotion("ai_urist"),
	"Facepalm" 					= new /datum/ai_emotion("ai_facepalm"),
	"Friend Computer" 			= new /datum/ai_emotion("ai_friend"),
	"Corgi" 					= new /datum/ai_emotion("ai_corgi"),
	"Communist" 				= new /datum/ai_emotion("ai_redoctober"),
	"Heart" 					= new /datum/ai_emotion("ai_heart"),
	"Tribunal" 					= new /datum/ai_emotion("ai_tribunal", "serithi"),
	"Tribunal Malfunctioning"	= new /datum/ai_emotion("ai_tribunal_malf", "serithi")
	))

/proc/get_ai_emotions(ckey)
	var/list/emotions = list()
	for(var/emotion_name in GLOB.ai_status_emotions)
		var/datum/ai_emotion/emotion = GLOB.ai_status_emotions[emotion_name]
		if(!emotion.ckey || emotion.ckey == ckey)
			emotions += emotion_name

	return emotions

/mob/living/silicon/ai/proc/set_ai_status_displays()
	perform_op(src, src, "ai_status_displays", null, ORIGIN_SYSTEM)

/mob/living/silicon/ai/proc/status_display_options(datum/act/op/A)
	return get_ai_emotions(ckey)

/mob/living/silicon/ai/proc/ai_status_display_chosen(datum/act/op/A)
	var/emote = A.step_value("emotion")
	for (var/obj/machinery/M in REGISTRY_MEMBERS(REGISTRY_MACHINES)) //change status
		if(istype(M, /obj/machinery/ai_status_display))
			var/obj/machinery/ai_status_display/AISD = M
			AISD.emotion = emote
			AISD.update()
		//if Friend Computer, change ALL displays
		else if(istype(M, /obj/machinery/status_display))

			var/obj/machinery/status_display/SD = M
			if(emote=="Friend Computer")
				SD.friendc = 1
			else
				SD.friendc = 0
			SD.refresh()

/obj/machinery/ai_status_display
	icon = 'icons/obj/status_display.dmi'
	icon_state = "frame"
	layer = ABOVE_WINDOW_LAYER
	name = "AI display"
	anchored = TRUE
	density = FALSE
	circuit =  /obj/item/circuitboard/ai_status_display
	flags = WALL_ITEM

	mode = 0	// 0 = Blank
					// 1 = AI emoticon
					// 2 = Blue screen of death

	var/picture_state	// icon_state of ai picture

	var/emotion = "Neutral"

/obj/machinery/ai_status_display/proc/emotion_options(datum/act/op/A)
	return get_ai_emotions(A.actor.ckey)

/obj/machinery/ai_status_display/proc/emotion_selected(datum/act/op/A)
	emotion = A.step_value("emotion")
	return OP_OK

/obj/machinery/ai_status_display/proc/update()
	if(mode==0) //Blank
		cut_overlays()
		return

	if(mode==1)	// AI emoticon
		var/datum/ai_emotion/ai_emotion = GLOB.ai_status_emotions[emotion]
		set_picture(ai_emotion.overlay)
		return

	if(mode==2)	// BSOD
		set_picture("ai_bsod")
		return

/obj/machinery/ai_status_display/proc/set_picture(state)
	picture_state = state
	cut_overlays()
	add_overlay(picture_state)

/obj/machinery/ai_status_display/power_change()
	. = ..()
	if(power_lost())
		cut_overlays()
	else
		update()

MSG_DEF_SELF(ai_status_display/needs_item, "needs an item")

CAPABILITIES(/obj/machinery/ai_status_display)
	op("touch", inputs(item(/obj/item), menu()), priority(OP_PRIORITY_DEFAULT - 1), label("Use"), needs(req(/obj/item, because = MSG(ai_status_display/needs_item)), req_adjacent(), req_capable()), then(TYPE_PROC_REF(/atom, op_as_touch)))
	op("set_status", remote(), label("Set status"), wait(0), asks(/datum/prompt/choice, fields = list("title" = "AI Status", "question" = "Please, select a status:", "choices" = computed(PROC_REF(emotion_options)), "timeout" = 0), step = "emotion"), then(PROC_REF(emotion_selected)))
	display_disconnect_op()
