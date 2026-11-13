//! Real primary syntax with an operation-only observer allocation barrier.
use super::*;
use dm_tree::frontend::{build, BodyArena};
use std::path::Path;
struct Source;
impl dm_preprocess::SourceProvider for Source {
    fn read(&self, _: &Path) -> Result<String, String> {
        Ok("/proc/probe()\n    if(1)\n        var/x=0\n".into())
    }
}
#[derive(Default)]
struct Probe {
    limit: usize,
    deny_enter: bool,
    denied: bool,
    entered: usize,
    left: usize,
    leaves: usize,
    chronology:Vec<&'static str>,
    refuse_switch:bool,
}
impl<'a> EvaluatedObserver<'a> for Probe {
    fn switch_started(&mut self,_selector:&'a Expr,_cases:&'a [dm_syntax::SwitchCase],_default_present:bool,_at:Span)->Result<(),String>{self.chronology.push("switch");if self.refuse_switch{Err("actual early switch refusal".into())}else{Ok(())}}
    fn control_event(&mut self,_event:Event<'a>)->Result<bool,String>{self.chronology.push("control");Ok(false)}
    fn admit_storage(&mut self, bytes: usize) -> Result<bool, String> {
        if self.denied || bytes > self.limit {
            self.denied = true;
            Err("test operation storage denied".into())
        } else {
            self.limit -= bytes;
            Ok(true)
        }
    }
    fn enter_scope(&mut self, _: ScopeKind) {
        self.entered += 1;
        if self.deny_enter {
            self.denied = true
        }
    }
    fn leave_scope(&mut self, _: ScopeKind) {
        self.left += 1
    }
    fn leaf(&mut self, _: &'a Statement) -> Result<(), String> {
        self.leaves += 1;
        Ok(())
    }
    fn expression(&mut self, _: &'a Expr) -> Result<(), String> {
        self.chronology.push("expression");
        Ok(())
    }
    fn statement_expression(&mut self, _: &'a Expr) -> Result<(), String> {
        Ok(())
    }
    fn initializer(&mut self, _: &'a dm_syntax::ForInitializer, _: Span) -> Result<(), String> {
        Ok(())
    }
    fn binding(&mut self, _: &'a str, _: Option<&'a Expr>, _: bool, _: Span) -> Result<(), String> {
        Ok(())
    }
    fn catch_binding(&mut self, _: Option<&'a str>, _: Span, _: Span) -> Result<(), String> {
        Ok(())
    }
}
fn walk_probe(observer: &mut Probe) -> Result<(), String> {
    let frontend = build(
        Path::new("control-storage.dme"),
        &Source,
        &Default::default(),
        1,
    )
    .map_err(|e| format!("{e:?}"))?;
    let arena = BodyArena::new_typed(&frontend, |_| true);
    arena
        .with_parsed(&frontend.bodies[0], |body| {
            let view = BodyView::new(&frontend, body)?;
            analyze_with_observer(&view, observer).map(|_| ())
        })
        .map_err(|e| e.message)?
}
#[test]
fn reachable_events_admit_before_growing_the_original_observation_vector() {
    let mut observer = Probe::default();
    assert!(walk_probe(&mut observer)
        .unwrap_err()
        .contains("storage denied"));
    assert!(observer.denied);
    assert_eq!(observer.entered, 0);
    assert_eq!(observer.leaves, 0);
}
#[test]
fn void_scope_denial_is_checked_immediately_and_preserves_the_paired_leave() {
    let mut observer = Probe {
        limit: 1024 * 1024,
        deny_enter: true,
        ..Default::default()
    };
    assert!(walk_probe(&mut observer)
        .unwrap_err()
        .contains("storage denied"));
    assert_eq!(
        (observer.entered, observer.left, observer.leaves),
        (1, 1, 0)
    );
}

struct EarlySwitchSource;impl dm_preprocess::SourceProvider for EarlySwitchSource{fn read(&self,_:&Path)->Result<String,String>{Ok("/proc/probe()\n    switch(rand(1,3))\n        if(1)\n            return 0\n".into())}}
fn walk_early_switch(observer:&mut Probe)->Result<(),String>{let frontend=build(Path::new("early-switch.dme"),&EarlySwitchSource,&Default::default(),1).map_err(|e|format!("{e:?}"))?;let arena=BodyArena::new_typed(&frontend,|_|true);arena.with_parsed(&frontend.bodies[0],|body|{let view=BodyView::new(&frontend,body)?;analyze_with_observer(&view,observer).map(|_|())}).map_err(|e|e.message)?}
#[test]fn switch_start_precedes_control_condition_and_main_selector_evaluation(){let mut observer=Probe{limit:1<<20,..Default::default()};walk_early_switch(&mut observer).unwrap();assert_eq!(&observer.chronology[..3],["switch","control","expression"]);let mut refused=Probe{limit:1<<20,refuse_switch:true,..Default::default()};assert!(walk_early_switch(&mut refused).unwrap_err().contains("actual early switch refusal"));assert_eq!(refused.chronology,["switch"]);assert_eq!((refused.entered,refused.leaves),(0,0));}
