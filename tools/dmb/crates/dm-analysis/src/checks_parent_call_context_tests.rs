use super::*;
use dm_tree::{frontend::{build,BodyArena},EngineHierarchy};
use std::path::Path;
struct Source(&'static str);
impl dm_preprocess::SourceProvider for Source {
    fn read(&self,_:&Path)->Result<String,String> {Ok(self.0.into())}
}
#[test]
fn foreign_source_host_cannot_reinterpret_an_issued_body_via_same_callable_name() {
    let a=build(Path::new("a.dme"),&Source("/datum/left\n/datum/right\n/datum/example\n    parent_type = /datum/left\n/datum/example/proc/probe()\n    return ..()\n"),&Default::default(),1).unwrap();
    let b=build(Path::new("b.dme"),&Source("/datum/left\n/datum/right\n/datum/example\n    parent_type = /datum/right\n/datum/example/proc/probe()\n    return ..()\n"),&Default::default(),1).unwrap();
    let tree=b.snapshot.tree.as_ref().clone();
    let hierarchy=EngineHierarchy {schema:99,parents:tree.types().iter().map(|t|(t.path,t.parent.map(|id|tree.type_node(id).unwrap().path))).collect()};
    let foreign=tree.with_complete_intrinsics(hierarchy,Vec::new()).unwrap();
    let arena=BodyArena::new_typed(&a,|_|true);
    arena.with_parsed(&a.bodies[0],|body| {
        assert!(check(&a,body,&foreign,Severity::Error).unwrap_err().contains("ancestry"));
    }).unwrap();
}
