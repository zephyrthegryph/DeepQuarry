/**************
* AI-specific *
**************/
/obj/item/camera/siliconcam
	var/in_camera_mode = 0
	var/photos_taken = 0
	var/list/obj/item/photo/aipictures

CAPABILITIES(/obj/item/camera/siliconcam)
	owns_many(nameof(aipictures), /obj/item/photo)

/obj/item/camera/siliconcam/ai_camera //camera AI can take pictures with
	name = "AI photo camera"

/obj/item/camera/siliconcam/robot_camera //camera cyborgs can take pictures with
	name = "Cyborg photo camera"

/obj/item/camera/siliconcam/drone_camera //currently doesn't offer the verbs, thus cannot be used
	name = "Drone photo camera"


/obj/item/camera/siliconcam/proc/injectaialbum(obj/item/photo/p, sufix = "") //stores image information to a list similar to that of the datacore
	move_into(src, nameof(src.aipictures), p)
	photos_taken++
	p.name = "Image [photos_taken][sufix]"

/obj/item/camera/siliconcam/proc/injectmasteralbum(mob/user, obj/item/photo/p) //stores image information to a list similar to that of the datacore
	var/mob/living/silicon/robot/C = user
	if(C.connected_ai)
		C.connected_ai.aiCamera.injectaialbum(p.copy(1), " (synced from [C.name])")
		to_chat(C.connected_ai, span_unconscious("Image uploaded by [C.name]"))
		to_chat(user, span_unconscious("Image synced to remote database"))	//feedback to the Cyborg player that the picture was taken
	else
		to_chat(user, span_unconscious("Image recorded"))
	// Always save locally
	injectaialbum(p)

/obj/item/camera/siliconcam/proc/selectpicture(mob/user, obj/item/camera/siliconcam/cam)
	if(!cam)
		cam = getsource(user)

	var/list/nametemp = list()
	var/find
	if(length(cam.aipictures) == 0)
		to_chat(user, span_userdanger("No images saved"))
		return
	for(var/obj/item/photo/t in cam.aipictures)
		nametemp += t.name
	var/_answer_k50 = rerun_ask(user, "k50", PROC_REF(selectpicture), args, /datum/prompt/choice, question = "Select image (numbered in order taken)", title = "Picture Choice", choices = nametemp)
	if(isnull(_answer_k50))
		return
	find = _answer_k50
	if(!find)
		return

	for(var/obj/item/photo/q in cam.aipictures)
		if(q.name == find)
			return q

/obj/item/camera/siliconcam/proc/viewpictures(mob/user)
	open_album_choice(user, null, "view")

/obj/item/camera/siliconcam/proc/deletepicture(mob/user, obj/item/camera/siliconcam/cam)
	open_album_choice(user, cam, "delete")

/obj/item/camera/siliconcam/proc/open_album_choice(mob/user, obj/item/camera/siliconcam/cam, album_action)
	var/obj/item/camera/siliconcam/source_cam = cam || getsource(user)
	if(!length(source_cam.aipictures))
		to_chat(user, span_userdanger("No images saved"))
		return
	var/list/names = list()
	for(var/obj/item/photo/photo in source_cam.aipictures)
		names += photo.name
	open_request(src, /datum/prompt/choice/silicon_album, PROC_REF(album_choice_entered), answerer = user, subject = cam, choices = names, album_action = album_action, captured = list("explicit_camera" = !isnull(cam)))

/obj/item/camera/siliconcam/proc/album_choice_entered(datum/act/request/A)
	var/datum/prompt/choice/silicon_album/ask = A.request
	if(!A.answer)
		if(ask.last_error == "not local")
			to_chat(ask.answerer, span_warning("Only local images can be deleted."))
		return
	var/mob/user = ask.answerer
	var/obj/item/camera/siliconcam/source_cam = ask.album_source()
	if(!length(source_cam.aipictures))
		to_chat(user, span_userdanger("No images saved"))
		return
	var/obj/item/photo/selection = ask.selected_picture()
	if(!selection)
		return
	if(ask.album_action == "view")
		selection.show(user)
		if(selection.desc)
			to_chat(user, selection.desc)
	else if(consume(selection, user))
		to_chat(user, span_unconscious("Local image deleted"))

