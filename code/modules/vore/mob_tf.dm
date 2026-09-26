// Procs for living mobs based around mob transformation. Initially made for the mouseray, they are now used in various other places and the main procs are now called from here.

/mob/living/proc/tf_into(A, allow_emotes = FALSE, object_name)
	if(isliving(A))
		var/mob/living/M = A
		transform_into_mob(M, FALSE)
		return
	if(isitem(A))
		if(!object_name)
			object_name = name
		var/obj/item/I = A
		I.inhabit_item(src, object_name, src, allow_emotes)
		var/mob/living/possessed_voice = I.possessed_voice
		I.trash_eatable = devourable
		I.unacidable = !digestable
		forceMove(possessed_voice)

/mob/living/proc/mob_belly_transfer(mob/living/M)
	for(var/obj/belly/B as anything in M.vore_organs)
		B.loc = src
		B.forceMove(src)
		B.owner = src
		M.vore_organs -= B
		LAZYADD(src.vore_organs, B)

/mob/living/proc/transfer_mob_identity(mob/living/new_mob)
	for(var/obj/belly/B as anything in new_mob.vore_organs)
		new_mob.vore_organs -= B
		qdel(B)
	new_mob.vore_organs = list()
	new_mob.name = src.name
	new_mob.real_name = src.real_name
	for(var/lang in src.languages)
		new_mob.languages |= lang
	src.copy_vore_prefs_to_mob(new_mob)
	new_mob.vore_selected = src.vore_selected
	if(ishuman(src))
		var/mob/living/carbon/human/H = src
		if(ishuman(new_mob))
			var/mob/living/carbon/human/N = new_mob
			N.gender = H.gender
			N.identifying_gender = H.identifying_gender
		else
			new_mob.gender = H.gender
	else
		new_mob.gender = src.gender
		if(ishuman(new_mob))
			var/mob/living/carbon/human/N = new_mob
			N.identifying_gender = src.gender

	new_mob.mob_belly_transfer(src)
	new_mob.nutrition = src.nutrition

	src.soulgem?.transfer_self(new_mob)

/mob/living
	var/mob/living/tf_mob_holder = null

/// The player in this transformed form goes back to its original body
/// (tf_mob_holder) through its mind, binding its identity there again.
/mob/living/proc/return_player_to_tf_holder(reason)
	if(!tf_mob_holder)
		return FALSE
	return move_player(src, tf_mob_holder, "[reason] (reverted from [src] to [tf_mob_holder])")

/mob/living/proc/revert_mob_tf()
	if(!tf_mob_holder)
		return
	var/mob/living/ourmob = tf_mob_holder
	if(soulgem) //Should always be the case, but...Safety. Done here first
		soulgem.transfer_self(ourmob)
	if(ourmob.loc != src)
		if(isnull(ourmob.loc))
			to_chat(src,span_notice("You have no body."))
			tf_mob_holder = null
			return
		if(istype(ourmob.loc, /mob/living)) //Check for if body was transformed
			ourmob = ourmob.loc
		if(ourmob.ckey)
			if(ourmob.tf_mob_holder && ourmob.tf_mob_holder == src)
				//Body Swap
				var/datum/mind/ourmind = src.mind
				var/datum/mind/theirmind = ourmob.mind
				ourmob.ghostize()
				src.ghostize()
				ourmob.mind = null
				src.mind = null
				ourmind.current = null
				theirmind.current = null
				transfer_mind(ourmind, ourmob, "mob transform body swap with [src]", force = TRUE)
				transfer_mind(theirmind, src, "mob transform body swap with [ourmob]", force = TRUE)
				ourmob.tf_mob_holder = null
				src.tf_mob_holder = null
			else
				to_chat(src,span_notice("Your body appears to be in someone else's control."))
			return
		move_player(src, ourmob, "reverted mob transform from [src]")
		tf_mob_holder = null
		return
	new /obj/effect/effect/teleport_greyscale(src.loc)
	//legacy ai_holder.set_stance(STANCE_SLEEP) removed; brain auto-sleeps
	// when the mob's stat changes via its COMSIG_MOB_STATCHANGE handler.
	return_player_to_tf_holder("reverted mob transform")
	tf_mob_holder = null
	var/turf/get_dat_turf = get_turf(src)
	ourmob.forceMove(get_dat_turf)
	ourmob.forceMove(get_dat_turf)
	if(!tf_form_mind)
		ourmob.vore_selected = vore_selected
		vore_selected = null
		ourmob.mob_belly_transfer(src)

	om_run_frame_now(ourmob, /datum/om/pipeline/life)

	if(ishuman(src))
		for(var/obj/item/W in src)
			if(istype(W, /obj/item/implant/backup) || istype(W, /obj/item/nif))
				continue
			src.drop_from_inventory(W)

	if(tf_form == ourmob)
		if(tf_form_mind)
			transfer_mind(tf_form_mind, src, "returned to shapeshift form [src]", tf_form_holds_key)
			tf_form_mind = null
		ourmob.tf_form = src
		src.forceMove(ourmob)
	else
		qdel(src)

