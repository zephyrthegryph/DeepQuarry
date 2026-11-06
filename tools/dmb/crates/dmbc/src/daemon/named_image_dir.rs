//! Closed resident request for one named native Analyze policy.
use super::{protocol, selected_report_wire, transport};
use crate::request::{BuildCommand,BuildRequest};
use serde::{Deserialize,Serialize};
use std::{error::Error,fs::File,io::{self,Read},path::{Path,PathBuf}};

const MAX_REQUEST:u64=64*1024;

#[derive(Deserialize,Serialize)]
#[serde(deny_unknown_fields)]
pub(super) struct Request {
    workspace_root:PathBuf,
    cache_root:PathBuf,
    timeout_seconds:u16,
}

impl Request {
    /// Construct a fixed scheduler envelope. There is no wire BuildRequest,
    /// generic policy/role switch, result path, or alternate input context.
    pub(super) fn prepare_request(&self)->io::Result<BuildRequest>{
        crate::request::validate_timeout_seconds(Some(self.timeout_seconds))?;
        if !self.workspace_root.is_absolute()||!self.cache_root.is_absolute(){
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir requires caller-absolute workspace and cache paths"));
        }
        if self.workspace_root.as_os_str().len().checked_add(self.cache_root.as_os_str().len())
            .is_none_or(|n|n>MAX_REQUEST as usize-128){
            return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir paths exceed the request bound"));
        }
        Ok(BuildRequest{
            command:BuildCommand::PrepareQuery,source_questions:None,diagnostic_declarations:false,
            timeout_seconds:Some(self.timeout_seconds),policy_inputs:None,project:self.workspace_root.join("deepquarry.dme"),
            defines:Default::default(),workers:1,engine_template:None,bootstrap_catalog:false,
            progress_enabled:false,output_store:None,exact_inputs:true,no_cache:false,cache_root:Some(self.cache_root.clone()),
            record_inputs:None,replay_inputs:None,artifact_directory:None,no_daemon:false,trace_path:None,warnings:Default::default(),
        })
    }
}

pub(super) fn canonical_roots(root:&Path,cache:&Path)->io::Result<(PathBuf,PathBuf)>{
    let root=std::fs::canonicalize(root)?;
    let cache=std::fs::canonicalize(cache)?;
    if !root.is_dir()||!cache.is_dir()||cache.starts_with(&root){
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir cache must be an existing directory outside the workspace"));
    }
    Ok((root,cache))
}

pub fn run_file(path:&Path)->Result<bool,Box<dyn Error>>{
    let mut bytes=Vec::new();
    File::open(path)?.take(MAX_REQUEST+1).read_to_end(&mut bytes)?;
    if bytes.len() as u64>MAX_REQUEST{
        return Err(io::Error::new(io::ErrorKind::InvalidInput,"named ImageDir request exceeds its control bound").into());
    }
    let request:Request=serde_json::from_slice(&bytes)?;
    drop(bytes);
    let build=request.prepare_request()?;
    let root=build.project.parent().ok_or_else(||io::Error::other("named ImageDir workspace absent"))?;
    let cache=build.cache_root.as_deref().ok_or_else(||io::Error::other("named ImageDir cache absent"))?;
    let (_,cache)=canonical_roots(root,cache)?;
    let mut stream=super::connect_generation()?;
    transport::set_timeout(&mut stream,transport::BUILD_DEADLINE)?;
    protocol::send(&mut stream,&protocol::Request::NamedImageDir(request))?;
    Ok(selected_report_wire::receive_named_image_dir(&mut stream,&cache)?.publish(&mut io::stdout().lock())?)
}
