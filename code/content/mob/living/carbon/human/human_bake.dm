// Off-thread baking of the human look's /icon work (human_look.dm): a picture the client cannot compose from tinted overlays (a wound's pixels
// masked to its limb, an animated tail frame split by facing) is composed by rust-g iconforge on a worker thread, once per key, and kept.
//
// The draw asks human_baked(look, key, builder, args): a baked picture is returned at once (an icon resource, read as image(icon = res, icon_state =
// HUMAN_BAKE_STATE)); otherwise the request is queued (as an effect of the look, once it is applied) and the draw shows what it can without it (the part is left out) until the picture lands, when
// every human that asked is redrawn. A bake that fails is remembered, and its asker falls back to the synchronous /icon build it replaced, so a look
// is never wrong, only late. Nothing here runs an /icon operation in a draw: the sprite description (a few lists and a JSON encode) is made in a
// kernel job step, the composition by iconforge, the file read by fcopy_rsc().
//
// Counters (human_bake_stats_line(), appended to human_look_stats_line()): bakes asked, started, landed, failed and waiting.

/// The directory iconforge writes baked pictures to; each file is read into the resource cache and kept until its picture is dropped.
#define HUMAN_BAKE_DIR "tmp/dq_human_bakes/"
/// The one state of a baked picture's DMI.
#define HUMAN_BAKE_STATE "bake"
/// Bakes iconforge runs at once.
#define HUMAN_BAKE_INFLIGHT_MAX 4
/// Baked pictures kept (oldest dropped first: an image already using one keeps it).
#define HUMAN_BAKE_KEPT 2048
/// Pictures dropped (file deleted, entry cut) by one landing while the cache is over HUMAN_BAKE_KEPT.
#define HUMAN_BAKE_DROP_PER_LANDING 8
/// What human_baked() answers for a bake that failed: the asker builds the picture the old way.
#define HUMAN_BAKE_FAILED "failed"

GLOBAL_DATUM_INIT(human_baker, /datum/human_baker, new)

CAPABILITIES_PART(/datum/controller/global_vars, human_baker)
	owns_one(nameof(human_baker), /datum/human_baker)

LIFECYCLE_KEEP_UNLESS_FORCED(/datum/human_baker)

/// The human look's bakes: one per world; a running bake outlives whatever asked for it.
/datum/human_baker
	/// Key -> the picture's icon resource (a DMI with one state, HUMAN_BAKE_STATE), or HUMAN_BAKE_FAILED.
	var/list/baked = list()
	/// Keys queued or baking -> list(builder name, builder args) while queued, TRUE once started.
	var/list/pending = list()
	/// Key -> handles of the humans waiting for it (redrawn when it lands).
	var/list/waiters = list()
	/// Facing sets -> the facing mask's disk path (human_dirs_mask()).
	var/list/masks = list()
	var/inflight = 0
	var/asked = 0
	var/started = 0
	var/landed = 0
	var/failed = 0
	var/mask_builds = 0
	/// TRUE while the pump job runs (it starts the queued bakes a step at a time).
	var/pumping = FALSE

/// Bakes that landed for this human's looks: the draw reads it, so a landing draws the human again (human_look.dm).
/mob/living/carbon/human
	var/bake_landed = 0

/// The picture baked for `key`: its icon resource, HUMAN_BAKE_FAILED, or null (not baked yet). A read only: asking is human_bake_ask().
/proc/human_bake_get(key)
	return GLOB.human_baker.baked[key]

/// The picture baked for `key`, asked for when it is not there: a draw passes its `look`, so the request is made once the look is applied, outside the draw;
/// `builder` is a proc of this human that takes `builder_args` and returns the iconforge sprite (it runs in a job step, never here).
/mob/living/carbon/human/proc/human_baked(datum/look/look, key, builder, list/builder_args)
	var/got = human_bake_get(key)
	if(got)
		return got
	if(look)
		look.effect(PROC_REF(human_bake_ask), key, builder, builder_args)
	else
		human_bake_ask(key, builder, builder_args)
	return null

