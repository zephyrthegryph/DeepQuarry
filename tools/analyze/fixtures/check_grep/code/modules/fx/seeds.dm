/proc/seed_user()
	var/x = 1
	x = init_alpha
	init_alpha = 5
	init_beta
	foo(init_beta)
	// init_alpha in a comment
	/* init_alpha here */
	 * init_beta star line
	init_alphabet = 3
	x = init_alpha // ALLOW(check_grep): reason
	x = init_alpha // ALLOW(check_grep)
