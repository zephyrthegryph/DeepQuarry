/proc/call_ext_fx()
	call_ext("lib", "fn")()
	load_ext("x")
	var/x = VERDIGRIS_CALL
	// call_ext in a comment
	* call_ext doc line
	foo() // call_ext here
	call_ext("a") // ALLOW(check_grep): needed
	call_ext("b") // ALLOW(check_grep)
	call_ext("c") // ALLOW(other, check_grep): both names
	http_x = "http://call_ext"
