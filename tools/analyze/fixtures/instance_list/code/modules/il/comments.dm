/obj/c
	/*
	var/list/hidden1 = list()
	*/
	/* one line */
	var/list/seen1 = list()
	/* opens here and closes here */ var/list/seen2 = list()
	/* opens
	var/list/hidden2 = list()
	still inside */
	var/list/seen3 = list()
	/*
	// a line comment inside a block does not close it
	var/list/hidden3 = list() */ var/list/hidden4 = list()
	var/list/seen4 = list()
	// var/list/hidden5 = list()
	#define FOO var/list/hidden6 = list()
	var/list/seen5 = list() // ALLOW(instance_list): the fixture keeps this one on the line
	// ALLOW(instance_list): the fixture keeps the next one from the comment line above
	var/list/kept1 = list()
	var/list/seen6 = list() // ALLOW(instance_list)
	var/list/seen7 = list() // ALLOW(init): another lint's name keeps nothing here
	var/list/kept2 = list() // ALLOW(init, instance_list): two names on one annotation
	var/list/seen8 = list() // ALLOW(instance_list): ok
	/* ALLOW(instance_list): block form is not a comment-only line above, only the same line counts */
	var/list/seen9 = list()
	var/list/kept3 = list() /* ALLOW(instance_list): the block form keeps its own line */
	x // ALLOW(instance_list): a trailing annotation on code does not cover the next line
	var/list/seen10 = list()
	{ // a brace line
	var/list/seen11 = list()