/datum/prompt/choice/silicon_album
	question = "Select image (numbered in order taken)"
	title = "Picture Choice"
	timeout = 0
	recheck_on_open = TRUE
	var/album_action

/datum/prompt/choice/silicon_album/proc/album_source()
	if(captured["explicit_camera"])
		return subject
	var/obj/item/camera/siliconcam/camera = owner
	return camera.getsource(answerer)

/datum/prompt/choice/silicon_album/proc/selected_picture()
	if(!value)
		return null
	var/obj/item/camera/siliconcam/source_cam = album_source()
	for(var/obj/item/photo/photo in source_cam.aipictures)
		if(photo.name == value)
			return photo
	return null

/datum/prompt/choice/silicon_album/recheck_extra()
	var/obj/item/camera/siliconcam/camera = owner
	if(QDELETED(camera) || QDELETED(answerer))
		return "gone"
	if(captured["explicit_camera"] && QDELETED(subject))
		return "gone"
	if(album_action == "delete")
		var/obj/item/photo/selected = selected_picture()
		if(selected && !(selected in camera.aipictures))
			return "not local"
	return null

/obj/item/camera/siliconcam/ai_camera/can_capture_turf(turf/T, mob/user)
	var/mob/living/silicon/ai = user
	return ai.TurfAdjacent(T)

/obj/item/camera/siliconcam/proc/toggle_camera_mode(mob/user)
	if(in_camera_mode)
		camera_mode_off(user)
	else
		camera_mode_on(user)

/obj/item/camera/siliconcam/proc/camera_mode_off(mob/user)
	src.in_camera_mode = 0
	to_chat(user, span_infoplain(span_bold("Camera Mode deactivated")))

/obj/item/camera/siliconcam/proc/camera_mode_on(mob/user)
	src.in_camera_mode = 1
	to_chat(user, span_infoplain(span_bold("Camera Mode activated")))

/obj/item/camera/siliconcam/ai_camera/printpicture(mob/user, obj/item/photo/p)
	injectaialbum(p)
	to_chat(user, span_unconscious("Image recorded"))

/obj/item/camera/siliconcam/robot_camera/printpicture(mob/user, obj/item/photo/p)
	injectmasteralbum(user, p)

/mob/living/silicon/ai/proc/take_image()
	set category = VERB_CAT_AI_COMMANDS
	set name = "Take Image"
	set desc = "Takes an image"

	if(aiCamera)
		aiCamera.toggle_camera_mode(src)

/mob/living/silicon/ai/proc/view_images()
	set category = VERB_CAT_AI_COMMANDS
	set name = "View Images"
	set desc = "View images"

	if(aiCamera)
		aiCamera.viewpictures(src)

/mob/living/silicon/ai/proc/delete_images()
	set category = VERB_CAT_AI_COMMANDS
	set name = "Delete Image"
	set desc = "Delete image"

	if(aiCamera)
		aiCamera.deletepicture(src)

/mob/living/silicon/robot/proc/take_image()
	set category =VERB_CAT_ABILITIES_SILICON
	set name = "Take Image"
	set desc = "Takes an image"

	if(aiCamera)
		aiCamera.toggle_camera_mode(src)

/mob/living/silicon/robot/proc/view_images()
	set category =VERB_CAT_ABILITIES_SILICON
	set name = "View Images"
	set desc = "View images"

	if(aiCamera)
		aiCamera.viewpictures(src)

/mob/living/silicon/robot/proc/delete_images()
	set category = VERB_CAT_ABILITIES_SILICON
	set name = "Delete Image"
	set desc = "Delete a local image"

	if(aiCamera)
		aiCamera.deletepicture(src)

/obj/item/camera/siliconcam/proc/getsource(mob/user)
	if(isAI(src.loc))
		return src

	var/mob/living/silicon/robot/C = user
	var/obj/item/camera/siliconcam/Cinfo
	if(C.connected_ai)
		Cinfo = C.connected_ai.aiCamera
	else
		Cinfo = src
	return Cinfo

/mob/living/silicon/proc/GetPicture()
	if(!aiCamera)
		return
	return aiCamera.selectpicture(src)
