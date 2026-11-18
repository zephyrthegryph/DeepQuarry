//! Dedicated resident callback request, not a CHECK with discarded policies.
use super::{protocol,transport,full_registry_check,selected_report_wire};
use serde::{Serialize,Deserialize};use std::{error::Error,io};
#[derive(Debug,Serialize,Deserialize)]#[serde(deny_unknown_fields)]pub(super)struct Request{pub(super)actual:full_registry_check::Request}
impl Request{pub(super)fn qualify(&self)->io::Result<()>{self.actual.qualify()?;if !self.actual.selftests||self.actual.cli.is_some()||self.actual.options!=(crate::runner_host::FullRegistryCheckOptions{unused:false,..Default::default()}){return Err(io::Error::new(io::ErrorKind::InvalidInput,"standalone callback request has CHECK-only observations/options"))}Ok(())}}
pub fn run_cli(args:&[String])->Result<bool,Box<dyn Error>>{
 // Reuse actual selector/root/caller/request admission; this namespace is DATA,
 // not an acquisition of the corresponding model or workspace policy inputs.
 let actual=full_registry_check::invocation_selftests(args)?;
 let request=Request{actual};request.qualify()?;let(_,cache)=crate::runner_host::BuildHost::native_registry_check_paths(&request.actual.build)?;
 let selection=dq_analyze::full_registry_check_selection_wire::SelectionBinding::for_selectors_using(&request.actual.selectors,&||super::control::checkpoint())?;
 super::build_admission::validate(&request.actual.build)?;let mut stream=super::connect_generation()?;transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;protocol::send(&mut stream,&protocol::Request::NativeUtility(super::native_utility::Request::StandaloneSelftests(request)))?;
 selected_report_wire::receive_standalone_selftests(&mut stream,&cache,selection)?.publish(&mut io::stdout().lock()).map_err(Into::into)
}
