//! Immutable actual Original Ifdef methods and global disabled scan, GPL-3.0,
//! Tad Hardesty/SpacemanDMM contributors at0290db5c752fa292f9824521515b603a2afd11dc.
type Location=usize;
#[derive(Debug)]
struct Ifdef {
    location: Location,
    active: bool,
    chain_active: bool,
}

impl Ifdef {
    fn new(location: Location, active: bool) -> Ifdef {
        Ifdef {
            location,
            active,
            chain_active: active,
        }
    }
    fn else_(self, location: Location) -> Ifdef {
        Ifdef {
            location,
            active: !self.chain_active,
            chain_active: true,
        }
    }
    fn else_if(self, location: Location, active: bool) -> Ifdef {
        Ifdef {
            location,
            active: !self.chain_active && active,
            chain_active: self.chain_active || active,
        }
    }
}


struct Owner{ifdef_stack:Vec<Ifdef>}
impl Owner{
    fn is_disabled(&self) -> bool {
        self.ifdef_stack.iter().any(|x| !x.active)
    }
}

fn project(frame:Ifdef)->(usize,bool,bool){(frame.location,frame.active,frame.chain_active)}
fn input(frame:(usize,bool,bool))->Ifdef{Ifdef{location:frame.0,active:frame.1,chain_active:frame.2}}
pub fn new_frame(origin:usize,active:bool)->(usize,bool,bool){project(Ifdef::new(origin,active))}
pub fn else_frame(old:(usize,bool,bool),origin:usize)->(usize,bool,bool){project(input(old).else_(origin))}
pub fn elif_frame(old:(usize,bool,bool),origin:usize,active:bool)->(usize,bool,bool){project(input(old).else_if(origin,active))}
pub fn disabled(frames:&[(usize,bool,bool)])->bool{Owner{ifdef_stack:frames.iter().copied().map(input).collect()}.is_disabled()}
