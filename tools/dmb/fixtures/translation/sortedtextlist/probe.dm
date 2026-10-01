/proc/dd_sortedtextlist(list/incoming, case_sensitive = 0)
	                                                  
	                                           
	                                                                                                             
	                                                             
	                                                       
	var/list/sorted_text = new()
	var/low_index
	var/high_index
	var/insert_index
	var/midway_calc
	var/current_index
	var/current_item
	var/list/list_bottom
	var/sort_result

	var/current_sort_text
	for (current_sort_text in incoming)
		low_index = 1
		high_index = sorted_text.len
		while (low_index <= high_index)
			                                                                                                   
			midway_calc = (low_index + high_index) / 2
			current_index = round(midway_calc)
			if (midway_calc > current_index)
				current_index++
			current_item = sorted_text[current_index]

			if (case_sensitive)
				sort_result = sorttextEx(current_sort_text, current_item)
			else
				sort_result = sorttext(current_sort_text, current_item)

			switch(sort_result)
				if (1)
					high_index = current_index - 1	                                   
				if (-1)
					low_index = current_index + 1	                                   
				if (0)
					low_index = current_index		                                    
					break

		                           
		insert_index = low_index

		                                      
		if (insert_index > sorted_text.len)
			sorted_text += current_sort_text
			continue

		                                                              
		                                                                                
		list_bottom = sorted_text.Copy(insert_index)
		sorted_text.Cut(insert_index)
		sorted_text += current_sort_text
		sorted_text += list_bottom
	return sorted_text