/mob/close_declared_tooltip(atom/holder)
	return closeToolTip(src, holder)

/mob/open_declared_tooltip(atom/holder, params, title, content, theme)
	return openToolTip(src, holder, params, title = title, content = content, theme = theme)
