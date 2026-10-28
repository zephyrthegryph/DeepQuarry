/proc/first(x, y)
	return !x & y

/proc/parenthesized(x, y)
	return (!x) & y

/proc/right_negation(x, y)
	return x | !y
