//! Diagnostic-only sampled buckets on the actual producer worker.
//! Windows cycles and whole-batch thread CPU are different clocks.
use std::{cell::RefCell,time::Instant};

const BATCH_STRIDE:usize=32;
const ROW_STRIDE:usize=16;

#[derive(Clone,Copy)]
pub(super) enum Bucket{Dispatch,Lex,Provider,Coordinate,Macro,Emit,BatchPush}
const NAMES:[&str;7]=["dispatch","lex","provider","coordinate","macro","emit","batch_push"];

struct State{
    phase:usize,
    row_count:usize,
    current:Bucket,
    previous:Option<u64>,
    active:bool,
    missed:usize,
    ticks:[u64;7],
    visits:[usize;7],
}
thread_local!{static STATE:RefCell<Option<State>>=const{RefCell::new(None)};}

impl State{
    fn boundary(&mut self,next:Bucket,now:Option<u64>){
        if let Some(delta)=now.zip(self.previous).and_then(|(next,old)|next.checked_sub(old)){
            self.ticks[self.current as usize]=self.ticks[self.current as usize].saturating_add(delta);
        }else{self.missed+=1;}
        self.current=next;
        self.previous=now;
    }
}

pub(super) struct Sampler{enabled:bool,ordinal:usize}
impl Sampler{
    pub(super) fn from_environment()->Self{
        Self{enabled:std::env::var_os("DMB_ORIGINAL_SAMPLE_FILL_CPU").is_some(),ordinal:0}
    }
    pub(super) fn next(&mut self)->Option<BatchGuard>{
        if !self.enabled{return None;}
        let ordinal=self.ordinal;
        self.ordinal+=1;
        if ordinal%BATCH_STRIDE!=0{return None;}
        STATE.with(|slot|{
            let mut slot=slot.borrow_mut();
            assert!(slot.is_none(),"one sample on its actual producer");
            *slot=Some(State{
                phase:(ordinal/BATCH_STRIDE)%ROW_STRIDE,row_count:0,current:Bucket::Dispatch,
                previous:None,active:false,missed:0,ticks:[0;7],visits:[0;7],
            });
        });
        Some(BatchGuard{ordinal,cpu:dm_profile::sample_thread_cpu_ns(),wall:Instant::now(),filled_rows:None})
    }
}

pub(super) struct BatchGuard{ordinal:usize,cpu:Option<u64>,wall:Instant,filled_rows:Option<usize>}
impl BatchGuard{
    pub(super) fn finished_rows(&mut self,rows:Option<usize>){self.filled_rows=rows;}
}
impl Drop for BatchGuard{
    fn drop(&mut self){
        let wall=self.wall.elapsed();
        let cpu=dm_profile::sample_thread_cpu_ns().zip(self.cpu).and_then(|(end,start)|end.checked_sub(start));
        let state=STATE.with(|slot|slot.borrow_mut().take()).expect("actual sampled batch");
        use std::io::Write;
        let _=writeln!(std::io::stderr().lock(),
            "ORIGINAL_FILL_CPU_SAMPLE batch={} phase={} sampled_rows={} filled_rows={:?} batch_wall_ns={} batch_cpu_ns={cpu:?} bucket_units={} names={NAMES:?} exclusive={:?} visits={:?} missing={}",
            self.ordinal,state.phase,state.row_count,self.filled_rows,wall.as_nanos(),CLOCK_UNITS,state.ticks,state.visits,state.missed,
        );
    }
}

pub(super) struct RowGuard;
pub(super) fn row(ordinal:usize)->Option<RowGuard>{
    STATE.with(|slot|{
        let mut slot=slot.borrow_mut();
        let state=slot.as_mut()?;
        if ordinal%ROW_STRIDE!=state.phase{return None;}
        assert!(!state.active,"one actual producer row");
        state.row_count+=1;
        state.current=Bucket::Dispatch;
        state.visits[Bucket::Dispatch as usize]+=1;
        state.previous=tick();
        state.active=true;
        Some(RowGuard)
    })
}
impl Drop for RowGuard{
    fn drop(&mut self){
        STATE.with(|slot|{
            let mut slot=slot.borrow_mut();
            let state=slot.as_mut().expect("active sampled row");
            state.boundary(Bucket::Dispatch,tick());
            state.active=false;
            state.previous=None;
        });
    }
}

pub(super) struct Scope(Bucket);
pub(super) fn scope(bucket:Bucket)->Option<Scope>{
    STATE.with(|slot|{
        let mut slot=slot.borrow_mut();
        let state=slot.as_mut().filter(|state|state.active)?;
        let previous=state.current;
        state.visits[bucket as usize]+=1;
        state.boundary(bucket,tick());
        Some(Scope(previous))
    })
}
impl Drop for Scope{
    fn drop(&mut self){
        STATE.with(|slot|{
            let mut slot=slot.borrow_mut();
            slot.as_mut().expect("active sampled scope").boundary(self.0,tick());
        });
    }
}

#[cfg(windows)]
const CLOCK_UNITS:&str="windows_thread_cycles";
#[cfg(not(windows))]
const CLOCK_UNITS:&str="thread_cpu_ns";
#[cfg(windows)]
fn tick()->Option<u64>{
    #[link(name="kernel32")]
    extern "system"{
        fn GetCurrentThread()->*mut std::ffi::c_void;
        fn QueryThreadCycleTime(thread:*mut std::ffi::c_void,cycles:*mut u64)->i32;
    }
    let mut cycles=0;
    // SAFETY: current pseudo-handle and live output pointer, no aliasing.
    (unsafe{QueryThreadCycleTime(GetCurrentThread(),&mut cycles)}!=0).then_some(cycles)
}
#[cfg(not(windows))]
fn tick()->Option<u64>{dm_profile::sample_thread_cpu_ns()}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn nested_bucket_time_is_exclusive_and_missing_clock_does_not_invent_work(){
        let mut state=State{phase:0,row_count:1,current:Bucket::Macro,previous:Some(10),active:true,missed:0,ticks:[0;7],visits:[0;7]};
        state.boundary(Bucket::Lex,Some(30));
        state.boundary(Bucket::Provider,Some(32));
        state.boundary(Bucket::Lex,Some(39));
        state.boundary(Bucket::Macro,Some(44));
        state.boundary(Bucket::Dispatch,None);
        assert_eq!(state.ticks,[0,7,7,0,20,0,0]);
        assert_eq!(state.missed,1);
    }
}
