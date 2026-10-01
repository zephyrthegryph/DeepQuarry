/datum/literal_format_unicode
 var/a="Ａ"
 var/two="２"
 var/prefix="～"
 var/raw=@"Ａ２～"
 var/unicode="\uFF21\uFF12\uFF5E"
 var/ellipsis="\..."
 var/concat="Ａ"+"２"
 var/hash_ascii=md5("abc")
 var/hash_unicode=md5("Ａ２～")
 var/hash_concat=md5("Ａ"+"２～")
 var/hash_escape=md5("\uFF21\uFF12\uFF5E")

/proc/literal_return()
 return "Ａ２～"
/proc/literal_raw()
 return @"Ａ２～"
/proc/literal_unicode()
 return "\uFF21\uFF12\uFF5E"
/proc/literal_length()
 return length("Ａ２～")
/proc/literal_copytext()
 return copytext("Ａ２～",1,4)
/proc/literal_md5(value="Ａ２～")
 return md5(value)
/proc/literal_json()
 return json_encode("Ａ２～")
/proc/literal_interpolation(X)
 return "Ａ[X]２\Roman [X]～\..."

/proc/literal_equal()
 return "Ａ"=="\uFF21"


/proc/literal_initial_hash(datum/literal_format_unicode/O)
 return initial(O.hash_unicode)

