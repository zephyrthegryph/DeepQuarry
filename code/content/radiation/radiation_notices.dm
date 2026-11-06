// Occurrences announced with PUBLISH(E, name, field = v): nothing can refuse them, so each is a FIXED ACTION whose notice (the past-tense
// /datum/notice/x of the same name) is generated with the fields below (doc/rewrite/final_api.html sections 8 and 10).

/// From the radiation subsystem, called before a potential irradiation. This does not guarantee radiation can reach or will succeed, but merely that there's a radiation source within range. (datum/radiation_pulse_information/pulse_information, insulation_to_target)
ACTION(in_range_of_irradiation, pulse_information, insulation_to_target, FIXED, notice = /datum/notice/in_range_of_irradiation)