/// Queues the bake of `key` (once, however many ask) and remembers this human to be drawn again when it lands.
/mob/living/carbon/human/proc/human_bake_ask(key, builder, list/builder_args)
	var/datum/human_baker/B = GLOB.human_baker
	if(B.baked[key])
		return
	var/handle = handle_of(src)
	var/list/who = B.waiters[key]
	if(!who)
		who = list()
		B.set_waiters_at(key, who)
	if(handle && !(handle in who))
		who += handle
	if(!B.pending[key])
		B.set_asked(B.asked + 1)
		B.set_pending_at(key, list(handle, builder, builder_args))
		B.wake()

/// Keeps the pump job running while there is something to start.
/datum/human_baker/proc/wake()
	if(pumping || !next_queued())
		return
	set_pumping(TRUE)
	job(src, TYPE_PROC_REF(/datum/human_baker, pump_step), budget = 20)

/// One job step: starts one queued bake (the sprite description, then iconforge).
/datum/human_baker/proc/pump_step(datum/act/timer/A)
	var/key = next_queued()
	if(!key || inflight >= HUMAN_BAKE_INFLIGHT_MAX)
		set_pumping(FALSE)
		return JOB_DONE
	var/list/request = pending[key]
	set_pending_at(key, TRUE)
	var/mob/living/carbon/human/asker = handle_get(request[1])
	var/list/sprite
	if(asker && !QDELETED(asker))
		sprite = call(asker, request[2])(arglist(request[3]))
	if(!sprite)
		finish(key, null, "no sprite (the asker is gone or its builder gave none)")
		return pump_next()
	var/sheet = "hb_[md5(key)]"
	human_bake_dir_ready()
	var/job_id = rustg_iconforge_generate_async(HUMAN_BAKE_DIR, sheet, json_encode(list(HUMAN_BAKE_STATE = sprite)), FALSE, TRUE, FALSE)
	inflight++
	started++
	io_job(null, /datum/io_backend/rustg_job, job_id, GLOBAL_PROC_REF(human_bake_job_done), key, sheet)
	return pump_next()

/// The key of the oldest bake still waiting for a start (its pending entry is still the request), or null.
/datum/human_baker/proc/next_queued()
	for(var/key in pending)
		if(islist(pending[key]))
			return key
	return null

/// The pump goes on while bakes are queued.
/datum/human_baker/proc/pump_next()
	if(next_queued())
		return JOB_MORE
	set_pumping(FALSE)
	return JOB_DONE

/// A bake is over: `path` is its DMI, or null (it failed, `why`).
/datum/human_baker/proc/finish(key, path, why)
	remove_pending(key)
	var/res
	if(path)
		res = fcopy_rsc(file(path)) // the file stays: a resource remembers its path, and a flat picture of the human (getFlatIcon) reads the DMI from it
		landed++
	else
		res = HUMAN_BAKE_FAILED
		failed++
		log_world("human bake: [key] failed: [why]; it is built the old way")
	set_baked_at(key, res)
	if(length(baked) > HUMAN_BAKE_KEPT)
		// A few pictures a landing, oldest first: dropping a quarter of the cache at once was hundreds of file deletes inside one I/O delivery.
		for(var/i in 1 to HUMAN_BAKE_DROP_PER_LANDING)
			var/dropped = baked[baked[i]]
			if(dropped != HUMAN_BAKE_FAILED)
				fdel("[dropped]")
		cut_baked(1, HUMAN_BAKE_DROP_PER_LANDING + 1)
	var/list/who = waiters[key]
	remove_waiters(key)
	for(var/handle in who)
		var/mob/living/carbon/human/H = handle_get(handle)
		if(H && !QDELETED(H))
			H.set_bake_landed(H.bake_landed + 1)

/proc/human_bake_dir_ready()
	var/static/made = FALSE
	if(!made)
		rustg_file_write("", "[HUMAN_BAKE_DIR].keep")
		made = TRUE

/// io_job() callback: a bake finished.
/proc/human_bake_job_done(result, error, key, sheet)
	var/datum/human_baker/B = GLOB.human_baker
	B.inflight--
	var/path = error ? null : human_bake_path(sheet, result)
	B.finish(key, path, error || result)
	B.wake()

