//! Operation-local initializer evaluator transport, never a classification
//! issue/artifact/cache key. SourceError/InvalidNameof remain Evaluation values.
#[derive(Debug)]
pub enum InitializerFailure {
    Unsupported(String),
    Operational(std::io::Error),
}
impl From<String> for InitializerFailure {fn from(value:String)->Self{Self::Unsupported(value)}}
impl From<&str> for InitializerFailure {fn from(value:&str)->Self{Self::Unsupported(value.into())}}
impl std::fmt::Display for InitializerFailure {
    fn fmt(&self,f:&mut std::fmt::Formatter<'_>)->std::fmt::Result{
        match self{Self::Unsupported(value)=>value.fmt(f),Self::Operational(error)=>error.fmt(f)}
    }
}
impl std::error::Error for InitializerFailure {
    fn source(&self)->Option<&(dyn std::error::Error+'static)>{match self{Self::Operational(error)=>Some(error),Self::Unsupported(_)=>None}}
}
impl InitializerFailure {
    pub fn into_operational(self)->Result<std::io::Error,Self>{match self{Self::Operational(error)=>Ok(error),other=>Err(other)}}
    pub fn operational(&self)->Option<&std::io::Error>{match self{Self::Operational(error)=>Some(error),Self::Unsupported(_)=>None}}
}
