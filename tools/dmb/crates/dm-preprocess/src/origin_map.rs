//! Immutable exact source origins compressed into affine line runs.
use crate::Origin;
use std::{path::PathBuf, sync::Arc};
#[derive(Clone, Debug, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
struct Run { first: usize, output: usize, source: usize, count: usize, stride: usize, path: Arc<PathBuf> }
#[derive(Clone, Debug, Default, Eq, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct OriginMap { runs: Arc<[Run]>, len: usize }
impl OriginMap {
    pub fn from_origins(origins: impl IntoIterator<Item=Origin>) -> Self {
        let mut builder=SourceMapBuilder::default();
        for origin in origins { builder.push(origin); }
        builder.finish()
    }
    pub fn validate(&self)->bool {
        let mut first=0;let mut previous_end=0;
        for run in self.runs.iter() {
            if run.first!=first || run.count==0 || run.output==0 || run.source==0 || run.stride>1 || run.output<previous_end {return false;}
            let Some(end)=run.output.checked_add(run.count) else {return false;};
            if run.source.checked_add(run.stride*(run.count-1)).is_none() {return false;}
            let Some(next)=first.checked_add(run.count) else {return false;};
            first=next;previous_end=end;
        }
        first==self.len
    }
    pub fn len(&self)->usize {self.len}
    pub fn is_empty(&self)->bool {self.len==0}
    pub fn resident_bytes(&self)->usize {self.runs.len()*std::mem::size_of::<Run>()}
    pub fn get(&self,index:usize)->Option<Origin> {
        if index>=self.len {return None;}
        let run=self.runs.get(self.runs.partition_point(|run|run.first<=index).checked_sub(1)?)?;
        let delta=index-run.first;Some(Origin{output_line:run.output+delta,source_line:run.source+run.stride*delta,path:Arc::clone(&run.path)})
    }
    pub fn at_line(&self,line:usize)->Option<Origin> {
        let run=self.runs.get(self.runs.partition_point(|run|run.output<=line).checked_sub(1)?)?;
        let delta=line.checked_sub(run.output)?;if delta>=run.count {return None;}
        Some(Origin{output_line:line,source_line:run.source+run.stride*delta,path:Arc::clone(&run.path)})
    }
    pub fn paths(&self)->impl Iterator<Item=&Arc<PathBuf>> { self.runs.iter().map(|run| &run.path) }
    pub fn iter(&self)->impl Iterator<Item=Origin>+'_ {
        self.runs.iter().flat_map(|run|(0..run.count).map(move |delta|Origin{output_line:run.output+delta,source_line:run.source+run.stride*delta,path:Arc::clone(&run.path)}))
    }
}

/// Streaming source-map sink used by preprocessing, replay and persisted inputs.
/// Storage grows with source discontinuities rather than emitted line count.
#[derive(Default)]
pub struct SourceMapBuilder { runs: Vec<Run>, len: usize }
impl SourceMapBuilder {
    pub fn len(&self)->usize {self.len}
    pub fn iter_from(&self,first:usize)->impl Iterator<Item=Origin>+'_ {
        let start=self.runs.partition_point(|run|run.first+run.count<=first);
        self.runs[start..].iter().flat_map(move |run| {
            let begin=first.saturating_sub(run.first).min(run.count);
            (begin..run.count).map(move |delta|Origin{output_line:run.output+delta,source_line:run.source+run.stride*delta,path:Arc::clone(&run.path)})
        })
    }
    pub fn push(&mut self, origin: Origin) {
        if let Some(last)=self.runs.last_mut() {
            let stride=origin.source_line.checked_sub(last.source);
            let next=last.output.checked_add(last.count)==Some(origin.output_line);
            let compatible=if last.count==1 {stride.is_some_and(|delta|delta<=1)} else {last.source.checked_add(last.stride*last.count)==Some(origin.source_line)};
            if next && last.path==origin.path && compatible {
                if last.count==1 {last.stride=stride.unwrap();}
                last.count+=1;self.len+=1;return;
            }
        }
        self.runs.push(Run{first:self.len,output:origin.output_line,source:origin.source_line,count:1,stride:0,path:origin.path});self.len+=1;
    }
    pub fn finish(self)->OriginMap {OriginMap{runs:self.runs.into(),len:self.len}}
}
