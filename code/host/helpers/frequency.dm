//Ensure the frequency is within bounds of what it should be sending/recieving at
/proc/sanitize_frequency(f, low = PUBLIC_LOW_FREQ, high = PUBLIC_HIGH_FREQ)
	f = round(f)
	f = max(low, f)
	f = min(high, f)
	if ((f % 2) == 0) //Ensure the last digit is an odd number
		f += 1
	return f

//Turns 1479 into 147.9
/proc/format_frequency(f)
	return "[round(f / 10)].[f % 10]"

//Opposite of format, returns as a number
/proc/unformat_frequency(frequency)
	frequency = text2num(frequency)
	return frequency * 10
