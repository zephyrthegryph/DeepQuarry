//Sender is optional
/proc/admin_chat_message(message = "Debug Message", color = "#FFFFFF", sender)
	if (!CONFIG_GET(string/chat_webhook_url) || !message)
		return
	var/query_string = "type=adminalert"
	query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
	query_string += "&msg=[url_encode(message)]"
	query_string += "&color=[url_encode(color)]"
	if(sender)
		query_string += "&from=[url_encode(sender)]"
	http_get_async("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")

/proc/admin_action_message(admin = "INVALID", user = "INVALID", action = "INVALID", reason = "INVALID", time = "INVALID")
	if (!CONFIG_GET(string/chat_webhook_url) || !action)
		return
	var/query_string = "type=adminaction"
	query_string += "&key=[url_encode(CONFIG_GET(string/chat_webhook_key))]"
	query_string += "&admin=[url_encode(admin)]"
	query_string += "&user=[url_encode(user)]"
	query_string += "&action=[url_encode(action)]"
	query_string += "&reason=[url_encode(reason)]"
	query_string += "&time=[url_encode(time)]"
	http_get_async("[CONFIG_GET(string/chat_webhook_url)]?[query_string]")
