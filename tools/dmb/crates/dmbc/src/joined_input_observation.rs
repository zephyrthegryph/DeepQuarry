//! Opt-in DATA observation of the actual joined publication closure.
//! Never creates source, producer, admission or parity authority.
use crate::{input_snapshot::InputSnapshot, publish::OutputPair,
    selected_report_spool::{Stage, Verified}};
use dm_preprocess::source_arena_credit::{SourceArenaControlCredit, SourceArenaCredit, SourceArenaWork};
use dq_analyze::selected_exclusions_wire::{Frame, Hex128, Seal, MAX_STREAM};
use serde::Serialize;
use std::{collections::BTreeMap, io::{self, Write}, path::Path, sync::Mutex};

type Consumer = Box<dyn for<'a> FnOnce(Observation<'a>) -> io::Result<()> + Send>;
const SCRATCH:usize=64*1024;

#[derive(Clone,Copy,Serialize)]
pub(crate) struct Binding {
    pub(crate) frame:Frame,
    pub(crate) checker_policy_revision:Hex128,
    pub(crate) roster:&'static str,
    pub(crate) clean:bool,
    pub(crate) diagnostics:Option<Seal>,
    pub(crate) checker:Seal,
    pub(crate) report:Seal,
    pub(crate) analysis_context:Option<crate::policy_request::AnalysisContext>,
}
#[derive(Serialize)]
struct Header<'a> {
    schema:&'static str, kind:&'static str, scope:&'static str,
    full_checker_parity:bool, native_pair:&'a OutputPair,
    project:&'a Path, defines:&'a BTreeMap<String,String>,
    native_engine_identity:Hex128, native_bootstrap_catalog:bool,
    original_initial_environment:&'static str,
    binding:Binding, native_inputs:Seal, report_inputs:Seal,
}
/// Private harness DATA only. All three streams are verified byte spools; the
/// compiler retains both original ledgers around the consumer and revalidates
/// exact contents afterwards. A successful consumer is NOT a parity seal.
pub struct Observation<'a> {
    pub project:&'a Path,
    pub pair:&'a OutputPair,
    /// Exact inherited deadline, never a new oracle allowance.
    pub deadline:std::time::Instant,
    pub(crate) header:Verified,
    pub(crate) native_inputs:Verified,
    pub(crate) report_inputs:Verified,
    // Last: drop files and callback-owned controls before their funding.
    _credit:SourceArenaCredit,
}
struct Pending { native:Stage, report:Stage, header:Stage, consume:Consumer, _credit:SourceArenaCredit }
struct Ready { native:Verified, report:Verified, header:Stage, consume:Consumer, _credit:SourceArenaCredit }
enum State { Pending(Pending), Ready(Ready) }
pub(crate) struct Plan {
    binding:Binding, state:Mutex<Option<State>>,
    context:crate::daemon::control::WorkerContext,
    // Retain the same physical grant until the Plan control itself is gone.
    _credit:SourceArenaControlCredit,
}

