//! SAME original setter-publication scalar/call-name judge.
//! No parser, semantic model, source authority, storage or cache.
pub const PUBLISHERS:&[&str]=&["tracked_changed","publish_change","state_changed","record_changed","rel_set","rel_add","rel_remove","own_set","own_add","own_put","own_clear","timed_set","vars_write"];
pub fn publishes_named(name:&str)->bool{PUBLISHERS.contains(&name)||name.starts_with("set_")||name.starts_with("add_")||name.starts_with("remove_")||name.starts_with("publish")}
pub fn owned_base_call(name:&str)->bool{name=="native_write"||name.starts_with("heat_")||name.starts_with("vg_")}
#[derive(Clone,Copy,Debug,Eq,PartialEq)]pub enum Finding{NoPublish,NotSetter}
impl Finding{pub fn rule(self)->&'static str{match self{Self::NoPublish=>"no_publish",Self::NotSetter=>"not_a_setter"}}}
pub fn judge(writes:bool,publishes:bool,must:bool)->Option<Finding>{if writes&&!publishes{Some(Finding::NoPublish)}else if !writes&&!publishes&&must{Some(Finding::NotSetter)}else{None}}
