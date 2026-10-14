#ifdef MISSING
var/conditional = 1
#endif
#define LOCAL EXTERNAL
var/result = LOCAL
#undef EXTERNAL
#ifdef EXTERNAL
var/unexpected = 1
#endif
