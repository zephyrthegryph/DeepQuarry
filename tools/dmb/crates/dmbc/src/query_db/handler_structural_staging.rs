//! Private spilled Handler structural rows. Source/ALLOW authority stays with
//! the partial closure and independently admitted full report owner.
use super::{StructuralData,StructuralFinding};
use crate::{query_db::{NativeQueryOwnerIdentity,QueryDb},selected_report_spool::{Sealed,Stage}};
use dq_analyze::captured_generator_budget::Budget;
use std::{io::{self,Read,Write},path::Path,sync::Arc};

pub(crate) struct StagedRows {
    sealed: Sealed,
    queries: NativeQueryOwnerIdentity,
    issuance: u64,
    model_present: bool,
}
fn invalid(message: &'static str) -> io::Error { io::Error::new(io::ErrorKind::InvalidData,message) }

fn put_u32(output:&mut impl Write,value:u32)->io::Result<()>{
    output.write_all(&value.to_le_bytes())
}
fn get_u32(input:&mut dyn Read)->io::Result<u32>{
    let mut bytes=[0;4];
    input.read_exact(&mut bytes)?;
    Ok(u32::from_le_bytes(bytes))
}
fn put_string(output:&mut impl Write,text:&str)->io::Result<()>{
    put_u32(output,u32::try_from(text.len()).map_err(|_|invalid("handler staged string exceeds wire width"))?)?;
    output.write_all(text.as_bytes())
}
impl StagedRows {
    pub(super) fn write(cache:&Path,queries:NativeQueryOwnerIdentity,issuance:u64,model_present:bool,data:&StructuralData)->io::Result<Self>{
        if data.issuance!=issuance || (!model_present && !data.rows().is_empty()){
            return Err(invalid("handler staged rows differ from the actual partial disposition"));
        }
        let sealed=write_rows(cache,data.rows())?;
        Ok(Self{sealed,queries,issuance,model_present})
    }

    /// Final caller must separately authenticate its retained partial closure
    /// against the current full capture before calling this one-shot reader.
    pub(crate) fn replay(
        self,queries:&QueryDb,issuance:u64,model_present:bool,budget:&Arc<Budget>,
        visit:impl FnMut(&'static str,&str,u32,&str)->io::Result<()>,
    )->io::Result<()>{
        if !self.queries.matches(queries)||self.issuance!=issuance||self.model_present!=model_present{
            return Err(invalid("handler staged rows belong to another partial producer"));
        }
        replay_rows(self.sealed,budget,visit)
    }
}

fn write_rows(cache:&Path,rows:&[StructuralFinding])->io::Result<Sealed>{
    let mut stage=Stage::new(cache)?;
    put_u32(&mut stage,u32::try_from(rows.len()).map_err(|_|invalid("handler staged row count exceeds wire width"))?)?;
    for row in rows{
        let tag=match row.rule{
            "context_escape"=>0,
            "act_try_unpaired"=>1,
            _=>return Err(invalid("handler staged row has unknown structural rule")),
        };
        stage.write_all(&[tag])?;
        put_u32(&mut stage,row.line)?;
        put_string(&mut stage,&row.relative)?;
        put_string(&mut stage,&row.message)?;
    }
    stage.seal()
}

fn replay_rows(sealed:Sealed,budget:&Arc<Budget>,mut visit:impl FnMut(&'static str,&str,u32,&str)->io::Result<()>)->io::Result<()>{
    let scratch=Budget::scoped_temporaries(budget).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
    let (_,())=sealed.validate(|input|{
        let count=get_u32(input)?;
        let mut bytes=Vec::new();
        for _ in 0..count{
            crate::daemon::control::checkpoint()?;
            let mut tag=[0];
            input.read_exact(&mut tag)?;
            let rule=match tag[0]{
                0=>"context_escape",
                1=>"act_try_unpaired",
                _=>return Err(invalid("handler staged row has unknown structural rule")),
            };
            let line=get_u32(input)?;
            let path_len=get_u32(input)? as usize;
            fill(input,&mut bytes,0,path_len,&scratch)?;
            let message_len=get_u32(input)? as usize;
            fill(input,&mut bytes,path_len,message_len,&scratch)?;
            let path=std::str::from_utf8(&bytes[..path_len]).map_err(|_|invalid("handler staged path is not UTF8"))?;
            let message=std::str::from_utf8(&bytes[path_len..]).map_err(|_|invalid("handler staged message is not UTF8"))?;
            visit(rule,path,line,message)?;
        }
        Ok(())
    })?;
    Ok(())
}
fn fill(input:&mut dyn Read,bytes:&mut Vec<u8>,start:usize,len:usize,budget:&Budget)->io::Result<()>{
    let end=start.checked_add(len).filter(|&n|n as u64<=dq_analyze::selected_exclusions_wire::MAX_STREAM)
        .ok_or_else(||invalid("handler staged row exceeds existing stream bound"))?;
    if end>bytes.capacity(){
        let capacity=end.checked_next_power_of_two().unwrap_or(end);
        budget.charge(capacity).map_err(|m|io::Error::new(io::ErrorKind::OutOfMemory,m))?;
        bytes.try_reserve_exact(capacity-bytes.len()).map_err(|error|io::Error::new(io::ErrorKind::OutOfMemory,error))?;
        if bytes.capacity()!=capacity{return Err(invalid("handler replay capacity differs from admission"))}
    }
    bytes.resize(end,0);
    input.read_exact(&mut bytes[start..])
}

#[cfg(test)]
mod tests{
    use super::*;
    #[test]
    fn spill_preserves_original_row_order_and_replay_releases_scratch(){
        let root=crate::test_scratch::dir("handler-spilled-structural-rows");
        let rows=vec![
            StructuralFinding{rule:"context_escape",relative:"code/z.dm".into(),line:99,message:"escaped Æ".into()},
            StructuralFinding{rule:"act_try_unpaired",relative:"code/a.dm".into(),line:7,message:"unpaired".into()},
            StructuralFinding{rule:"context_escape",relative:"code/z.dm".into(),line:99,message:"escaped Æ".into()},
        ];
        let sealed=write_rows(&root,&rows).unwrap();
        let budget=Budget::new(4096).unwrap();
        let before=budget.used();
        let mut index=0;
        replay_rows(sealed,&budget,|rule,path,line,message|{
            let row=&rows[index];index+=1;
            assert_eq!((rule,path,line,message),(row.rule,row.relative.as_str(),row.line,row.message.as_str()));
            Ok(())
        }).unwrap();
        assert_eq!(index,rows.len());
        assert_eq!(budget.used()-before,std::mem::size_of::<Budget>()+2*std::mem::size_of::<usize>());
    }
    #[test]
    fn empty_result_is_sealed_and_foreign_owner_cannot_replay(){
        let root=crate::test_scratch::dir("handler-spilled-structural-foreign");
        let owner=QueryDb::default();let other=QueryDb::default();
        let data=StructuralData{issuance:17,rows:Vec::new()};
        let budget=Budget::new(4096).unwrap();
        let stage=StagedRows::write(&root,owner.native_query_owner_identity(),17,false,&data).unwrap();
        assert!(stage.replay(&other,17,false,&budget,|_,_,_,_|panic!("foreign rows")).is_err());
        let stage=StagedRows::write(&root,owner.native_query_owner_identity(),17,false,&data).unwrap();
        assert!(stage.replay(&owner,18,false,&budget,|_,_,_,_|panic!("another issuance")).is_err());
        let stage=StagedRows::write(&root,owner.native_query_owner_identity(),17,false,&data).unwrap();
        assert!(stage.replay(&owner,17,true,&budget,|_,_,_,_|panic!("another model disposition")).is_err());
        let stage=StagedRows::write(&root,owner.native_query_owner_identity(),17,false,&data).unwrap();
        stage.replay(&owner,17,false,&budget,|_,_,_,_|panic!("empty rows")).unwrap();
    }
}
