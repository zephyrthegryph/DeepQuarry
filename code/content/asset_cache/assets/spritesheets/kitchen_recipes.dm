/datum/asset/spritesheet_batched/kitchen_recipes
	name = "kitchen_recipes"

/datum/asset/spritesheet_batched/kitchen_recipes/create_spritesheets()
	for(var/datum/xform/R as anything in xform_rules_in(MEDIUM_CONTENTS, REGIME_COOKING))
		var/key = sanitize_css_class_name("[R.rule_type]")

		var/atom/item = R.result
		var/datum/universal_icon/icon = get_display_icon_for(item)
		if(!icon || !icon.icon_file)
			continue

		insert_icon(key, icon)
