/mob/verb/a()
	set category = VERB_CAT_ADMIN
/mob/verb/b()
	set category = "Raw.One"
/mob/verb/c()
	set  category  =  "Raw.Two"
/mob/verb/d()
	set category = "Raw.Three" // ALLOW(verb_category): legacy
/mob/verb/e()
	// ALLOW(verb_category): above
	set category = "Raw.Four"
/mob/verb/f()
	// set category = "Raw.Comment"
	var/s = "set category = \"Raw.String\""
	set name = "category"
ADMIN_VERB(x, R_ADMIN, "X", "Desc", "Admin.Game")
ADMIN_VERB(y, R_ADMIN, "Y", "Desc", ADMIN_CATEGORY_GAME)
ADMIN_VERB(z, R_ADMIN, "Z", "Desc, with comma", "Admin.Game2")
DEBUG_VERB(w, R_DEBUG, "W", "Desc", "Debug.Thing")
ADMIN_VERB_AND_CONTEXT_MENU(v, R_ADMIN, "V", "Desc", "Admin.Menu", x)
ADMIN_VERB_AND_CONTEXT_MENU(u, R_ADMIN, "V", "Desc", VERB_CAT_ADMIN, x)
#define MY_ADMIN_VERB(a) ADMIN_VERB(a, R_ADMIN, "A", "D", "Raw.Macro")
#define PLAIN_DEFINE set category = "Raw.Define"
	#define INDENTED_DEFINE set category = "Raw.Indented"
ADMIN_VERB(t, R_ADMIN, "T", "Desc", "Admin.A", extra) // ALLOW(verb_category): keep
/mob/verb/g()
	var/icon/I = 'unbalanced.dmi
	set category = "Raw.After.Quote"
/mob/verb/h()
	set category = "Raw.Five"
