//! Header-only original output-signature policy over the authentic own-value
//! roster. No BODY is parsed merely to discover or compare parameter names.
use crate::{captured_reactive_reads::Failure,captured_generator_budget::Budget,captured_allow_annotations::Operation,key_policy_control::{self as kc,Control},reactive_original_source::ReadSource,reactive_global_source::Source,sem_handlers_output_policy::Output};
use std::{io,sync::Arc};
struct Work<'a,'source>{source:&'a ReadSource<'source>,peak:usize}
impl dm_analysis::policy_body_demand::WorkspaceWork for Work<'_,'_>{type Error=Failure;const CHECKED:bool=true;fn checkpoint(&mut self)->Result<(),Failure>{self.source.checkpoint()?;self.source.require()?;Ok(())}fn retain(&mut self,n:usize)->Result<(),Failure>{self.source.reserve(Some(n))?;Ok(())}fn temporary(&mut self,n:usize)->Result<(),Failure>{if n>self.peak{self.source.reserve(Some(n-self.peak))?;self.peak=n}Ok(())}fn overflow(&mut self)->Failure{self.source.budget().deny();Failure::Operational(io::ErrorKind::OutOfMemory.into())}fn allocation_failed(&mut self)->Failure{self.overflow()}fn body<'a>(&mut self,_:&'a dm_tree::frontend::BodyArchive,_:usize)->Result<dm_tree::frontend::ArchivedBody<'a>,Failure>{Err("output header roster cannot grant BODY access".into())}}
pub(crate) fn collect(source:&ReadSource<'_>,mut emit:impl FnMut(&str,u32,String)->Result<(),Failure>)->Result<(),Failure>{
 let root=source.budget();source.checkpoint()?;source.require()?;
 for &name in crate::sem_handlers_policy::STANDARD_OUTPUTS{
  let scratch=Budget::scoped_temporaries(root).map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;
  let pending=source.with_budget(&scratch,|source|{
   let mut output=Output::default();let inputs=source.inputs();let mut work=Work{source,peak:0};let mut control=Operation{budget:source.budget(),poll:&||source.checkpoint()};
   for ty in source.tree().types(){control.checkpoint()?;let owner=source.tree().symbols().text(ty.path).ok_or("output own-type spelling absent")?;
    dm_analysis::setter_publication_native::visit_own_values_using(inputs,owner,name,&mut work,&mut|ordinal,_,_|{
     control.checkpoint()?;let header=inputs.archive().header_parameters_using(ordinal,&||source.checkpoint()).map_err(|error|match error{dm_tree::frontend::BodySyntaxFailure::Operational(actual)=>Failure::Operational(actual),dm_tree::frontend::BodySyntaxFailure::Syntax(error)=>Failure::Unsupported(error.message)})?;
     let entries=header.entries()?;let mut names=Vec::new();for parameter in entries{control.checkpoint()?;kc::row(&mut control,&mut names)?;names.push(header.name(parameter)?);}
     let(relative,line)=source.callable_header_site(ordinal)?;output.push_using(owner,&relative,line,names,&mut control)
    })?;
   }
   output.finish_using(name,&mut|owner,control|Source::parent_type(source,owner)?.map(|parent|kc::own(control,parent)).transpose(),&mut|relative,line,message,_|{root.charge(message.capacity())?;emit(relative,line,message)},&mut control)
  });
  if pending.is_err(){scratch.keep_failed_scratch();}drop(scratch);if matches!(&pending,Err(Failure::Operational(_))){return pending}root.require().map_err(|message|Failure::Operational(io::Error::new(io::ErrorKind::OutOfMemory,message)))?;source.checkpoint()?;pending?;
 }Ok(())
}
