//! Stack-only decorator for the actual primary signature observer.
//! Ordinary observer layout and default behavior remain unchanged.
use super::*;
use dm_preprocess::regions::{OriginalPrimaryStreamConsumer,OriginalFormalTokenStream,OriginalNoticeRegistration};
pub(crate) trait CommittedBodySyntaxConsumer{
 fn formal_prefix_adoption(&mut self,_:&dm_preprocess::regions::OriginalStreamPrimary,_:&dm_syntax::SettingAdmission<'_>)->std::io::Result<crate::frontend::committed_bodies::CommittedPrefixAdoption>{Err(std::io::Error::new(std::io::ErrorKind::Unsupported,"report-only committed prefix is not supported by this consumer"))}
 fn final_adoption(&mut self,primary:&dm_preprocess::regions::OriginalStreamPrimary,end:&OriginalNoticeRegistration,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<crate::frontend::committed_bodies::CommittedHeaderAdoption>;
 fn failed_prefix(&mut self,input:dm_syntax::OriginalCommittedBodyInput<'_,'_>,registration:&OriginalNoticeRegistration,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>;
 fn produce(&mut self,input:dm_syntax::OriginalCommittedBodyInput<'_,'_>,parameters:dm_syntax::SharedParameterSignature,registration:&OriginalNoticeRegistration,producer:&dm_syntax::OriginalPrimaryProducerIdentity,a:&dm_syntax::SettingAdmission<'_>)->std::io::Result<()>;
}
pub(crate) struct CommittedSignatureConsumer<'loan,'a,'budget>{
 pub(crate) observer:&'loan mut OriginalSignatureObserver<'a,'budget>,
 pub(crate) body:&'loan mut dyn CommittedBodySyntaxConsumer,
}
impl dm_syntax::OriginalDeclarationHeaderObserver for CommittedSignatureConsumer<'_,'_,'_>{
 fn header(&mut self,event:dm_syntax::OriginalPrimaryHeader<'_>)->std::io::Result<dm_syntax::OriginalHeaderFlow>{dm_syntax::OriginalDeclarationHeaderObserver::header(self.observer,event)}
 fn declaration_committed(&mut self,event:dm_syntax::OriginalPrimaryCommit<'_>)->std::io::Result<()>{dm_syntax::OriginalDeclarationHeaderObserver::declaration_committed(self.observer,event)}
 fn wants_committed_body_input(&self)->bool{true}
 fn committed_body_input(&mut self,input:dm_syntax::OriginalCommittedBodyInput<'_,'_>)->std::io::Result<()>{
  checkpoint(self.observer.a)?;
  if input.body_collection()==dm_syntax::OriginalCommittedBodyCollection::NotCallable{return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual callable commit loan has a noncallable role"))}
  if input.body_collection()==dm_syntax::OriginalCommittedBodyCollection::FailedPrefix{
   let registration=self.observer.reader_registration.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual failed-prefix reader registration is unissued"))?;
   return self.body.failed_prefix(input,registration,self.observer.a)
  }
  let parameters=self.observer.prepare_committed_parameters(&input)?;
  let registration=self.observer.reader_registration.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::Unsupported,"actual committed BODY reader registration is unissued"))?;
  let producer=&self.observer.rows.producers.first.as_ref().ok_or_else(||std::io::Error::new(std::io::ErrorKind::InvalidInput,"actual completed header producer is absent"))?.1;
  self.body.produce(input,parameters,registration,producer,self.observer.a)
 }
}
impl OriginalPrimaryStreamConsumer for CommittedSignatureConsumer<'_,'_,'_>{
 fn wants_reader_registrations(&self)->bool{true}
 fn reader_registration(&mut self,registration:OriginalNoticeRegistration)->std::io::Result<()>{OriginalPrimaryStreamConsumer::reader_registration(self.observer,registration)}
 fn retains_committed_items(&self)->bool{true}
 fn callable(&mut self,header:dm_syntax::OriginalPrimaryLiveHeader,source:&mut dyn OriginalFormalTokenStream)->std::io::Result<dm_syntax::OriginalHeaderFlow>{OriginalPrimaryStreamConsumer::callable(self.observer,header,source)}
}
