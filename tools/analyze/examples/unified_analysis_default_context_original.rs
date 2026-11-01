//! Independent original default environment and complete declaration observations.
//! The native lexer is a transport-only canonical word codec, not an old answer provider.
#[cfg(all(feature="legacy-sem",feature="native-policy"))]
#[path="../fixtures/native-analysis-context/observations.rs"]mod observations;
#[cfg(all(feature="legacy-sem",feature="native-policy"))]
fn main()->Result<(),Box<dyn std::error::Error>>{
 use dreammaker::{lexer::LocatedToken,preprocessor::{DefineMap,Preprocessor}};
 use std::{fmt,path::PathBuf};
 // Token transport must preserve punctuation. pretty_print(false) rewrites
 // braces/semicolons into layout and is intentionally unsuitable for this proof.
 struct Program<'a>(&'a[LocatedToken]);impl fmt::Display for Program<'_>{fn fmt(&self,out:&mut fmt::Formatter<'_>)->fmt::Result{use dreammaker::lexer::{Token,Punctuation};let mut previous=None;for located in self.0{let token=&located.token;if matches!(token,Token::Punct(Punctuation::Newline)){out.write_str("\n")?;previous=None;continue}if previous.is_some_and(|prior|token.separate_from(prior)){out.write_str(" ")?;}write!(out,"{token}")?;previous=Some(token);}Ok(())}}
 let project=std::fs::canonicalize(PathBuf::from(std::env::args().nth(1).ok_or("expected actual context fixture DME")?))?;
 let context=dreammaker::Context::default();let tokens:Vec<_>=Preprocessor::new(&context,project)?.collect();
 if context.errors().iter().any(|error|error.severity()==dreammaker::Severity::Error){return Err(format!("actual original preprocessing errors: {:?}",context.errors()).into())}
 let program=Program(&tokens).to_string();
 let mut parser=dreammaker::parser::Parser::new(&context,dreammaker::indents::IndentProcessor::new(&context,tokens));parser.enable_procs();let tree=parser.parse_object_tree();
 if context.errors().iter().any(|error|error.severity()==dreammaker::Severity::Error){return Err(format!("actual original declaration errors: {:?}",context.errors()).into())}
 let mut types:Vec<_>=tree.iter_types().map(|ty|{let path=if ty.get().path.is_empty(){"/".to_owned()}else{ty.get().path.clone()};let parent=ty.parent_type().map(|parent|if parent.get().path.is_empty(){"/".to_owned()}else{parent.get().path.clone()});(path,parent)}).collect();types.sort();
 println!("OLD_ANALYSIS_DEFAULT_CONTEXT={}",serde_json::json!({"schema":"analysis-default-context-observations-v1","default_macro_count":DefineMap::with_builtins().len(),"types":types,"tokens":observations::tokens(&program)}));Ok(())
}
#[cfg(not(all(feature="legacy-sem",feature="native-policy")))]fn main(){panic!("original context observation requires legacy-sem,native-policy")}
