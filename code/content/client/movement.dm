
/client/New()
	..()
	dir = NORTH

/client/verb/spinleft()
	set name = "Spin View CCW"
	set hidden = TRUE
	dir = turn(dir, 90)

/client/verb/spinright()
	set name = "Spin View CW"
	set hidden = TRUE
	dir = turn(dir, -90)
