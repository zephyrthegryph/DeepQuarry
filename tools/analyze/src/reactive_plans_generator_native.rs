//! Plans metadata over SAME original callable coordinates and raw file loans.
//! Only bounded key/name summaries survive; no Proc/File/AST/source model.
use crate::{reactive_global_source::Source as OriginalSource,reactive_reads_native::Failure,plans_policy::{self,PreparedMetadata,MarkerRow},key_policy_control as kc};
use std::io;
struct Control<'a>(&'a dyn OriginalSource);
impl kc::Control for Control<'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.0.budget().require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;self.0.checkpoint()?;self.0.budget().require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;self.0.require()?;Ok(())}fn reserve(&mut self,n:usize)->Result<(),Failure>{self.0.budget().charge(n).map_err(|actual|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,actual)))}fn overflow(&mut self)->Failure{self.0.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans metadata capacity overflow"))}fn allocation_failed(&mut self)->Failure{self.0.budget().deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans metadata capacity refused"))}}
fn reserve_captures(budget:&crate::captured_generator_budget::Budget)->Result<(),Failure>{let bytes=plans_policy::metadata_capture_backing().ok_or_else(||{budget.deny();Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,"Plans capture metadata overflow"))})?;budget.charge(bytes).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))}
struct Reader<'a>{relative:String,header:u32,ordinal:usize,owner:&'a str,name:&'a str,matched:bool}
pub(crate) fn collect(source:&dyn OriginalSource)->Result<PreparedMetadata,Failure>{let mut c=Control(source);kc::Control::checkpoint(&mut c)?;let defines=source.dependency_defines()?;let markers=source.plans_marker_rows()?;let mut out=PreparedMetadata::for_native_generation();reserve_captures(source.budget())?;for marker in &markers.markers{out.marker(&MarkerRow{name:&marker.name,args:&marker.args,body:&marker.body},&defines,&mut c)?;}
    let mut readers = Vec::new();
    source.visit_callables(
        Some(&[
            "draw", "hidden_verbs", "push_to_rust", "on_state_changed",
            "reactions", "derived", "generated_reads", "derived_reads",
        ]),
        &mut || source.checkpoint().map_err(Failure::Operational),
        &mut |call| {
            kc::Control::checkpoint(&mut c)?;
            match call.name {
                "draw" | "hidden_verbs" => out.legacy_output(call.owner, &mut c)?,
                "push_to_rust" | "on_state_changed" => out.side_override(call.owner, &mut c)?,
                _ => {
                    let (relative, _) = source.site_line(call.ordinal, 1)?;
                    let header = u32::try_from(call.header).map_err(|_| {
                        Failure::Unsupported("Plans original reader header line overflow".into())
                    })?;
                    crate::reactive_dependency_fold::row(&mut c, &mut readers)?;
                    readers.push(Reader { relative, header, ordinal: call.ordinal, owner: call.owner, name: call.name, matched: false });
                }
            }
            Ok(())
        },
    )?;
 readers.sort_unstable_by(|a,b|(&a.relative,a.header,a.owner,a.name).cmp(&(&b.relative,b.header,b.owner,b.name)));readers.dedup_by(|a,b|a.relative==b.relative&&a.header==b.header&&a.owner==b.owner&&a.name==b.name);
 let completed=source.with_plan_metadata_files(&mut|relative,views,code_source|{kc::Control::checkpoint(&mut c)?;let first=readers.partition_point(|row|row.relative.as_str()<relative);let last=readers.partition_point(|row|row.relative.as_str()<=relative);if !code_source&&first==last{return Ok(true)}reserve_captures(views.allocation_budget(source.budget()))?;let text=views.raw()?;if code_source{out.file(text,&defines,&mut c)?;}for row in &mut readers[first..last]{out.reader(text,row.header,row.owner,row.name,&defines,&mut c)?;row.matched=true;}Ok(true)})?;if !completed{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidInput,"Plans CODE metadata traversal stopped")))}
 for row in readers.iter_mut().filter(|row|!row.matched){source.with_plan_reader_file(row.ordinal,row.name,&mut|relative,views|{kc::Control::checkpoint(&mut c)?;if row.matched||relative!=row.relative{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"required Plans callable file differs or was loaned twice")))}reserve_captures(views.allocation_budget(source.budget()))?;out.reader(views.raw()?,row.header,row.owner,row.name,&defines,&mut c)?;row.matched=true;Ok(())})?;if !row.matched{return Err(Failure::Operational(io::Error::new(io::ErrorKind::InvalidData,"required Plans callable provider omitted its source loan")))}}
 source.raw_metadata(&mut||source.checkpoint(),&mut|_,event|{if let crate::raw_reactive_metadata_policy::Event::Tracked{name,..}=event{out.tracked(name,&mut c)?;}Ok(())})?;kc::Control::checkpoint(&mut c)?;Ok(out)}
pub(crate) fn generate(source:&dyn OriginalSource,analysis:crate::reactive_dependency_view::Analysis<'_>)->Result<crate::sparse_slots_policy::Output,Failure>{let metadata=collect(source)?;let result=plans_policy::generate_prepared_admitted(analysis,&metadata,source.budget(),&||{source.budget().require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))?;source.checkpoint()?;source.budget().require().map_err(|message|io::Error::new(io::ErrorKind::OutOfMemory,message))});match result{Err(actual)=>Err(Failure::Operational(actual)),Ok(output)=>{kc::Control::checkpoint(&mut Control(source))?;Ok(output)}}}