fn invalid(message:&'static str)->io::Error{io::Error::new(io::ErrorKind::InvalidData,message)}
fn seal(stream:&Verified)->Seal { Seal { length:stream.length(), hash:Hex128(stream.hash()) } }
fn verify(stage:Stage)->io::Result<Verified>{
    let (verified,())=stage.seal()?.validate(|reader| {
        // Serialization already owns JSON shape. Check all sealed bytes without
        // allocating another decoded ledger, value tree, or full-size buffer.
        io::copy(reader,&mut io::sink()).map(|_|())
    })?;
    Ok(verified)
}
fn encode(value:&impl Serialize,output:&mut impl Write)->io::Result<()> {
    // serde_json preserves its underlying first IO error through this From
    // conversion, unlike Error::other wrapping the diagnostic string.
    serde_json::to_writer(output,value).map_err(io::Error::from)
}
impl Plan {
    /// Called only by the closed FullRegistry host path, before native compile.
    /// The harness owns/funds any heap payload captured by its callback; this
    /// grant pays the actual callback/control allocation and bounded IO scratch.
    pub(crate) fn new<F>(cache:&Path,work:&dyn SourceArenaWork,binding:Binding,consume:F)->io::Result<Self>
    where F:for<'a> FnOnce(Observation<'a>)->io::Result<()> + Send + 'static {
        work.checkpoint()?;
        let context=crate::daemon::control::WorkerContext::capture()
            .ok_or_else(||invalid("observed compound request has no existing operation context"))?;
        let path_bytes=cache.as_os_str().len().checked_mul(8)
            .and_then(|n|n.checked_add(3*256))
            .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
        let bytes=SCRATCH.checked_add(path_bytes).and_then(|n|n.checked_add(std::mem::size_of::<Self>()))
            .and_then(|n|n.checked_add(std::mem::size_of::<Pending>()))
            .and_then(|n|n.checked_add(std::mem::size_of::<F>()))
            .ok_or_else(||io::Error::from(io::ErrorKind::OutOfMemory))?;
        let credit=work.reserve(bytes)?;
        let control=credit.control();
        let pending=Pending { native:Stage::new(cache)?, report:Stage::new(cache)?,
            header:Stage::new(cache)?,consume:Box::new(consume),_credit:credit };
        Ok(Self { binding,state:Mutex::new(Some(State::Pending(pending))),context,_credit:control })
    }
    pub(super) fn with_checkpoints<T>(&self,run:impl FnOnce()->Result<T,Box<dyn std::error::Error>>)
        ->Result<T,Box<dyn std::error::Error>> {
        self.context.with_checkpoint_context(run)
    }
    /// Invoked only after the existing two-role exact barrier has succeeded.
    /// Failure consumes/poisons this single attempt and cannot leave a Ready
    /// partial observation for a retry or later request to borrow.
    pub(super) fn stage(&self,native:&InputSnapshot,report:&InputSnapshot)->io::Result<()> {
        self.context.checkpoint()?;
        let mut state=self.state.lock().map_err(|_|invalid("joined observation state poisoned"))?;
        let Some(State::Pending(mut pending))=state.take() else {
            return Err(invalid("joined observation requires its fresh single attempt"));
        };
        encode(native,&mut pending.native)?;
        encode(report,&mut pending.report)?;
        if pending.native.length().checked_add(pending.report.length()).is_none_or(|n|n>MAX_STREAM){
            return Err(io::Error::new(io::ErrorKind::OutOfMemory,"joined observation exceeds the existing aggregate stream bound"));
        }
        let native=verify(pending.native)?;
        let report=verify(pending.report)?;
        *state=Some(State::Ready(Ready { native,report,header:pending.header,consume:pending.consume,_credit:pending._credit }));
        Ok(())
    }
    /// Pair is supplied only after genuine installation, while the caller still
    /// owns the original native and joined ledgers. No source-reading oracle may
    /// run inside the earlier prepublication freshness callback.
    pub(super) fn published(&self,project:&Path,pair:&OutputPair,defines:&BTreeMap<String,String>,
        engine_identity:u128,bootstrap_catalog:bool)->io::Result<()> {
        self.context.checkpoint()?;
        let ready={
            let mut state=self.state.lock().map_err(|_|invalid("joined observation state poisoned"))?;
            let Some(State::Ready(ready))=state.take() else {return Err(invalid("installed observation lacks both verified input roles"))};
            ready
        };
        let Ready {native,report,mut header,consume,_credit}=ready;
        encode(&Header {schema:"joined-publication-input-observation-v1",kind:"observed_inputs_only",
            scope:"actual native and report inputs at exact publication; no independent parity or no-intervening-change claim",
            full_checker_parity:false,native_pair:pair,project,defines,
            native_engine_identity:Hex128(engine_identity),native_bootstrap_catalog:bootstrap_catalog,
            original_initial_environment:"OriginalChecker0290",binding:self.binding,
            native_inputs:seal(&native),report_inputs:seal(&report)},&mut header)?;
        if native.length().checked_add(report.length()).and_then(|n|n.checked_add(header.length())).is_none_or(|n|n>MAX_STREAM){
            return Err(io::Error::new(io::ErrorKind::OutOfMemory,"joined observation header exceeds aggregate stream bound"));
        }
        let header=verify(header)?;
        let deadline=crate::daemon::control::current_deadline()
            .ok_or_else(||invalid("observed publication lost its original request deadline"))?;
        consume(Observation {project,pair,deadline,header,native_inputs:native,report_inputs:report,_credit})?;
        // Publication masks ordinary request checkpoints. Reuse the captured
        // PREpublication context to enforce the original deadline, not a reset.
        self.context.checkpoint()
    }
}

