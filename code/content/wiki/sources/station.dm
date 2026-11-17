// The wiki's station source: the departments and their jobs (from the job system's department and job datums), the station's operating
// manuals (the /obj/item/book/manual texts, filed by GLOB.wiki_manual_sections) and the setting's lore (the Traveler's Guide codex tree:
// locations, species, organisations, governments, militaries, political factions). Nothing here is written out: it is the game's own text,
// converted from HTML to wiki markup once (wiki_html_markup()).

/proc/wiki_dept_id(name)
	return "dept/[ckey(name)]"

/proc/wiki_job_id(title)
	return "job/[ckey(title)]"

/// Manual type -> the section it is filed in. A manual not listed is filed under Civilian/Manuals.
GLOBAL_LIST_INIT(wiki_manual_sections, list(
	/obj/item/book/manual/engineering_particle_accelerator = "Engineering/Manuals",
	/obj/item/book/manual/supermatter_engine = "Engineering/Manuals",
	/obj/item/book/manual/tesla_engine = "Engineering/Manuals",
	/obj/item/book/manual/engineering_singularity_safety = "Engineering/Manuals",
	/obj/item/book/manual/atmospipes = "Engineering/Manuals",
	/obj/item/book/manual/evaguide = "Engineering/Manuals",
	/obj/item/book/manual/rotary_electric_generator = "Engineering/Manuals",
	/obj/item/book/manual/research_and_development = "Research/Manuals",
	/obj/item/book/manual/robotics_cyborgs = "Research/Manuals",
	/obj/item/book/manual/ripley_build_and_repair = "Research/Manuals",
	/obj/item/book/manual/synthetic_life = "Research/Manuals",
	/obj/item/book/manual/medical_cloning = "Medical/Manuals",
	/obj/item/book/manual/hydroponics_pod_people = "Civilian/Manuals",
	/obj/item/book/manual/chef_recipes = "Civilian/Manuals",
	/obj/item/book/manual/barman_recipes = "Civilian/Manuals",
	/obj/item/book/manual/cook_guide = "Civilian/Manuals",
	/obj/item/book/manual/bar_guide = "Civilian/Manuals",
))

/// Manuals that are not station reference (an antagonist's handbook).
GLOBAL_LIST_INIT(wiki_manual_excluded, list(/obj/item/book/manual/nuclear))

/// HTML (a manual's dat, a codex page) to wiki markup: headings, list items and paragraphs kept, every other tag dropped, entities decoded.
/// `link_of` (term -> article id) turns the codex's quick links into wiki links.
/proc/wiki_html_markup(html, list/link_of)
	var/text = "[html]"
	for(var/tag in list("style", "script", "head"))
		text = replacetext(text, regex("<[tag]\[^>]*>\[\\s\\S]*?</[tag]>", "gi"), "")
	text = replacetext(text, regex(@"\s*\n\s*", "g"), " ")
	text = replacetext(text, regex(@"<h[1-6][^>]*>", "gi"), "\n\n## ")
	text = replacetext(text, regex(@"</h[1-6]>", "gi"), "\n\n")
	text = replacetext(text, regex(@"<li[^>]*>", "gi"), "\n- ")
	text = replacetext(text, regex(@"</li>|</ul>|</ol>|<ul[^>]*>|<ol[^>]*>", "gi"), "\n")
	text = replacetext(text, regex(@"<br\s*/?>", "gi"), "\n\n")
	text = replacetext(text, regex(@"</?p[^>]*>|</?div[^>]*>|<hr[^>]*>|</?tr[^>]*>", "gi"), "\n\n")
	if(link_of)
		var/regex/anchor = regex(@"<a[^>]*quick_link=([^'&;]+)[^>]*>([\s\S]*?)</a>", "i")
		while(anchor.Find(text))
			var/term = url_decode(anchor.group[1])
			var/id = link_of[lowertext(term)]
			var/label = anchor.group[2]
			text = copytext(text, 1, anchor.index) + (id ? wiki_ref(id, strip_html_properly(label)) : label) + copytext(text, anchor.index + length(anchor.match))
	text = replacetext(text, regex(@"<[^>]+>", "g"), "")
	text = html_decode(text)
	text = replacetext(text, regex(@"\n{3,}", "g"), "\n\n")
	return trimtext(text)

// ---- departments and jobs ----

