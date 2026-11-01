//general stuff
/proc/sanitize_integer(number, min=0, max=1, default=0)
	if(isnum(number))
		var/rounded = round(number)
		if(min <= rounded && rounded <= max)
			return rounded
	return isnull(default) ? null : default * 1 // every caller's default is a number or none (a literal, initial() of a number var, a weight): said in arithmetic so the result is plainly a number

/proc/sanitize_float(number, min=0, max=1, accuracy=1, default=0)
	if(isnum(number))
		var/rounded = round(number, accuracy)
		if(round(min, accuracy) <= rounded && rounded <= round(max, accuracy))
			return rounded
	return default

// Checks if the given input is a valid list index; returns true/false and doesn't change anything.
/proc/sanitize_text(text, default="")
	if(istext(text))
		return "[text]" // the same text, spelled so the result is plainly text
	return isnull(default) ? null : "[default]" // the default is text (or none)

/proc/sanitize_inlist(value, list/List, default)
	if(value in List)	return value
	if(default)			return default
	if(List && List.len)return List[1]



//more specialised stuff
/proc/sanitize_hexcolor(color, default="#000000")
	if(!istext(color)) return text_or_null(default)
	var/len = length(color)
	if(len != 7 && len !=4) return text_or_null(default)
	if(text2ascii(color,1) != 35) return text_or_null(default)	//35 is the ascii code for "#"
	. = "#"
	for(var/i=2,i<=len,i++)
		var/ascii = text2ascii(color,i)
		switch(ascii)
			if(48 to 57)	. += ascii2text(ascii)		//numbers 0 to 9
			if(97 to 102)	. += ascii2text(ascii)		//letters a to f
			if(65 to 70)	. += ascii2text(ascii+32)	//letters A to F - translates to lowercase
			else			return text_or_null(default)
	return .

//Valid format codes: YY, YEAR, MM, DD, hh, mm, ss, :, -. " " (space). Invalid format will return default.
//Internal proc, expects valid format and text input of equal length to format.
/// `value` as text, or null when it is none. For a value whose contract is text (a text preference's, a prompt's text answer): the same
/// text comes back, and the result is plainly text.
/proc/text_or_null(value)
	return isnull(value) ? null : "[value]"

/// `value` as a number, or null when it is none. For a value whose contract is a number (a toggle, a numeric preference's): the same
/// number comes back, and the result is plainly a number.
/proc/num_or_null(value)
	return isnull(value) ? null : value * 1
