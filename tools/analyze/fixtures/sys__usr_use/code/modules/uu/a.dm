/mob/proc/plain()
	var/mob/M = usr
	to_chat(usr, "the usr word in text")
/mob/proc/ability()
	set name = "Ability"
	set category = "Abilities"
	var/mob/M = usr
/mob/verb/shout()
	to_chat(usr, "hi")
ADMIN_VERB(smite, R_FUN, "Smite", "x", y)
	log_admin("[key_name(usr)]")
/proc/helper(x)
	var/t = "usr"
	log_admin("[usr]")
#define WHO usr
	// usr is mentioned in a comment
	var/x = src.usr_count
	var/y = x.usr
	var/z = x:usr
	var/w = /obj/usr
	var/v = (usr)
	var/u = usr.client
	var/s = usr?.client
	var/r = usr_thing
	var/q = susr
	var/p = usr2
	to_chat(usr,"a")
	#define INNER usr
		#define DEEP usr
	/* usr in a block comment */
	var/o = "\[usr]"
	var/n = "text [usr] and [usr]"
	var/m = {"
	text block with usr
	[usr]
	"}
	var/l = @"usr"
	var/k = 'usr.ogg'
/proc/plain_head(a = usr)
	return 1
/mob/verb/verb_head(mob/m as mob in usr)
	return usr
/mob/proc/set_variants()
	set src in view(1)
	return usr
/mob/proc/set_desc()
	var/x = 1
	set desc = "A verb that sets its desc after a statement"
	return usr
/mob/proc/set_hidden()
	set hidden = 1
	return usr
/mob/proc/set_popup()
	set popup_menu = 0
	return usr
/mob/proc/set_instant()
	set instant = 1
	return usr
/mob/proc/set_background()
	set background = 1
	set waitfor = 0
	return usr
/mob/proc/set_spaces()
	set  name="extra spaces"
	return usr
/mob/proc/set_in_comment()
	// set name = "not a statement"
	return usr
/mob/proc/set_in_string()
	var/x = "set name = text"
	return usr
/mob/proc/set_namespace()
	set namespace = 1
	return usr
/mob/proc/verb/nested_verb_path()
	return usr
/mob/verbose/not_a_verb_path()
	return usr
/verb/global_verb()
	return usr
/mob/verbs/other()
	return usr
/mob/proc/multi(a,
	b)
	set name = "multi-line head"
	return usr
/mob/proc/multi_plain(a,
	b)
	return usr
/mob/proc/after_verbs()
	return usr
DECLARE_VERB(/mob, "Say", "IC", PROC_REF(say_x))
	var/x = usr

	var/y = usr
DECLARE_VERB_IF(/mob, "Say", "IC", PROC_REF(say_y), FALSE)
	var/z = usr
DECLARE_LOGIN_VERB(/mob, "Login", "IC", PROC_REF(say_z))
DECLARE_VERB_HIDE(/mob, x)
DECLARE_VERB_X(/mob, usr)
ADMIN_VERB_AND_CONTEXT_MENU(a, b, c, d, e)
	to_chat(usr, "ok")
ADMIN_VERB (spaced, b)
	to_chat(usr, "not a verb macro")
ADMIN_VERBS(a)
	to_chat(usr, "also matches the macro prefix")
DECLARE_VERBOSE(x)
	to_chat(usr, "DECLARE_\w*VERB\w* needs VERB then the paren after the word characters")
XDECLARE_VERB(x)
	to_chat(usr, "not at the start of the line")
var/global/at_top = usr
/mob/proc/trailing()
	return usr
