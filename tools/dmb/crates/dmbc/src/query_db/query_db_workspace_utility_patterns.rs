//! Sibling scoped provider over the existing reader pattern slot. Callbacks may
//! perform real source reads BETWEEN pattern calls; no ledger borrow spans IO.
use super::*;
impl WorkspaceCodeReader<'_,'_>{pub(in crate::query_db)fn with_utility_patterns<T>(&self,consume:impl FnOnce(&dyn dq_analyze::native_pattern::Provider)->Result<T,Failure>)->Result<T,Failure>{let slot=self.new_pattern_slot().map_err(Failure::Operational)?;let provider=ReaderPatternProvider{reader:self,slot:&slot};let result=consume(&provider);if matches!(&result,Err(Failure::Operational(_))){return result}self.checkpoint()?;result}}