/proc/wiki_source_station(list/index)
	for(var/datum/department/D as anything in SSjob.get_all_department_datums())
		if(!D.visible || D.centcom_only || !length(D.jobs))
			continue
		wiki_add(index, wiki_dept_id(D.name), "[D.name] department", D.name, "Who works in [D.name], who they answer to, and where to read on.", null, GLOBAL_PROC_REF(wiki_dept_body), D.name)
		for(var/title in D.primary_jobs)
			var/datum/job/J = D.primary_jobs[title]
			if(!J || index[wiki_job_id(J.title)])
				continue
			wiki_add(index, wiki_job_id(J.title), J.title, "[D.name]/Jobs", J.supervisors ? "Answers to [J.supervisors]." : null, null, GLOBAL_PROC_REF(wiki_job_body), J.title)
	for(var/manual_type in subtypesof(/obj/item/book/manual))
		if(manual_type in GLOB.wiki_manual_excluded)
			continue
		var/obj/item/book/manual/M = manual_type
		var/dat = initial(M.dat)
		if(!istext(dat) || !length(dat) || findtext(dat, "<iframe"))
			continue
		wiki_add(index, "manual/[ckey(initial(M.title) || initial(M.name))]", initial(M.title) || initial(M.name), GLOB.wiki_manual_sections[manual_type] || "Civilian/Manuals", initial(M.author) ? "By [initial(M.author)]." : null, null, GLOBAL_PROC_REF(wiki_manual_body), manual_type)
	wiki_source_lore(index)

/proc/wiki_dept_body(name)
	var/datum/department/D
	for(var/datum/department/candidate as anything in SSjob.get_all_department_datums())
		if(candidate.name == name)
			D = candidate
	var/list/blocks = list(wiki_p("The [name] department: its jobs, who leads it, and the reference its people work from. Every job below has its own page."))
	var/list/jobs = list()
	var/list/heads = list()
	for(var/title in D.jobs)
		var/datum/job/J = D.jobs[title]
		var/id = wiki_job_id(J.title)
		var/list/link = wiki_link(wiki_title(id) ? id : null, J.title, J.departments_managed ? "leads it" : null, J.departments_managed ? "good" : null)
		if(J.departments_managed)
			heads += list(link)
		else
			jobs += list(link)
	if(length(heads))
		blocks += list(wiki_links("Led by", heads))
	if(length(jobs))
		blocks += list(wiki_links("Jobs", jobs))
	return blocks

/proc/wiki_job_body(title)
	var/datum/job/J = SSjob.get_job(title)
	var/list/blocks = list(wiki_p(J.job_description))
	var/list/facts = list()
	if(J.supervisors)
		facts += list(list("Answers to", J.supervisors))
	if(length(J.departments))
		var/list/depts = list()
		for(var/dept in J.departments)
			depts[wiki_dept_id(dept)] = dept
		var/list/known = list()
		for(var/id in depts)
			if(wiki_title(id))
				known[id] = depts[id]
		facts += list(list("Department", length(known) ? wiki_ref_list(known) : english_list(J.departments)))
	if(J.departments_managed)
		facts += list(list("Leads", english_list(J.departments_managed)))
	if(J.total_positions > 0)
		facts += list(list("Positions", "[J.total_positions]"))
	if(length(facts))
		blocks += list(wiki_kv(facts))
	if(length(J.alt_titles))
		var/list/titles = list()
		for(var/alt in J.alt_titles)
			titles += "[alt]"
		blocks += list(wiki_h("Also called"), wiki_ul(titles))
	return blocks

/proc/wiki_manual_body(manual_type)
	var/obj/item/book/manual/M = manual_type
	var/list/blocks = wiki_markup_blocks(wiki_html_markup(initial(M.dat)))
	return length(blocks) ? blocks : list(wiki_p(initial(M.desc) || "An operating manual."))

// ---- lore ----

/proc/wiki_lore_id(datum/lore/codex/page)
	var/datum/lore/codex/parent = page.parent()
	return "lore/[parent?.parent() ? "[ckey(parent.name)]/" : ""][ckey(page.name)]"

/// The Traveler's Guide, converted once: a page per codex page, filed by its categories (Lore/<category>). The codex tree is built for the
/// conversion and released after.
/proc/wiki_source_lore(list/index)
	var/datum/codex_tree/tree = new(null, /datum/lore/codex/category/main_borealis_lore)
	var/list/link_of = list()
	var/list/pages = list()
	for(var/term in tree.indexed_pages)
		var/datum/lore/codex/page = tree.indexed_pages[term]
		link_of[lowertext(term)] = wiki_lore_id(page)
		pages[page] = TRUE
	for(var/datum/lore/codex/page as anything in pages)
		if(!page.name)
			continue
		var/list/trail = list()
		var/datum/lore/codex/up = page.parent()
		while(up?.parent())
			trail.Insert(1, up.name)
			up = up.parent()
		var/path = length(trail) ? "Lore/[jointext(trail, "/")]" : "Lore"
		var/title = page == tree.home ? "The Traveler's Guide" : page.name
		var/list/blocks = wiki_markup_blocks(wiki_html_markup(page.data, link_of))
		if(istype(page, /datum/lore/codex/category))
			var/datum/lore/codex/category/C = page
			var/list/children = list()
			for(var/datum/lore/codex/child as anything in C.child_pages)
				if(child.name)
					children += list(wiki_link(wiki_lore_id(child), child.name))
			if(length(children))
				blocks += list(wiki_links("In this section", children))
		if(!length(blocks))
			blocks += list(wiki_p("A section of the Traveler's Guide."))
		wiki_add(index, wiki_lore_id(page), title, path, null, blocks)
	spent(tree)
