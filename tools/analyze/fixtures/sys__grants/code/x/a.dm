verbs += /mob/proc/x
verbs -= x
verbs |= x
verbs &= x
verbs ^= x
verbs = list()
if(verbs == x)
verbs.Add(x)
verbs . Remove(x)
verbs.Cut()
verbs.Copy()
verbs.Insert(1,x)
verbs[1] = x
verbs[1] == x
add_verb(src, x)
remove_verb (src, x)
new /mob/proc/foo(src)
new /obj/verb/bar(src, x)
new /obj/item(src)
x = "verbs += y"
x = "a\"b" + verbs += 1
// verbs += x
verbs += x // c
verbs += x // ALLOW(sys_verb_write): no effect
// ALLOW(sys_verb_write): none
verbs -= x
myverbs += x
x.verbs += y
