//! Immutable exact source origins compressed into affine line runs.
use crate::Origin;
use std::{path::PathBuf, sync::Arc};
#[derive(Clone, Debug, Eq, PartialEq)]
struct Run { first: usize, output: usize, source: usize, count: usize, stride: usize, path: Arc<PathBuf> }
#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct OriginMap { runs: Arc<[Run]>, len: usize }
impl OriginMap {
    pub fn from_origins(origins: impl IntoIterator<Item=Origin>) -> Self {
        let mut runs: Vec<Run> = Vec::new(); let mut len=0;
        for origin in origins {
            if let Some(last)=runs.last_mut() {
                let stride=origin.source_line.checked_sub(last.source);
                let next=last.output.checked_add(last.count)==Some(origin.output_line);
                let compatible=if last.count==1 { stride.is_some_and(|delta|delta<=1) } else { last.source.checked_add(last.stride*last.count)==Some(origin.source_line) };
                if next && last.path==origin.path && compatible {
                    if last.count==1 { last.stride=stride.unwrap(); }
                    last.count+=1;len+=1;continue;
                }
            }
            runs.push(Run{first:len,output:origin.output_line,source:origin.source_line,count:1,stride:0,path:origin.path});len+=1;
        }
        Self{runs:runs.into(),len}
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
