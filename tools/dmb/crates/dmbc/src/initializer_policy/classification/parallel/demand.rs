//! Per-bucket transport only: the original preparation, workers, semantic store,
//! token issuer and source ordering remain in the shared parallel implementation.
use super::*;
use super::super::demand::{Checked,Compatibility,Demand as ClassDemand,ClassificationReadFailure};
use crate::initializer_policy::modifier_facts::{self,ModifierKey,ModifierReadFailure};
pub(super) trait ParallelDemand:ClassDemand {
    type ReportFailure:Send;
    type Operational;
    fn semantic(source:ClassificationError)->Self::ReportFailure;
    fn operational(actual:Self::Operational)->Self::ReportFailure;
    fn split(error:Self::ReportFailure)->Result<ClassificationError,Self::Operational>;
    fn failure(error:Self::Failure,ordinal:usize)->Self::ReportFailure;
    fn modifiers<'a>(writes:impl ExactSizeIterator<Item=&'a InitializerWrite>,symbols:&SymbolTable,worker:&dyn CapturedInitializerEvaluator,ordinals:&[usize],factory:ParallelEvaluator<'_>,reuse:Option<InitializerReuse<'_>>,keys:Option<&[ModifierKey]>,admission:Option<&crate::initializer_policy::current_admission::Admission<'_,'_>>)->Result<Vec<ModifierFact>,Self::ReportFailure>;
}
impl ParallelDemand for Compatibility {
    type ReportFailure=ClassificationError;type Operational=std::convert::Infallible;
    fn semantic(source:ClassificationError)->Self::ReportFailure{source}
    fn operational(never:Self::Operational)->Self::ReportFailure{match never{}}
    fn split(error:Self::ReportFailure)->Result<ClassificationError,Self::Operational>{Ok(error)}
    fn failure(error:Self::Failure,ordinal:usize)->Self::ReportFailure{ClassificationError{issues:error.into_issues(ordinal)}}
    fn modifiers<'a>(writes:impl ExactSizeIterator<Item=&'a InitializerWrite>,symbols:&SymbolTable,worker:&dyn CapturedInitializerEvaluator,ordinals:&[usize],factory:ParallelEvaluator<'_>,reuse:Option<InitializerReuse<'_>>,keys:Option<&[ModifierKey]>,admission:Option<&crate::initializer_policy::current_admission::Admission<'_,'_>>)->Result<Vec<ModifierFact>,Self::ReportFailure>{
        match(reuse,keys){(Some(reuse),Some(keys))=>modifier_facts::modifier_facts_reused_in(writes,symbols,worker,ordinals,factory,reuse,keys,admission),_=>modifier_facts::modifier_facts_indexed(writes,symbols,worker,Some(ordinals))}
    }
}
impl ParallelDemand for Checked {
    type ReportFailure=InitializerClassificationFailure;type Operational=std::io::Error;
    fn semantic(source:ClassificationError)->Self::ReportFailure{InitializerClassificationFailure::Semantic(source)}
    fn operational(actual:Self::Operational)->Self::ReportFailure{InitializerClassificationFailure::Operational(actual)}
    fn split(error:Self::ReportFailure)->Result<ClassificationError,Self::Operational>{match error{InitializerClassificationFailure::Semantic(source)=>Ok(source),InitializerClassificationFailure::Operational(actual)=>Err(actual)}}
    fn failure(error:Self::Failure,ordinal:usize)->Self::ReportFailure{match error{ClassificationReadFailure::Semantic(source)=>Self::semantic(ClassificationError{issues:source.into_issues(ordinal)}),ClassificationReadFailure::Operational(actual)=>Self::operational(actual)}}
    fn modifiers<'a>(writes:impl ExactSizeIterator<Item=&'a InitializerWrite>,symbols:&SymbolTable,worker:&dyn CapturedInitializerEvaluator,ordinals:&[usize],factory:ParallelEvaluator<'_>,reuse:Option<InitializerReuse<'_>>,keys:Option<&[ModifierKey]>,admission:Option<&crate::initializer_policy::current_admission::Admission<'_,'_>>)->Result<Vec<ModifierFact>,Self::ReportFailure>{
        let result=match(reuse,keys){(Some(reuse),Some(keys))=>modifier_facts::modifier_facts_reused_checked_in(writes,symbols,worker,ordinals,factory,reuse,keys,admission),_=>modifier_facts::modifier_facts_indexed_checked(writes,symbols,worker,Some(ordinals))};
        result.map_err(|failure|match failure{ModifierReadFailure::Semantic(source)=>Self::semantic(source),ModifierReadFailure::Operational(actual)=>Self::operational(actual)})
    }
}
