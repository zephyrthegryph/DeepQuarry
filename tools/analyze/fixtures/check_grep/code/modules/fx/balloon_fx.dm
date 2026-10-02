/proc/balloon_fx(user)
	balloon_alert("text")
	balloon_alert(user, "<span>x</span>")
	balloon_alert(user, "SPAN")
	balloon_alert(user, "Hello")
	balloon_alert(user, " leading space")
	balloon_alert(user, "ok")
	balloon_alert(user, UNLINT("AI"))
	balloon_alert(user, "Capital") // ALLOW(check_grep): ok