/// The DMI a bake's output names, or null.
/proc/human_bake_path(sheet, output)
	if(!output || !findtext(output, "{", 1, 2))
		log_world("human bake: iconforge gave no result for [sheet]: [output]")
		return null
	var/list/data = json_decode(output)
	var/list/sprite_data = data["sprites"]?[HUMAN_BAKE_STATE]
	if(length(data["error"]) || !sprite_data)
		log_world("human bake: iconforge reported [json_encode(data["error"])] for [sheet]: [output]")
		return null
	var/path = "[HUMAN_BAKE_DIR][sheet]_[sprite_data["size_id"]].dmi"
	return rustg_file_exists(path) ? path : null

/// (Tests only: it blocks.) Bakes `sprite` on the spot and returns the DMI's path (the caller deletes it), or null.
/proc/human_bake_blocking(list/sprite, sheet)
	human_bake_dir_ready()
	return human_bake_path(sheet, rustg_iconforge_generate(HUMAN_BAKE_DIR, sheet, json_encode(list(HUMAN_BAKE_STATE = sprite)), FALSE, TRUE, FALSE))

/// The facing mask for `dirs` of `state` of `file`: as many facings and frames as the state (iconforge blends only states of equal frame counts), opaque
/// white in the facings kept and clear in the others, as an on-disk DMI. Made once per state and set of facings, in the bake's job step. Returns its path.
/proc/human_dirs_mask(list/dirs, file, state)
	var/datum/human_baker/B = GLOB.human_baker
	var/mask_key = "[file]|[state]|[jointext(dirs, ",")]"
	var/path = B.masks[mask_key]
	if(path && rustg_file_exists(path))
		return path
	B.mask_builds++
	var/icon/mask = icon(file, state)
	var/icon/clear = icon(file, state)
	mask.MapColors(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 1,1,1,1)
	clear.MapColors(0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0)
	for(var/facing in GLOB.cardinal - dirs)
		mask.Insert(icon(clear, dir = facing), dir = facing)
	human_bake_dir_ready()
	path = "[HUMAN_BAKE_DIR]mask_[md5(mask_key)].dmi"
	if(!fcopy(fcopy_rsc(mask), path))
		return null
	B.masks[mask_key] = path
	return path

/// "human bake: ..." for human_look_stats_line().
/proc/human_bake_stats_line()
	var/datum/human_baker/B = GLOB.human_baker
	return "bakes: [B.asked] asked, [B.started] started, [B.landed] landed, [B.failed] failed, [length(B.pending)] waiting, [B.mask_builds] masks"

// ---- the wounds ----

/// The iconforge sprite of one limb's wound picture: the species' damage icon in `part`'s state ("<damage state>/<limb icon name>"), masked to the limb's
/// pixels (the limb's state of the mask sheet) and tinted with the species' blood colour. Every facing (the damage and mask sheets are 4-facing).
/mob/living/carbon/human/proc/damage_sprite(overlay_file, mask_file, blood_colour, part)
	var/list/bits = splittext(part, "/")
	return list(
		"icon_file" = resolve_icon_dmi_path(overlay_file),
		"icon_state" = bits[1],
		"dir" = null,
		"frame" = null,
		"transform" = list(
			list("type" = RUSTG_ICONFORGE_BLEND_ICON, "icon" = list("icon_file" = resolve_icon_dmi_path(mask_file), "icon_state" = bits[2], "dir" = null, "frame" = null, "transform" = list()), "blend_mode" = ICON_MULTIPLY),
			list("type" = RUSTG_ICONFORGE_BLEND_COLOR, "color" = blood_colour, "blend_mode" = ICON_MULTIPLY),
		),
	)

// ---- the animated tails ----

/// The iconforge sprite of `state` of `file` with only `dirs` facings drawn: every frame and facing of the state, multiplied by a facing mask (opaque in the
/// facings kept), so the others are blank and the animation stays. The same picture icon_keep_dirs() makes.
/mob/living/carbon/human/proc/tail_dirs_sprite(file, state, list/dirs)
	var/mask = human_dirs_mask(dirs, file, state)
	if(!mask)
		return null
	return list(
		"icon_file" = resolve_icon_dmi_path(file),
		"icon_state" = state,
		"dir" = null,
		"frame" = null,
		"transform" = list(
			list("type" = RUSTG_ICONFORGE_BLEND_ICON, "icon" = list("icon_file" = mask, "icon_state" = "", "dir" = null, "frame" = null, "transform" = list()), "blend_mode" = ICON_MULTIPLY),
		),
	)
