// Shared TEST-ONLY extraction of the existing dm-tree checked fixture host.
// It owns resource admission/census only, never a parser/model/cache/daemon.
use super::*;
use std::sync::{Arc,atomic::{AtomicBool,AtomicUsize,Ordering}};
#[derive(Debug)]
pub(crate) struct Host {
    pub(crate) counter:Arc<AtomicUsize>,
    pub(crate) limit:AtomicUsize,
    pub(crate) fail:AtomicBool,
    pub(crate) entries:AtomicUsize,
    pub(crate) aliases:std::sync::Mutex<OriginalSignatureAliasCensus>,
}
impl Host {
    pub(crate) fn new()->Arc<Self>{Arc::new(Self{counter:Arc::new(AtomicUsize::new(0)),limit:AtomicUsize::new(128*1024*1024),fail:AtomicBool::new(false),entries:AtomicUsize::new(0),aliases:Default::default()})}
    fn checkpoint(&self)->std::io::Result<()>{if self.fail.load(Ordering::Acquire){Err(std::io::Error::from_raw_os_error(1450))}else{Ok(())}}
}
impl SettingExpressionQueries for Host {
    fn retain_original_signature_aliases(&self,row:Arc<OriginalSignatureAliasGroup>,a:&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>{self.aliases.lock().unwrap().retain(row,a).map_err(BodySyntaxFailure::Operational)}
    fn expression(&self,input:&SettingExpressionInput<'_>)->Result<dm_syntax::SettingExpression,BodySyntaxFailure>{
        let checkpoint=||self.checkpoint();
        input.prepare(&dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint))
    }
    fn initializer<'source>(&self,input:&OriginalInitializerExpressionInput<'source>)->Result<OriginalInitializerExpression<'source>,BodySyntaxFailure>{
        let checkpoint=||self.checkpoint();
        input.prepare(&dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint))
    }
    fn with_declaration_admission(&self,operation:&mut dyn FnMut(&dm_syntax::SettingAdmission<'_>)->Result<(),BodySyntaxFailure>)->Result<(),BodySyntaxFailure>{
        self.entries.fetch_add(1,Ordering::Relaxed);
        let checkpoint=||self.checkpoint();
        let a=dm_syntax::SettingAdmission::new(&self.counter,self.limit.load(Ordering::Acquire),&checkpoint);
        self.aliases.lock().unwrap().prune(&a).map_err(BodySyntaxFailure::Operational)?;
        let before=a.checkpoint();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
        before.map_err(BodySyntaxFailure::Operational)?;
        let result=operation(&a);
        if matches!(&result,Err(BodySyntaxFailure::Operational(_))){return result}
        let after=a.checkpoint();
        if let Some(actual)=a.take_operational_error(){return Err(BodySyntaxFailure::Operational(actual))}
        after.map_err(BodySyntaxFailure::Operational)?;result
    }
}
