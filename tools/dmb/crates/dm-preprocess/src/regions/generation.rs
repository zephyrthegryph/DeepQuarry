//! Restricted declaration-generation input. This is not a compiler plan and
//! cannot issue a semantic/source/body/read completeness receipt.
use super::*;
use std::io;

/// Paths whose absence was probed by the caller's actual input recorder. The
/// caller also owns the permitted-output registry. Generic callbacks provide
/// data only; this value grants no source authority.
pub struct GenerationOmissions { paths: BTreeSet<PathBuf> }
impl GenerationOmissions {
    pub fn probe(
        permitted: impl IntoIterator<Item=PathBuf>,
        absent: &mut dyn FnMut(&Path)->io::Result<bool>,
        admit: &mut dyn FnMut(usize)->io::Result<()>,
    )->io::Result<Self> {
        let mut paths=BTreeSet::new();
        let mut count=0usize;
        for path in permitted {
            count=count.checked_add(1).ok_or_else(||io::Error::other("generation output count overflow"))?;
            if count>64 { return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation output registry exceeds 64 paths")); }
            if !path.is_absolute() || path.extension().is_none_or(|e| e!="dm") {
                return Err(io::Error::new(io::ErrorKind::InvalidInput,"generation output must be an absolute DM path"));
            }
            admit(path.as_os_str().len().checked_mul(8).and_then(|n|n.checked_add(1024)).ok_or_else(||io::Error::other("generation output path admission overflow"))?)?;
            let path=canonical_path(&path);
            if absent(&path)? {
                admit(1024usize.checked_add(path.as_os_str().len().checked_mul(8).ok_or_else(||io::Error::other("generation output width overflow"))?).ok_or_else(||io::Error::other("generation output admission overflow"))?)?;
                paths.insert(path);
            }
        }
        admit(0)?;
        Ok(Self{paths})
    }
    pub fn paths(&self)->impl Iterator<Item=&Path> { self.paths.iter().map(PathBuf::as_path) }
}

/// SAME native directive algorithm with explicit absent-output omissions. No
/// public conversion, Deref or plan getter allows this to masquerade as a normal
/// compiler plan. Ordinary preprocessing does not select this mode.
pub struct GenerationDirectivePlan { plan: DirectivePlan, omissions: GenerationOmissions }
impl GenerationDirectivePlan {
    pub fn prepare<P:SourceProvider>(project:&Path,provider:&P,defines:&BTreeMap<String,String>,omissions:GenerationOmissions,read:&dyn Fn(&Path)->io::Result<Option<Arc<prepared_source::PreparedSource>>>)->io::Result<Self> {
        let plan=directives::plan_generation(project,provider,defines,&omissions.paths,read)?;
        Ok(Self{plan,omissions})
    }
    /// Actual original acquisitions of this restricted directive traversal.
    /// Borrowed source data only; this does not expose a compiler DirectivePlan.
    /// Explicitly omitted NotFound outputs remain directive occurrences and
    /// negative dependencies, but have no source/acquisition to loan. Exclude
    /// ONLY those private issued omissions and actual typed NonText rows; all
    /// other missing leases stay None. NonText items/dependencies remain intact.
    pub fn original_sources(&self)->GenerationOriginalSources<'_>{GenerationOriginalSources{occurrences:self.plan.occurrences.iter().enumerate(),acquisitions:&self.plan.source_acquisitions,omitted:&self.omissions.paths}}
    pub fn root_source(&self)->Option<&Path>{self.plan.occurrences.first().map(|occurrence|occurrence.path.as_path())}
    /// Borrowed source geometry of this explicitly incomplete traversal.
    pub fn initial_environment(&self)->crate::InitialEnvironment{self.plan.initial_environment}
    pub fn source_geometry(&self)->SourcePlanGeometry<'_>{self.plan.source_geometry()}
    pub fn diagnostics(&self)->&[Diagnostic] { &self.plan.diagnostics }
    pub fn omissions(&self)->impl Iterator<Item=&Path> { self.omissions.paths() }
    /// Actual skipped include occurrences, not unused permitted negatives. DATA only.
    pub fn encountered_omissions(&self)->impl Iterator<Item=&Path>{self.plan.occurrences.iter().filter(|row|self.omissions.paths.contains(row.path.as_path())).map(|row|row.path.as_path())}
    /// Text is only for generation-declaration parsing. It carries no complete
    /// original-input receipt, even when preprocessing has no diagnostics.
    pub fn expand(&self,executor:&dm_exec::BuildExecutor)->ExpandedRegions {
        expand_regions_text_with_executor(&self.plan,executor,None)
    }
}

#[cfg(test)] mod tests {
    use super::*;
    struct Files(BTreeMap<PathBuf,String>);
    impl SourceProvider for Files {
        fn read(&self,path:&Path)->Result<String,String>{self.0.get(path).cloned().ok_or_else(||"actual missing input".into())}
    }
    #[test] fn generation_omits_only_explicit_negative_outputs_without_fabricating_sources(){
        let root=std::env::current_dir().unwrap().join("generation-only-fixture");
        let project=root.join("main.dme");let generated=root.join("generated.dm");
        let files=Files(BTreeMap::from([(project.clone(),"#include \"generated.dm\"\n#include \"map.dmm\"\n#include \"skin.dmf\"\n#include \"actual.dm\"\n/datum/probe\n    var/value=7\n".into()),(root.join("actual.dm"),"/datum/actual\n".into())]));
        let omissions=GenerationOmissions::probe([generated.clone()],&mut |p|Ok(!files.0.contains_key(p)),&mut |_|Ok(())).unwrap();
        let read=|p:&Path|Ok(files.0.get(p).map(|s|prepared_source::shared_prepared(s.clone().into())));
        let plan=GenerationDirectivePlan::prepare(&project,&files,&BTreeMap::new(),omissions,&read).unwrap();
        assert!(plan.diagnostics().is_empty());assert_eq!(plan.omissions().collect::<Vec<_>>(),[generated.as_path()]);
        assert!(!plan.plan.source_texts.contains_key(&generated));assert!(!plan.plan.source_acquisitions.contains_key(&1));
        assert_eq!(plan.original_sources().map(|(path,_)|path).collect::<Vec<_>>(),[project.as_path(),root.join("actual.dm").as_path()]);
        assert!(plan.original_sources().all(|(_,lease)|lease.is_none()),"an unacquired non-omitted source is NOT filtered or fabricated");
        assert_eq!(plan.plan.items.iter().filter(|item|matches!(item,OrderedItem::NonText{..})).count(),2);
        assert_eq!(plan.plan.occurrences.iter().filter_map(IncludeOccurrence::non_text_kind).collect::<Vec<_>>(),[NonTextKind::Map,NonTextKind::Skin]);
        assert!(plan.plan.dependencies.contains(&root.join("map.dmm"))&&plan.plan.dependencies.contains(&root.join("skin.dmf")));
        assert!(!plan_regions(&project,&files,&BTreeMap::new()).diagnostics.is_empty());
        let denied=GenerationOmissions::probe([root.join("other.dm")],&mut |_|Ok(true),&mut |_|Ok(())).unwrap();
        assert!(!GenerationDirectivePlan::prepare(&project,&files,&BTreeMap::new(),denied,&read).unwrap().diagnostics().is_empty());
    }
    #[test] fn generation_negative_probe_preserves_actual_io_and_allocation_failure(){
        let root=std::env::current_dir().unwrap().join("generation-only-fixture");
        let error=GenerationOmissions::probe([root.join("generated.dm")],&mut |_|Err(io::Error::from_raw_os_error(1450)),&mut |_|Ok(())).err().unwrap();
        assert_eq!(error.raw_os_error(),Some(1450));
        let error=GenerationOmissions::probe([root.join("generated.dm")],&mut |_|Ok(true),&mut |_|Err(io::ErrorKind::OutOfMemory.into())).err().unwrap();
        assert_eq!(error.kind(),io::ErrorKind::OutOfMemory);
    }
}

/// Borrowed iterator over the actual issued code-source domain. No allocation,
/// source owner or compiler-completeness receipt is created by this adapter.
pub struct GenerationOriginalSources<'a>{occurrences:std::iter::Enumerate<std::slice::Iter<'a,IncludeOccurrence>>,acquisitions:&'a BTreeMap<usize,crate::SourceAcquisitionLease>,omitted:&'a BTreeSet<PathBuf>}
impl<'a> Iterator for GenerationOriginalSources<'a>{type Item=(&'a Path,Option<&'a crate::SourceAcquisitionLease>);fn next(&mut self)->Option<Self::Item>{for(index,occurrence)in self.occurrences.by_ref(){if occurrence.non_text_kind().is_some()||self.omitted.contains(occurrence.path.as_ref()){continue}return Some((occurrence.path.as_path(),self.acquisitions.get(&index)))}None}}