/datum/om/stage/life/tf_holder
	order = LIFE_PHASE_OUTPUT + 40
	name = "tf holder"
	run_if = LIFE_RUN_IF_PLACED

/// Continuous only for a transformed mob holding its original body.
/datum/om/stage/life/tf_holder/idle(mob/living/self)
	return !self.tf_mob_holder

/// Links life and death between a transformed mob and the body it holds.
/datum/om/stage/life/tf_holder/perform(mob/living/self, datum/om/frame/life/ctx)
	if(!self.tf_mob_holder)
		return
	if(self.tf_mob_holder.loc != self) return // Prevent bodyswapped creatures having their life linked
	if(self.stat != self.tf_mob_holder.stat)
		if(self.stat == DEAD)
			self.tf_mob_holder.death(FALSE, null)
		if(self.tf_mob_holder.stat == DEAD)
			self.death()

/mob/living/proc/copy_vore_prefs_to_mob(mob/living/new_mob)
	//For primarily copying vore preference settings from a carbon mob to a simplemob
	//It can be used for other things, but be advised, if you're using it to put a simplemob into a carbon mob, you're gonna be overriding a bunch of prefs

	new_mob.share_identity(identity) // the character's OOC notes, by reference
	new_mob.appendage_color = appendage_color
	new_mob.appendage_alt_setting = appendage_alt_setting

	VORE_PREF_TRANSFER(new_mob, src)

// Requires a /mob/living type path for transformation. Returns the new mob on success, null in all other cases.
// Just handles mob TF right now, but maybe we'll want to do something similar for items in the future.
/mob/living/proc/transform_into_mob(mob/living/new_form, pref_override = FALSE, revert = FALSE, shapeshifting = FALSE)
	if(!src.mind)
		return
	if(!src.allow_spontaneous_tf && !pref_override)
		return
	if(src.tf_mob_holder) //If we're already transformed
		if(revert)
			revert_mob_tf()
			return
		else
			return
	else
		if(src.stat == DEAD)
			return
		if(!ispath(new_form, /mob/living) && !ismob(new_form))
			return
		var/mob/living/new_mob
		if(shapeshifting && src.tf_form)
			new_mob = src.tf_form
			add_verb(new_mob,/mob/living/proc/shapeshift_form)
			new_mob.tf_form = src
			new_mob.forceMove(src.loc)
			visible_message(span_warning("[src] twists and contorts, shapeshifting into a different form!"))
			if(new_mob.ensure_mind())
				new_mob.tf_form_mind = new_mob.mind
				new_mob.tf_form_holds_key = new_mob.key == new_mob.mind.key
		else
			if(isliving(new_form))
				new_mob = new_form
			else
				new_mob = new new_form(get_turf(src))

		if(new_mob && isliving(new_mob))
			new_mob.faction = src.faction
			if(istype(new_mob, /mob/living/simple_mob))
				var/mob/living/simple_mob/S = new_mob
				if(!S.voremob_loaded)
					S.init_vore(TRUE)
			new /obj/effect/effect/teleport_greyscale(src.loc)
			if(!new_mob.ckey)
				transfer_mob_identity(new_mob)

			// The player wears the new form: the mind moves, the character's
			// identity is shared (not bound) so the form keeps its own body.
			var/datum/mind/form_mind = new_mob.tf_form_mind
			move_player(src, new_mob, "transformed into [new_mob]", share = TRUE)
			if(form_mind)
				transfer_mind(form_mind, src, "displaced from shapeshift form [new_mob] into [src]", new_mob.tf_form_holds_key)
			//legacy ai_holder state transfer between original and TF'd mob
			// no longer needed; modern brain spawns fresh on the new mob.
			forceMove(new_mob)
			src.forceMove(new_mob)
			new_mob.tf_mob_holder = src
			return new_mob

// Used to check if THIS MOB has been transformed into a different mob, as only the NEW mob uses tf_mob_holder.
// Necessary in niche cases where a proc interacts with the old body and needs to know it's been transformed (such as transforming into a mob then dying in virtual reality).
// Use this if you cannot use the tf_mob_holder var. Returns TRUE if transformed, FALSE if not.
/mob/living/proc/tfed_into_mob_check()
	if(loc && isliving(loc))
		var/mob/living/M = loc
		if(istype(M) && M.tf_mob_holder && (M.tf_mob_holder == src))
			return TRUE
		else
			return FALSE
	else
		return FALSE

/mob/living/proc/shapeshift_form()
	set name = "Shapeshift Form"
	set category = "Abilities.Shapeshift"
	set desc = "Shape shift between set mob forms. (Requires a spawned mob to be varedited into the user's tf_form var as mob reference.)"
	if(!istype(tf_form))
		to_chat(src, span_notice("No shapeshift form set. (Requires a spawned mob to be varedited into the user's tf_form var as mob reference.)"))
		return
	else
		transform_into_mob(tf_form, TRUE, TRUE, TRUE)

/mob/living/set_dir(new_dir)
	. = ..()
	if(size_multiplier != 1 || icon_scale_x != 1 && center_offset > 0)
		update_transform(TRUE)
