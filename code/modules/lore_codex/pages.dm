// Contains the 'raw' lore data.
/datum/lore/codex
	var/name = null // Title displayed
	var/data = null // The actual words.
	var/tmp/datum/lore/codex/parent	// Category above us
	// ALLOW(instance_list): d: codex page keywords, filled at init
	var/list/keywords = list() // Used for searching.
	var/tmp/datum/codex_tree/holder

/datum/lore/codex/New(new_holder, new_parent)
	..()
	rel_set(src, nameof(holder), new_holder)
	rel_set(src, nameof(parent), new_parent)
	add_content()
	if(name)
		keywords.Add(name)

// Page links (quick links) are handled by the codex they belong to.
/datum/lore/codex/topic_forward()
	return holder()

/datum/lore/codex/page

// Returns an assoc list of keywords binded to a ref of this page.  If it's a category, it will also recursively call this on its children.
/datum/lore/codex/proc/index_page()
	var/list/results = list()
	for(var/keyword in keywords)
		results[keyword] = src
	return results

// This gets called in New(), which is helpful for inserting quick_link()s.
/datum/lore/codex/proc/add_content()
	return

// Use this to quickly link to a different page
/datum/lore/codex/proc/quick_link(target, word_to_display)
	if(isnull(word_to_display))
		word_to_display = target
	return "<a href='byond://?src=\ref[src];quick_link=[target]'>[word_to_display]</a>"

// Can only be found by specifically searching for it.
/datum/lore/codex/page/ultimate_answer
	name = "Answer to the Ultimate Question of Life, the Universe, and Everything"
	data = "42"
	keywords = list("Ultimate Question", "Ultimate Question of Life, the Universe, and Everything", "Life, the Universe, and Everything", "Everything", "42")

// Organizes pages together.
/datum/lore/codex/category
	/// The types of the pages or categories relevant to this category (New() builds child_pages from it).
	// ALLOW(instance_list): d: a per-subtype type table, set in the type definitions
	var/list/children = list()
	/// Our pages and sub-categories (owned), built from `children` in New().
	var/list/child_pages

/datum/lore/codex/category/New()
	..()
	for(var/type in children)
		own_add(src, nameof(child_pages), new type(holder(), src))

/datum/lore/codex/category/index_page()
	// First, get our own keywords.
	var/list/results = ..()
	// Now get our children.  If a child is also a category, it will get their children too.
	for(var/datum/lore/codex/child in child_pages)
		results += child.index_page()
	return results

/// Category above us (a relation view: null once that is deleted).
/datum/lore/codex/proc/parent() as /datum/lore/codex
	return parent

/// The holder this refers to (a relation view: null once that is deleted).
/datum/lore/codex/proc/holder() as /datum/codex_tree
	return holder