impl Observation<'_> {
    /// Emit only verified observation DATA. Invoke the independent oracles in
    /// the same callback AFTER this succeeds; the host still owns and checks
    /// both real ledgers before returning qualification success.
    pub fn write_inputs(self,header:&mut impl Write,native:&mut impl Write,report:&mut impl Write)->io::Result<()> {
        let Self {header:head,native_inputs,report_inputs,_credit,..}=self;
        head.publish(header)?;
        native_inputs.publish(native)?;
        report_inputs.publish(report)?;
        drop(_credit);
        Ok(())
    }
}
/// Narrow opt-in harness export. This is the real full-registry BuildHost path,
/// not an arbitrary source endpoint, deserializer, new frontend or CLI mode.
/// Callback executes after pair installation and before exact source recheck.
/// It must bound its external oracle subprocesses to the existing request budget
/// and must not treat before/after equality as no-intervening-change proof.
pub fn with_compiled_full_registry_input_observation<F>(
    host:&mut crate::runner_host::BuildHost,
    prepare:crate::request::BuildRequest,compile:crate::request::BuildRequest,
    full_ci:bool,cbt:bool,compact_checker:bool,observe:F,
    diagnostics:&mut impl Write,checker:&mut impl Write,analyze:&mut impl Write,
)->Result<(crate::request::BuildOutcome,bool),Box<dyn std::error::Error>>
where F:for<'a> FnOnce(Observation<'a>)->io::Result<()> + Send + 'static {
    use crate::daemon::selected_report_wire::CompoundRoster;
    if cbt&&!full_ci{return Err(io::Error::new(io::ErrorKind::InvalidInput,"CBT observation requires the actual CI full-registry profile").into())}
    let roster=if cbt{CompoundRoster::FullRegistryCiCbt}else if full_ci{CompoundRoster::FullRegistryCi}else{CompoundRoster::FullRegistry};
    host.with_compiled_full_registry_observed_using(prepare,compile,roster,compact_checker,observe,
        |staged|staged.publish(diagnostics,checker,analyze))
}

#[cfg(test)]mod tests {
    use super::*;
    #[test]fn snapshot_encoding_preserves_first_writer_io_payload_and_stops(){
        struct Fail(usize);impl Write for Fail {
            fn write(&mut self,_:&[u8])->io::Result<usize>{self.0+=1;Err(io::Error::from_raw_os_error(1450))}
            fn flush(&mut self)->io::Result<()>{panic!("no flush after first write error")}
        }
        let mut writer=Fail(0);let error=encode(&InputSnapshot::new(17),&mut writer).unwrap_err();
        assert_eq!(error.raw_os_error(),Some(1450));assert_eq!(writer.0,1);
    }
    #[test]fn snapshot_encoding_is_existing_exact_snapshot_codec_not_generic_value_roundtrip(){
        let snapshot=InputSnapshot::new(u128::MAX);
        let mut actual=Vec::new();encode(&snapshot,&mut actual).unwrap();
        assert_eq!(actual,serde_json::to_vec(&snapshot).unwrap());
        assert!(std::str::from_utf8(&actual).unwrap().contains(&u128::MAX.to_string()));
    }
}
