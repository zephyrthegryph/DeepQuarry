/obj/item/thing
	var/hitsound = 'sound/weapons/punch1.ogg'
	var/list/apply_sounds = list('sound/a.ogg', 'sound/b.ogg')
	var/open_sound = 'sound/open.wav'
	var/unfed_sound = 'sound/unfed.ogg'
	var/string_sound = "punch"
	var/fed_set_sound = "sparks"
	var/other_key = "punch"
	var/ok_sound = SFX_PUNCH

/obj/item/thing/proc/use(mob/user)
	playsound(src, hitsound, 50, 1)
	playsound(src, pick(apply_sounds), 50)
	playsound(src, open_sound, 50)
	playsound(src, 'sound/direct.ogg', 50)
	playsound(src, pick('sound/a.ogg', 'sound/b.ogg'), 50)
	playsound_local(user, 'sound/local.mid', 50)
	playsound(src, prob(50) ? 'sound/x.mp3' : 'sound/y.ogg', 50)
	playsound(src, SFX_PUNCH, 50)
	playsound(src, "punch", 50)
	playsound(src, "not a key", 50)
	playsound(src, "sparks")
	playsound(user, string_sound, 50)
	playsound(src, fed_set_sound)
	play_sfx(src, "sparks")
	play_sfx(src, SFX_SPARKS)
	play_sfx(src, ok_sound)
	var/s = get_sfx("punch")
	var/s2 = get_sfx(pick(apply_sounds))
	var/s3 = get_sfx("body_fall")
	// playsound(src, 'sound/commented.ogg', 50)
	playsound(src, SFX_PUNCH, 50) // 'sound/trailing.ogg'
	to_chat(user, "playsound(src, 'sound/in_string.ogg')")
	playsound(src, mob.some_member, 50)
	playsound(src, GLOB.emote_sound, 50)
	playsound(src, pick(GLOB.emote_sound2), 50)
	xplaysound(src, 'sound/not_a_call.ogg', 50)
	user.playsound(src, 'sound/member.ogg', 50)
	/playsound(src, 'sound/slash.ogg', 50)
	playsound(src, SFX_PUNCH, 50, extrarange = 'sound/arg.ogg')

/obj/item/thing/proc/multi(mob/user)
	playsound(src,
		'sound/multi.ogg',
		50)
	playsound(src, hitsound,
		50)
	playsound(src, SFX_PUNCH,
		50, 'sound/after_name.ogg')
	var/list/L = list(
		'sound/l1.ogg',
		'sound/l2.ogg')
	apply_sounds = list(
		'sound/m1.ogg')
	hitsound = pick(
		'sound/p1.ogg',
		'sound/p2.ogg')
	hitsound = \
		'sound/continued.ogg'
	open_sound = SFX_PUNCH
	open_sound = 'sound/ok.ogg' // ALLOW(sys_literal_sound_var): legacy

GLOBAL_LIST_INIT(emote_sound, list('sound/e1.ogg', 'sound/e2.ogg'))
GLOBAL_LIST_INIT(emote_sound2, list(
	'sound/f1.ogg',
	'sound/f2.ogg'))
GLOBAL_LIST_INIT(unfed_list, list('sound/u1.ogg'))
GLOBAL_LIST_INIT(emote_names, list("sparks", "punch"))
#define HIT_SOUND 'sound/define.ogg'
#define HIT_SOUND2 hitsound = 'sound/define2.ogg'

/obj/item/thing/proc/sparks()
	var/datum/effect/effect/system/spark_spread/s = new /datum/effect/effect/system/spark_spread
	s.set_up(5, 1, src)
	s.start()
	spark_spreader = 1
	// spark_spread in a comment
	to_chat(user, "spark_spread in a string")
	var/x = spark_spread_count

/obj/item/thing/proc/more_vars()
	var/hitsound = 'sound/local_var.ogg'
	hitsound = "punch"
	hitsound ==  'sound/cmp.ogg'
	hitsound != 'sound/cmp2.ogg'
	hitsound <= 'sound/cmp3.ogg'
	hitsound >= 'sound/cmp4.ogg'
	hitsound = other_thing = 'sound/chained.ogg'
	src.hitsound = 'sound/member_assign.ogg'
	var/path/typed/hitsound = 'sound/typed.ogg'
	mob.hitsound = 'sound/dotted.ogg'
	fn(a, hitsound = 'sound/kwarg.ogg')
	x = list('sound/not_fed.ogg')
	hitsound = list('sound/list_call.ogg')
	hitsound = pick('sound/pick_call.ogg')
	hitsound = pick ( 'sound/pick_spaced.ogg')
	hitsound=list ('sound/list_spaced.ogg')
	string_sound = pick("sparks", "punch")
	string_sound = "sparks"
	string_sound = "Sparks"
	string_sound = "unknown_key"
	fed_set_sound =  "body_fall"
	other_key = "body_fall"

/obj/item/thing/proc/allowed()
	playsound(src, 'sound/allowed.ogg', 50) // ALLOW(sys_literal_playsound): migration
	// ALLOW(sys_literal_playsound): migration above
	playsound(src, 'sound/allowed2.ogg', 50)
	playsound(src, "punch", 50) // ALLOW(sys_sfx_string_key): bare key
	new /datum/effect/effect/system/spark_spread // ALLOW(sys_spark_triple): legacy
	// ALLOW(sys_spark_triple): legacy above
	var/datum/effect/effect/system/spark_spread/s

/obj/item/thing/proc/two_calls()
	playsound(src, 'sound/one.ogg', 50); playsound(src, 'sound/two.ogg', 50)
	playsound(src, SFX_PUNCH); playsound(src, 'sound/second_only.ogg')

/obj/item/thing/proc/runs_off(mob/user)
	playsound(src, SFX_PUNCH, 50
	'sound/runs_off.ogg'
	var/x = 1
