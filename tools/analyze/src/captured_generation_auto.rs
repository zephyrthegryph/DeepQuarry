//! Auto generation from purpose-specific native owners, not a complete source.
//! The host must authenticate its requested names, native Q/Db/current recorder,
//! actual fixed configuration read and exhausted CODE/CLI-test original scopes.
//! This returns only staged output DATA; no receipt, cache or installer exists.
use crate::{captured_generator_budget::Budget,captured_reactive_reads::Failure};use std::{io,path::Path,sync::Arc,collections::{BTreeSet,HashMap}};
pub fn generate_from_questions(questions:&dm_tree::frontend::GenerationNativeQuestions,root:&Path,pages:&dyn crate::reactive_raw_policy_pages::RawPolicyPages,order:&HashMap<String,usize>,configuration:&crate::captured_raw_file::Config,tests:&BTreeSet<String>,budget:&Arc<Budget>,poll:&dyn Fn()->io::Result<()>)->Result<crate::sparse_slots_policy::Output,Failure>{
 use crate::captured_generation_questions::{self as common,Generator,Generated};let mut output=None;common::with_generators(questions,root,pages,order,Some(configuration),tests,&[Generator::AutoTracked],budget,poll,&mut|name,value|{if name!=Generator::AutoTracked||output.is_some(){return Err("Auto question callback repeated or changed role".into())}let Generated::Single(value)=value else{return Err("Auto question callback returned another output form".into())};output=Some(value);Ok(())})?;output.ok_or_else(||"Auto question callback omitted".into())
}
