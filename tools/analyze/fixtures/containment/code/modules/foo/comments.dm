/mob/c
/*
	loc = T
	X.contents += A
*/
	loc = T
	var/x = {"
		loc = T
	"}
	loc = T
	/* loc = T */ loc = U
	loc = T /* loc = U */
	var/y = "unterminated loc = T
	loc = T
	var/i = 'icons/foo.dmi'
	X.contents += A
