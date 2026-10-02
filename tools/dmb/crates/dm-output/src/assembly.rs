//! One typed assembly contract for decoded and addressed physical images.
use byond_dmb::dmb::*;
use std::io;
macro_rules! sections {
    ($macro:ident) => {$macro! {
        header,header_mut,Header; dimensions,dimensions_mut,[u16;3]; grid,grid_mut,Vec<GridRun>;
        classes,classes_mut,Vec<Class>; mobs,mobs_mut,Vec<MobType>; strings,strings_mut,Vec<DmString>;

        variable_footer,variable_footer_mut,u32; proc_references,proc_references_mut,Vec<u32>;
        instances,instances_mut,Vec<Instance>; map_objects,map_objects_mut,Vec<MapObject>;
        world,world_mut,World; resources,resources_mut,Vec<ResourceRef>;
    }};
}
macro_rules! declare {($( $get:ident,$set:ident,$ty:ty; )*)=>{$(fn $get(&self)->&$ty;fn $set(&mut self)->&mut $ty;)*};}
macro_rules! native {($( $get:ident,$set:ident,$ty:ty; )*)=>{$(fn $get(&self)->&$ty {&self.$get}fn $set(&mut self)->&mut $ty {&mut self.$get})*};}
macro_rules! physical {($( $get:ident,$set:ident,$ty:ty; )*)=>{$(fn $get(&self)->&$ty {&self.metadata.$get}fn $set(&mut self)->&mut $ty {&mut self.metadata.$get})*};}
pub trait AssemblyImage {
    sections!(declare);
    fn proc_count(&self)->usize;
    fn proc(&self,index:usize)->io::Result<Proc>;
    fn append_proc(&mut self,row:Proc)->io::Result<u32>;
    fn replace_proc(&mut self,index:usize,row:Proc)->io::Result<()>;
    fn variable_count(&self)->usize;
    fn variable(&self,index:usize)->io::Result<Variable>;
    fn append_variable(&mut self,row:Variable)->io::Result<u32>;
    fn replace_variable(&mut self,index:usize,row:Variable)->io::Result<()>;
    fn proc_range(&self,start:usize,end:usize)->io::Result<Vec<Proc>> {
        if start>end||end>self.proc_count()||end-start>1024 {return Err(io::Error::new(io::ErrorKind::InvalidInput,"procedure row range exceeds bound"));}
        (start..end).map(|index|self.proc(index)).collect()
    }
    fn variable_range(&self,start:usize,end:usize)->io::Result<Vec<Variable>> {
        if start>end||end>self.variable_count()||end-start>1024 {return Err(io::Error::new(io::ErrorKind::InvalidInput,"variable row range exceeds bound"));}
        (start..end).map(|index|self.variable(index)).collect()
    }
    fn list_count(&self)->usize;
    fn list_words(&self,id:u32)->io::Result<ListWords>;
    fn resident_list(&self,id:u32)->Option<&ListWords>;
    fn list_mut(&mut self,id:u32)->io::Result<&mut ListWords>;
    fn append_list(&mut self,words:ListWords)->io::Result<u32>;
    fn append_shared_list(&mut self,words:std::sync::Arc<[u32]>)->io::Result<u32> {self.append_list(words.into())}
    fn append_code_handle(&mut self,_handle:crate::wire_image::VerifiedCodeHandle)->io::Result<u32> {
        Err(io::Error::new(io::ErrorKind::Unsupported,"native assembly requires materialized code"))
    }
    fn relink_code_handle(&self,_handle:&crate::wire_image::VerifiedCodeHandle,_plan:&crate::wire_relocation::RelocationPlan)->io::Result<crate::wire_image::VerifiedCodeHandle> {
        Err(io::Error::new(io::ErrorKind::Unsupported,"native assembly requires materialized code"))
    }
    fn allocation_counts(&self)->Option<crate::object_directory::AllocationCounts> {Some(crate::object_directory::AllocationCounts {
        strings:self.strings().len().try_into().ok()?,variables:self.variable_count().try_into().ok()?,lists:self.list_count().try_into().ok()?,
        procedures:self.proc_count().try_into().ok()?,references:self.proc_references().len().try_into().ok()?,instances:self.instances().len().try_into().ok()?,
    })}
    fn validate_references_cached(&self,cache:&mut ReferenceValidationCache)->io::Result<()>;
    fn string(&self,id:u32)->Option<&[u8]> {self.strings().get(id as usize).map(|string|string.data.as_slice())}
    fn reserve_proc_sentinel(&mut self)->io::Result<()> {
        if self.proc_count()==0xffff {self.append_proc(Proc {strings:[0xffff;4],source_parameter:255,source_kind:0,flags:4,extended_flags:None,code_locals_args:[0xffff;3]})?;}Ok(())
    }
    fn promote_object_ids(&mut self) {
        if [self.classes().len(),self.mobs().len(),self.strings().len(),self.list_count(),self.proc_count(),self.variable_count(),
            self.proc_references().len(),self.instances().len(),self.map_objects().len(),self.resources().len()].into_iter().any(|count|count>u16::MAX as usize) {
            self.header_mut().flags|=0x4000_0000;
        }
    }
    fn class_variable_declarations(&self,index:usize)->io::Result<Option<Vec<(u32,u32)>>> {
        let Some(class)=self.classes().get(index) else {return Ok(None);};let id=class.defining_variable_list_id();if id==0xffff {return Ok(None);}
        let words=self.list_words(id)?;if words.len()%2!=0 {return Err(io::Error::new(io::ErrorKind::InvalidData,"malformed class declaration list"));}
        Ok(Some(words.chunks_exact(2).map(|pair|(pair[0],pair[1])).collect()))
    }
    fn class_initial_values(&self,index:usize)->io::Result<Option<Vec<ClassInitialValue>>> {
        let Some(class)=self.classes().get(index) else {return Ok(None);};let id=class.initialized_variable_list_id();if id==0xffff {return Ok(None);}
        let words=self.list_words(id)?;let mut values=Vec::new();let mut at=0;
        while at<words.len() {let (value,len)=byond_dmb::operands::Value::decode(&words[at+1..]).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("malformed tagged value: {error:?}")))?;
            values.push(ClassInitialValue {variable_id:words[at],value});at+=len+1;}
        Ok(Some(values))
    }
    fn class_builtin_overrides(&self,index:usize)->io::Result<Option<Vec<ClassBuiltinOverride>>> {
        let Some(class)=self.classes().get(index) else {return Ok(None);};let id=class.overriding_variable_list_id();if id==0xffff {return Ok(None);}
        let words=self.list_words(id)?;let mut values=Vec::new();let mut at=0;
        while at<words.len() {let (value,len)=byond_dmb::operands::Value::decode(&words[at+1..]).map_err(|error|io::Error::new(io::ErrorKind::InvalidData,format!("malformed tagged value: {error:?}")))?;
            values.push(ClassBuiltinOverride {name_string_id:words[at],value});at+=len+1;}
        Ok(Some(values))
    }
}
impl AssemblyImage for Dmb {
    sections!(native);
    fn proc_count(&self)->usize {self.procs.len()}
    fn proc(&self,index:usize)->io::Result<Proc> {self.procs.get(index).cloned().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"procedure row missing"))}
    fn append_proc(&mut self,row:Proc)->io::Result<u32> {let index=u32::try_from(self.procs.len()).map_err(io::Error::other)?;self.procs.push(row);self.promote_object_ids();Ok(index)}
    fn replace_proc(&mut self,index:usize,row:Proc)->io::Result<()> {*self.procs.get_mut(index).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"procedure row missing"))?=row;Ok(())}
    fn variable_count(&self)->usize {self.variables.len()}
    fn variable(&self,index:usize)->io::Result<Variable> {self.variables.get(index).cloned().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"variable row missing"))}
    fn append_variable(&mut self,row:Variable)->io::Result<u32> {let index=u32::try_from(self.variables.len()).map_err(io::Error::other)?;self.variables.push(row);self.promote_object_ids();Ok(index)}
    fn replace_variable(&mut self,index:usize,row:Variable)->io::Result<()> {*self.variables.get_mut(index).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"variable row missing"))?=row;Ok(())}

    fn list_count(&self)->usize {self.lists.len()}
    fn list_words(&self,id:u32)->io::Result<ListWords> {self.lists.get(id as usize).cloned().ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"list ID out of range"))}
    fn resident_list(&self,id:u32)->Option<&ListWords> {self.lists.get(id as usize)}
    fn list_mut(&mut self,id:u32)->io::Result<&mut ListWords> {self.lists.get_mut(id as usize).ok_or_else(||io::Error::new(io::ErrorKind::InvalidData,"list ID out of range"))}
    fn append_list(&mut self,words:ListWords)->io::Result<u32> {if self.lists.len()==0xffff {self.lists.push(Vec::new());}
        let id=u32::try_from(self.lists.len()).map_err(io::Error::other)?;self.lists.push(words);self.promote_object_ids();Ok(id)}
    fn validate_references_cached(&self,cache:&mut ReferenceValidationCache)->io::Result<()> {self.validate_references_incremental(cache)}
}
impl AssemblyImage for crate::wire_image::WireImageBuilder {
    sections!(physical);
    fn proc_count(&self)->usize {self.procs.len()}
    fn proc(&self,index:usize)->io::Result<Proc> {self.procs.get(index)}
    fn append_proc(&mut self,row:Proc)->io::Result<u32> {let index=self.procs.append(row)?;self.promote_object_ids();Ok(index)}
    fn replace_proc(&mut self,index:usize,row:Proc)->io::Result<()> {self.procs.replace(index,row)}
    fn variable_count(&self)->usize {self.variables.len()}
    fn variable(&self,index:usize)->io::Result<Variable> {self.variables.get(index)}
    fn append_variable(&mut self,row:Variable)->io::Result<u32> {let index=self.variables.append(row)?;self.promote_object_ids();Ok(index)}
    fn replace_variable(&mut self,index:usize,row:Variable)->io::Result<()> {self.variables.replace(index,row)}

