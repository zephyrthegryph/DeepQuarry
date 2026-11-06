/proc/ui_style2icon(ui_style)
	if(ui_style in GLOB.all_ui_styles)
		return GLOB.all_ui_styles[ui_style]
	return GLOB.all_ui_styles["White"]

