/proc/html_fx()
	to_chat(x, "<span class='x>bad")
	to_chat(x, "<span class="a">good")
	to_chat(x, "<span class='a'>good")
	to_chat(x, "< span class = 'a'  >good")
	to_chat(x, "<span class=x'>bad")
	to_chat(x, "<span class='y>bad") // ALLOW(check_grep): ok
	x = "href='?src=1'"
	y = "href=\"?src\""
	z = "href = ?x"
	w = "<a href='byond://?src'>"
	v = "href=1"