    fn list_count(&self)->usize {self.lists.len()}
    fn list_words(&self,id:u32)->io::Result<ListWords> {self.lists.read_words(id as usize)}
    fn resident_list(&self,id:u32)->Option<&ListWords> {self.lists.resident_words(id as usize)}
    fn list_mut(&mut self,id:u32)->io::Result<&mut ListWords> {self.lists.materialize_mut(id as usize)}
    fn append_list(&mut self,words:ListWords)->io::Result<u32> {if self.lists.len()==0xffff {self.lists.append_resident(Vec::new());}
        let id=u32::try_from(self.lists.append_resident(words)).map_err(io::Error::other)?;self.promote_object_ids();Ok(id)}
    fn validate_references_cached(&self,cache:&mut ReferenceValidationCache)->io::Result<()> {self.metadata.validate_physical_sources(&self.lists,self,cache)}
    fn append_code_handle(&mut self,handle:crate::wire_image::VerifiedCodeHandle)->io::Result<u32> {self.append_verified_code(handle)}
    fn relink_code_handle(&self,handle:&crate::wire_image::VerifiedCodeHandle,plan:&crate::wire_relocation::RelocationPlan)->io::Result<crate::wire_image::VerifiedCodeHandle> {self.relink_code(handle,plan)}
}
