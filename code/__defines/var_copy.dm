/// Identity/bookkeeping vars (om_hid: the OM handle slot, om_rec, gc_destroyed,
/// weak_reference) belong to one datum; a copy sharing them resolves as the original.
/// Use this when copying vars[] to skip some built in byond ones that get really unhappy when you access them like that. Used like if(BLACKLISTED_COPY_VARS) in switch or list(BLACKLISTED_COPY_VARS)
#define BLACKLISTED_COPY_VARS "ATOM_TOPIC_EXAMINE","type","loc","locs","vars","parent","parent_type","verbs","ckey","key","om_hid","om_rec","gc_destroyed","weak_reference","own_holder_ref","own_slot","own_key_text","om_refs_in"
