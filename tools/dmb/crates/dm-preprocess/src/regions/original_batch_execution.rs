//! Closed resource/execution loans for the actual Original batch producer.
use crate::SourceProvider;
use dm_syntax::SettingAdmission;use std::io;
/// Resource/execution loan only. Actual Tree adapter delegates the existing
/// SettingExpressionQueries host; no counter, parser, daemon or source grant.
pub trait OriginalBatchSyntaxHost:Send+Sync{
 fn with_producer_admission(&self,run:&mut dyn FnMut(&SettingAdmission<'_>)->io::Result<()>)->io::Result<()>;
}
pub struct OriginalBatchExecution<'a>{provider:&'a(dyn SourceProvider+Sync),host:&'a dyn OriginalBatchSyntaxHost,executor:&'a dm_exec::BuildExecutor}
impl<'a>OriginalBatchExecution<'a>{
 pub fn new(provider:&'a(dyn SourceProvider+Sync),host:&'a dyn OriginalBatchSyntaxHost,executor:&'a dm_exec::BuildExecutor)->Self{Self{provider,host,executor}}
 pub(crate) fn provider(&self)->&'a(dyn SourceProvider+Sync){self.provider}
 pub(crate) fn host(&self)->&'a dyn OriginalBatchSyntaxHost{self.host}
 pub(crate) fn executor(&self)->&'a dm_exec::BuildExecutor{self.executor}
}
