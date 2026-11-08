// Representative icons for each research design
/datum/asset/spritesheet_batched/research_designs
	name = "design"

/// The designs are content: code/content/research/tg/designs.dm lists them (entry_sources()) and inserts each one's icon
/// (add_entry_for()), a step at a time in the asset loader.

/// What a design's icon shows for its build_path: the path itself. A build_path that is a VARIANT() reference is resolved by content
/// (code/content/research/tg/designs.dm).
/datum/asset/spritesheet_batched/research_designs/proc/product_of(build_path)
	return build_path
