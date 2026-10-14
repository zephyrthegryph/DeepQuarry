/datum/a
	var/static/list/foo_cache = list()
	var/static/list/FooCache
	var/static/list/typecache_foo = typecacheof(list())
	var/static/list/my_TypeCache = list()
	var/static/list/cached = list()
	var/static/list/foo = list()
	var/static/list/foo_c_ache
	var/static/list/cache
	var/static/list/ cache
	var/static/list/a = list() // foo_cache
	var/list/static/foo_cache
	var/static/list/Cache
	var/static/lists/foo_cache
	xvar/static/list/foo_cache
	var/static/list/foo_cache // trailing comment
	var/static/list/foo = "a_cache" // in a string, before the comment: not a name position
	var/s = "var/static/list/foo_cache"
GLOBAL_LIST_EMPTY(foo_cache)
GLOBAL_LIST_INIT(foo_cache, list())
GLOBAL_LIST_EMPTY_TYPED(foo_cache, /datum)
GLOBAL_LIST_INIT_TYPED(foo_cache, /datum, list())
GLOBAL_LIST_EMPTY( foo_cache)
GLOBAL_LIST_EMPTY(typecache_x)
GLOBAL_LIST_INIT(typecache_x, typecacheof(list()))
GLOBAL_LIST(foo_cache)
GLOBAL_LIST_EMPTY (foo_cache)
global_list_empty(foo_cache)
GLOBAL_LIST_EMPTY(foo)
GLOBAL_LIST_EMPTY(cache)
GLOBAL_LIST_EMPTY(foo_cache) // trailing comment
var/list/foo_cache
var/global/list/foo_cache
	var/global/list/foo_cache
	var/list/indented_cache
 var/list/one_space_cache
var/global/list/typecache_foo
	var/global/list/typecache_foo
var/list/typecache_foo
var/static/list/typecache_a = list() ; var/static/list/b_cache
var/static/list/b_cache; var/static/list/typecache_a
var/list/a_cache // ALLOW(cache): a keyed cache with its own invalidation lives here
// ALLOW(cache): a keyed cache with its own invalidation lives here
var/list/b_cache
	// ALLOW(cache): a keyed cache with its own invalidation lives here
	var/list/c_cache
var/list/d_cache // ALLOW(cache)
var/list/e_cache // ALLOW(other): a reason for some other lint entirely
var/list/f_cache // ALLOW(other, cache): a reason that names two lints at once
x = 1 // ALLOW(cache): not a comment-only line so it keeps nothing below
var/list/g_cache
/* ALLOW(cache): block form of the annotation */ var/static/list/h_cache
/* var/static/list/block_cache */
/*
	var/static/list/inside_cache
*/
var/static/list/i_cache = list() // var/static/list/typecache_ignored
var/static/list/j_cache; /* var/static/list/typecache_ignored */
	var/list/not_cache_at_the_start
var/list/cache_first
var/list/CACHE
var/list/x_CACHE_y
var//list/foo_cache
var/list/typecache
var/list/Typecache
var/list/atypecachea
var/list/cache_of_typecaches
