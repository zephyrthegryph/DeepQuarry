//This file was auto-corrected by findeclaration.exe on 25.5.2012 20:42:32

/// The thin view a client occupies while its mind is held outside a living
/// body (removed brain, MMI, posibrain, soulcatcher). It has no health of its
/// own: when it has a mind host with brain tissue, its status is that organ's
/// (see refresh_host_status() and code/modules/body/organs/internal/brain.dm).
/mob/living/carbon/brain
	// Views without brain tissue (digital hosts, souls) keep a simple body;
	// the old brainmob death margin stays for them.
	endurance = 2 * DEFAULT_ENDURANCE
	/// The object the view lives in (MMI, brain organ, soulcatcher).
	var/obj/item/container = null
	/// The mind host that owns this view, if any.
	var/datum/mind_host/host
	/// Set once the view has read its status from brain tissue. Only digital
	/// hosts are tissue-less: a view that loses its tissue has lost its brain.
	var/had_tissue = FALSE
	var/emp_damage = 0//Handles a type of MMI damage
	var/alert = null
	use_me = 0 //Can't use the me verb, it's a freaking immobile brain
	icon = 'icons/obj/surgery.dmi'
	icon_state = "brain1"
	no_vore = TRUE
	can_pain_emote = FALSE // Sanity/safety
	low_priority = TRUE

/mob/living/carbon/brain/Initialize(mapload)
	. = ..()
	default_language = GLOB.all_languages[LANGUAGE_GALCOM]

// a brain with a player dies and ghosts; its host forgets the view.
/mob/living/carbon/brain/on_destroy(force)
	if(key)				//If there is a mob connected to this thing. Have to check key twice to avoid false death reporting.
		if(stat != DEAD)	//If not dead.
			death(1)	//Brains can die again. AND THEY SHOULD AHA HA HA HA HA HA
		ghostize()		//Ghostize checks for key so nothing else is necessary.
	..()

/// A view names itself after the character it shows and reads the
/// character's languages by reference. The DNA belongs to the character's body,
/// so the view keeps its own copy (one owner per DNA datum).
/mob/living/carbon/brain/on_identity_bound()
	..()
	if(identity().real_name)
		real_name = identity().real_name
		name = real_name
	if(identity().get_dna())
		rel_set(src, nameof(dna), identity().get_dna().Clone())
	if(identity().languages)
		languages = identity().languages
	else
		identity().languages = languages
	sync_language_state()

/// The brain tissue this view shows, if any.
/mob/living/carbon/brain/proc/host_tissue()
	return host?.tissue()

/// Sync stat with the host: the view is dead exactly when its brain tissue is
/// brain dead (/obj/item/organ/internal/brain/proc/is_brain_dead()), or when a
/// view that had tissue has lost it. Only digital hosts stay up without tissue.
/mob/living/carbon/brain/proc/refresh_host_status()
	if(!host)
		return
	var/obj/item/organ/internal/brain/tissue = host.tissue()
	if(tissue)
		had_tissue = TRUE
	if(tissue ? tissue.is_brain_dead() : had_tissue)
		if(stat != DEAD)
			log_game("MIND: view [key_name(src)] in [host.owner] died: [tissue ? "its brain tissue is brain dead" : "its brain tissue is gone"].")
			death()
		return
	if(stat == DEAD && return_from_death("brain tissue recovered", tissue, REVIVE_IGNORE_WINDOW) == TRUE)
		set_blinded(0)
	update_canmove()

/mob/living/carbon/brain/say_understands(other)//Goddamn is this hackish, but this say code is so odd
	if(istype(container, /obj/item/mmi))
		if(issilicon(other))
			return TRUE
	if(ishuman(other))
		return TRUE
	if(isslime(other))
		return TRUE
	return ..()

/mob/living/carbon/brain/update_canmove()
	if(in_contents_of(/obj/mecha) || istype(loc, /obj/item/mmi))
		canmove = 1
		use_me = 1
	else
		canmove = 0
	return canmove

/// A brain in a man-machine interface is housed in a machine: its systemic
/// biology is the housing's.
/mob/living/carbon/brain/biology()
	return istype(loc, /obj/item/mmi) ? BIOLOGY_SYNTHETIC : ..()

/mob/living/carbon/brain/runechat_holder(datum/chatmessage/CM)
	if(isturf(loc))
		return ..()

	return loc

// start

/mob/living/carbon/brain/verb/backup_ping()
	set category = VERB_CAT_IC_GAME
	set name = "Notify Transcore"
	set desc = "Your body is gone. Notify robotics to be resleeved!"
	backup_ping_resolve()

/// The Notify Transcore verb's work. A brain with no mind or no backup record gets the no-backup
/// answer instead of a runtime (audit A7). Returns TRUE when a notification was sent.
/mob/living/carbon/brain/proc/backup_ping_resolve()
	var/datum/transcore_db/db = mind ? SStranscore.db_by_mind_name(mind.name) : null
	var/datum/transhuman/mind_record/record = db?.backed_up[mind.name]
	if(!record)
		to_chat(src, span_warning("No backup record could be found, sorry."))
		return FALSE
	if(!(record.dead_state == MR_DEAD))
		if((world.time - identity().time_of_death) > 5 MINUTES)	//Allows notify transcore to be used if you have an entry but for some reason weren't marked as dead
			record.dead_state = MR_DEAD				//Such as if you got scanned but didn't take an implant. It's a little funky, but I mean, you got scanned
			db.notify(record)						//So you probably will want to let someone know if you die.
			EXPIRY_STAMP(record, last_notification, CLOCK_WORLD)
			to_chat(src, span_notice("New notification has been sent."))
		else
			to_chat(src, span_warning("Your backup is not past-due yet."))
	else if(ELAPSED_SINCE(src, record.last_notification, CLOCK_WORLD) < 5 MINUTES)
		to_chat(src, span_warning("Too little time has passed since your last notification."))
	else
		db.notify(record)
		EXPIRY_STAMP(record, last_notification, CLOCK_WORLD)
		to_chat(src, span_notice("New notification has been sent."))

CAPABILITIES(/mob/living/carbon/brain)
	reagents(1000)
	ref_one(nameof(container)) // back reference to what holds us (an MMI, a soulcatcher); never owned by the brainmob
