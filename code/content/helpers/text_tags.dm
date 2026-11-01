// The content half of code/base/helpers/text.dm: what names content, so the layer the engine calls cannot hold it.

//For generating neat chat tag-images
//The icon var could be local in the proc, but it's a waste of resources
//	to always create it and then throw it out.
GLOBAL_VAR_INIT(text_tag_icons, 'icons/chattags.dmi')
DECLARE_SHARED_CACHE_EX(text_tags, GLOBAL_PROC_REF(build_text_tag), SC_NEVER, 256, 0)

/proc/build_text_tag(tagname)
	var/datum/asset/spritesheet_batched/chatassets = get_asset_datum(/datum/asset/spritesheet_batched/chat)
	return chatassets.icon_tag(tagname)

/proc/create_text_tag(tagname, tagdesc = tagname, client/C = null)
	if(!(C && C.prefs?.read_preference(/datum/preference/toggle/chat_tags)))
		return tagdesc
	if(!C.tgui_panel.is_ready() || C.tgui_panel.oldchat)
		return "<IMG src='[REF(GLOB.text_tag_icons)]' class='text_tag' iconstate='[tagname]'" + (tagdesc ? " alt='[tagdesc]'" : "") + ">"
	return CACHED(text_tags, tagname)

