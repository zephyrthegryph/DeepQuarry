
/obj/item/blobcore_chunk
	name = "core chunk"
	desc = "The remains of some strange life-form. It smells awful."
	icon = 'icons/mob/blob.dmi'
	icon_state = "blobcore"
	flags = OPENCONTAINER
	var/datum/blob_type/blob_type	// The blob type this dropped from.

	var/active_ability_cooldown = 20 SECONDS
	COOLDOWN_DECLARE(active_use_cooldown)

	var/should_tick = TRUE	// Incase it's a toggle.

	var/passive_ability_cooldown = 5 SECONDS
	COOLDOWN_DECLARE(passive_use_cooldown)

	var/can_genesis = TRUE	// Can the core chunk be used to grow a new blob?

	drop_sound = SFX_EFFECTS_SLIME_SQUISH

CAPABILITIES(/obj/item/blobcore_chunk)
	reagents(120)
	owns_one(nameof(blob_type), /datum/blob_type)
	param(nameof(parent_blob_type), pos = 1, apply = PROC_REF(setup_blobtype), keep = FALSE)

/obj/item/blobcore_chunk/is_open_container()
	return 1


/// The blob type the chunk comes from (its constructor param, dropped once set up).
/obj/item/blobcore_chunk/var/tmp/datum/blob_type/parent_blob_type

/obj/item/blobcore_chunk/proc/setup_blobtype(datum/blob_type/parentblob = null)
	if(!parentblob)
		name = "inert [initial(name)]"

	else
		rel_set(src, nameof(blob_type), new parentblob.type)
		name = "[blob_type.name] [initial(name)]"

	if(blob_type)
		color = blob_type.color

		if(blob_type.chunk_active_type == BLOB_CHUNK_CONSTANT)
			should_tick = TRUE
		else if(blob_type.chunk_active_type == BLOB_CHUNK_TOGGLE)
			should_tick = FALSE

		active_ability_cooldown = blob_type.chunk_active_ability_cooldown
		passive_ability_cooldown = blob_type.chunk_passive_ability_cooldown

		blob_type.chunk_setup(src)

		om_task_periodic(src, PERIODIC_SLOW)

/obj/item/blobcore_chunk/proc/call_chunk_unique(datum/act/notice/A)
	SHOULD_NOT_SLEEP(TRUE)
	var/datum/source = A.target
	if(blob_type)
		blob_type.chunk_unique(src, list(source))
	return

/obj/item/blobcore_chunk/proc/get_carrier(atom/target)
	var/atom/A = target ? target.loc : src

	if(isturf(A) || isarea(A))	// Something has gone horribly wrong if the second is true.
		return FALSE	// No mob is carrying us.

	if(!isliving(A))
		A = get_carrier(A)

	return A

/obj/item/blobcore_chunk/blob_act(obj/structure/blob/B)
	if(B.overmind && !blob_type)
		setup_blobtype(B.overmind.blob_type)

	return

DECLARE_INTERACTIONS(/obj/item/blobcore_chunk, \
	INTERACT_USE(null, PROC_REF(interaction_self)), \
	INTERACT_ALT(null, PROC_REF(interaction_alt)), \
)

/// Old attack_self.
/obj/item/blobcore_chunk/proc/interaction_self(mob/user, obj/item/held, datum/interaction/interaction)
	if(blob_type && COOLDOWN_FINISHED(src, active_use_cooldown))
		COOLDOWN_START(src, active_use_cooldown, active_ability_cooldown)
		to_chat(user, span_alien("[icon2html(src, user.client)] \The [src] gesticulates."))
		blob_type.on_chunk_use(src, user)
	else
		to_chat(user, span_notice("\The [src] doesn't seem to respond."))
	return TRUE

/obj/item/blobcore_chunk/periodic_step()
	if(blob_type && should_tick && COOLDOWN_FINISHED(src, passive_use_cooldown))
		COOLDOWN_START(src, passive_use_cooldown, passive_ability_cooldown)
		blob_type.on_chunk_tick(src)

/// Old click_alt.
/obj/item/blobcore_chunk/proc/interaction_alt(mob/living/carbon/user, obj/item/held, datum/interaction/interaction)
	if(blob_type && blob_type.chunk_active_type == BLOB_CHUNK_TOGGLE)
		should_tick = !should_tick

		if(should_tick)
			to_chat(user, span_alien("\The [src] shudders with life."))
		else
			to_chat(user, span_alien("\The [src] stills, returning to a death-like state."))
	return TRUE

/obj/item/blobcore_chunk/proc/regen(newfaction = null)
	if(istype(blob_type))
		if(newfaction)
			blob_type.faction = newfaction

		var/obj/structure/blob/core/NC = new (get_turf(src))
		// The new overmind gets its own instance: this chunk keeps (and deletes) its own.
		var/datum/blob_type/copy = new blob_type.type
		copy.faction = blob_type.faction
		rel_set(NC.overmind, nameof(/mob/observer/blob::blob_type), copy)
		NC.overmind.blob_core().update_icon()
		return TRUE

	return FALSE

/datum/decl/chemical_reaction/instant/blob_reconstitution
	name = "Hostile Blob Revival"
	id = "blob_revival"
	result = null
	required_reagents = list(REAGENT_ID_PHORON = 60)
	result_amount = 1

/datum/decl/chemical_reaction/instant/blob_reconstitution/can_happen(datum/reagents/holder)
	if(holder.my_atom && istype(holder.my_atom, /obj/item/blobcore_chunk))
		return ..()
	return FALSE

/datum/decl/chemical_reaction/instant/blob_reconstitution/on_reaction(datum/reagents/holder)
	var/obj/item/blobcore_chunk/chunk = holder.my_atom
	if(chunk.can_genesis && chunk.regen())
		chunk.visible_message(span_notice("[chunk] bubbles, surrounding itself with a rapidly expanding mass of [chunk.blob_type.name]!"))
		chunk.can_genesis = FALSE
	else
		chunk.visible_message(span_warning("[chunk] shifts strangely, but falls still."))

/datum/decl/chemical_reaction/instant/blob_reconstitution/domination
	name = "Allied Blob Revival"
	id = "blob_friend"
	result = null
	required_reagents = list(REAGENT_ID_HYDROPHORON = 40, REAGENT_ID_PERIDAXON = 20, REAGENT_ID_MUTAGEN = 20)
	result_amount = 1

/datum/decl/chemical_reaction/instant/blob_reconstitution/domination/on_reaction(datum/reagents/holder)
	var/obj/item/blobcore_chunk/chunk = holder.my_atom
	if(chunk.can_genesis && chunk.regen("neutral"))
		chunk.visible_message(span_notice("[chunk] bubbles, surrounding itself with a rapidly expanding mass of [chunk.blob_type.name]!"))
		chunk.can_genesis = FALSE
	else
		chunk.visible_message(span_warning("[chunk] shifts strangely, but falls still."))

// The chunk owns its own blob type instance (the overmind's is deleted with the overmind).
