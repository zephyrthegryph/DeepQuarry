//! Shared mapped-network topology and route edits. This module has no browser or BYOND dependency.

use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashSet};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct Point { pub x: i32, pub y: i32, pub z: i32 }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct Tile { pub x: i32, pub y: i32, pub z: i32, pub atoms: Vec<String> }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct RouteInput {
    pub layer: String,
    pub atom: String,
    pub points: Vec<Point>,
    pub tiles: Vec<Tile>,
    #[serde(default)] pub anchor_port: Option<i32>,
    #[serde(default)] pub end_port: Option<i32>,
    #[serde(default)] pub end_stub: bool,
    #[serde(default = "yes")] pub auto_join_neighbors: bool,
    #[serde(default = "yes")] pub snap_start: bool,
    #[serde(default = "yes")] pub snap_end: bool,
}

fn yes() -> bool { true }

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TileDiff { pub x: i32, pub y: i32, pub z: i32, pub before: Vec<String>, pub after: Vec<String> }

fn base(atom: &str) -> &str { atom.split('{').next().unwrap_or(atom).trim() }
fn var_edit<'a>(atom: &'a str, name: &str) -> Option<&'a str> {
    let edits = atom.split_once('{')?.1;
    edits.split(&[';', '}'][..]).find_map(|item| {
        let (key, value) = item.split_once('=')?;
        (key.trim() == name).then_some(value.trim().trim_matches('"'))
    })
}
fn opposite(direction: i32) -> i32 {
    match direction { 1=>2,2=>1,4=>8,8=>4,5=>10,10=>5,6=>9,9=>6,_=>0 }
}
fn direction(dx: i32, dy: i32) -> i32 {
    match (dx,dy) { (0,1)=>1,(0,-1)=>2,(1,0)=>4,(-1,0)=>8,
        (1,1)=>5,(1,-1)=>6,(-1,1)=>9,(-1,-1)=>10,_=>0 }
}
fn delta(direction: i32) -> (i32,i32) {
    match direction { 1=>(0,1),2=>(0,-1),4=>(1,0),8=>(-1,0),
        5=>(1,1),6=>(1,-1),9=>(-1,1),10=>(-1,-1),_=>(0,0) }
}
fn clockwise(direction: i32) -> i32 {
    match direction {1=>4,4=>2,2=>8,8=>1,_=>0}
}
fn counterclockwise(direction: i32) -> i32 {
    match direction {1=>8,8=>2,2=>4,4=>1,_=>0}
}
fn layer_of(atom: &str) -> &'static str {
    let path = base(atom);
    if path.starts_with("/obj/structure/cable") { "power" }
    else if path.starts_with("/obj/machinery/atmospherics/") { "atmos" }
    else if path.starts_with("/obj/structure/disposalpipe") { "disposals" }
    else { "other" }
}

pub fn ports(atom: &str, layer: &str) -> HashSet<i32> {
    let path=base(atom);
    if layer == "power" {
        let value=var_edit(atom,"icon_state").unwrap_or("0-1");
        return value.split('-').filter_map(|part| part.parse::<i32>().ok())
            .filter(|dir| opposite(*dir)!=0).collect();
    }
    let dir=var_edit(atom,"dir").and_then(|v| v.parse::<i32>().ok())
        .unwrap_or(if layer=="atmos" || path.contains("/junction") {2} else {0});
    if layer=="atmos" {
        if path.contains("/pipe/manifold4w/") { return [1,2,4,8].into(); }
        if path.contains("/pipe/manifold/") { return [1,2,4,8].into_iter().filter(|d| *d!=dir).collect(); }
        if path.contains("/pipe/simple/") {
            return if dir==1 || dir==2 { [1,2].into() }
                else if dir==4 || dir==8 { [4,8].into() }
                else { [1,2,4,8].into_iter().filter(|d| dir & d != 0).collect() };
        }
    }
    if layer=="disposals" {
        if path.contains("/junction") {
            let state=var_edit(atom,"icon_state").unwrap_or(if path.contains("/yjunction") {"pipe-y"} else {"pipe-j1"});
            return if state=="pipe-y" { [dir,clockwise(dir),counterclockwise(dir)].into() }
                else { [dir,opposite(dir),if state=="pipe-j2" {counterclockwise(dir)} else {clockwise(dir)}].into() };
        }
        if path.contains("/segment") {
            let state=var_edit(atom,"icon_state").unwrap_or("pipe-s");
            return if state=="pipe-s" { [dir,opposite(dir)].into_iter().filter(|d| *d!=0).collect() }
                else { [dir,clockwise(dir)].into_iter().filter(|d| *d!=0).collect() };
        }
    }
    HashSet::new()
}

pub fn route_atom(atom: &str, layer: &str, dirs: &HashSet<i32>) -> Result<String,String> {
    let atom=base(atom);
    let mut values:Vec<_>=dirs.iter().copied().collect(); values.sort_unstable();
    if values.is_empty() { return Err("A network piece needs a port".into()); }
    if layer=="power" {
        if values.len()>2 { return Err("A cable has at most two ports".into()); }
        let state=if values.len()==1 { format!("0-{}",values[0]) }
            else { format!("{}-{}",values[0],values[1]) };
        return Ok(format!("{atom}{{icon_state = \"{state}\"}}"));
    }
    if layer=="atmos" {
        if !["/pipe/simple/","/pipe/manifold/","/pipe/manifold4w/"].iter().any(|p| atom.contains(p)) {
            return Err("Automated atmos routes need a simple pipe subtype".into());
        }
        if values.len()>=3 {
            let lane=atom.rsplit('/').next().unwrap_or("");
            if values.len()==4 { return Ok(format!("/obj/machinery/atmospherics/pipe/manifold4w/hidden/{lane}")); }
            let missing=[1,2,4,8].into_iter().find(|d| !dirs.contains(d)).unwrap();
            return Ok(format!("/obj/machinery/atmospherics/pipe/manifold/hidden/{lane}{{dir = {missing}}}"));
        }
        if !atom.contains("/pipe/simple/") { return Err("A two-way atmos route needs a simple pipe".into()); }
        if values.len()==1 { values.push(opposite(values[0])); }
        let direction=if values.contains(&1) && values.contains(&2) {1}
            else if values.contains(&4) && values.contains(&8) {4} else {values.iter().sum()};
        return Ok(format!("{atom}{{dir = {direction}}}"));
    }
    if layer=="disposals" {
        if values.len()>3 { return Err("Disposals have no four-way connected fitting".into()); }
        if values.len()==3 {
            let missing=[1,2,4,8].into_iter().find(|d| !dirs.contains(d)).unwrap();
            return Ok(format!("/obj/structure/disposalpipe/junction/yjunction{{dir = {}}}",opposite(missing)));
        }
        if !atom.ends_with("/segment") { return Err("A two-way disposal route needs a segment".into()); }
        if values.len()==1 { values.push(opposite(values[0])); }
        if values.contains(&1) && values.contains(&2) { return Ok(format!("{atom}{{dir = 1}}")); }
        if values.contains(&4) && values.contains(&8) { return Ok(format!("{atom}{{dir = 4}}")); }
        let bend=values.iter().find(|dir| values.contains(&clockwise(**dir))).ok_or("Unsupported disposal bend")?;
        return Ok(format!("{atom}{{dir = {bend}; icon_state = \"pipe-c\"}}"));
    }
    Err("Unknown network".into())
}

fn compatible(atom: &str, input: &RouteInput) -> bool {
    if layer_of(atom)!=input.layer { return false; }
    if input.layer=="power" { return true; }
    if input.layer=="atmos" {
        return ["/pipe/simple/","/pipe/manifold/","/pipe/manifold4w/"].iter().any(|p| base(atom).contains(p)) &&
            base(atom).rsplit('/').next()==base(&input.atom).rsplit('/').next();
    }
    (base(atom).ends_with("/segment") || base(atom).ends_with("/junction") ||
      base(atom).ends_with("/junction/yjunction")) && base(&input.atom).ends_with("/segment")
}

fn sorted_atoms(atoms:Vec<String>) -> Vec<String> {
    let mut movables=Vec::new(); let mut turfs=Vec::new(); let mut areas=Vec::new();
    for atom in atoms {
        if atom.starts_with("/turf/") {turfs.push(atom)}
        else if atom.starts_with("/area/") {areas.push(atom)}
        else {movables.push(atom)}
    }
    movables.extend(turfs); movables.extend(areas); movables
}

pub fn route(input:RouteInput) -> Result<Vec<TileDiff>,String> {
    if !["power","atmos","disposals"].contains(&input.layer.as_str()) || layer_of(&input.atom)!=input.layer {
        return Err("Route atom does not match the network layer".into());
    }
    if input.points.len()<2 || input.points.len()>500 { return Err("A route needs 2 to 500 points".into()); }
    let mut pts=input.points.clone();
    for pair in pts.windows(2) {
        let dx=pair[1].x-pair[0].x; let dy=pair[1].y-pair[0].y;
        if pair[0].z!=pair[1].z || (if input.layer=="power" {dx.abs().max(dy.abs())!=1}
            else {dx.abs()+dy.abs()!=1}) {
            return Err("Route points must be adjacent on one deck".into());
        }
    }
    let mut tiles:BTreeMap<Point,Vec<String>>=input.tiles.iter().map(|tile|
        (Point{x:tile.x,y:tile.y,z:tile.z},tile.atoms.clone())).collect();
    let original=tiles.clone();
    for at_start in [true,false] {
        if (at_start && !input.snap_start) || (!at_start && !input.snap_end) {continue;}
        let end=if at_start {pts[0]} else {*pts.last().unwrap()};
        if tiles.get(&end).is_some_and(|a| a.iter().any(|a| layer_of(a)==input.layer)) {continue;}
        let mut neighbors=Vec::new();
        for dir in [1,2,4,8,5,6,9,10] {
            if input.layer!="power" && dir>8 {continue;}
            let (dx,dy)=delta(dir); let neighbor=Point{x:end.x+dx,y:end.y+dy,z:end.z};
            if pts.contains(&neighbor) {continue;}
            if tiles.get(&neighbor).is_some_and(|atoms| atoms.iter().any(|a| compatible(a,&input))) {
                neighbors.push(neighbor);
            }
        }
        if neighbors.len()==1 { if at_start {pts.insert(0,neighbors[0]);} else {pts.push(neighbors[0]);} }
    }
    let route_set:HashSet<_>=pts.iter().copied().collect();
    for (i,point) in pts.iter().enumerate() {
        let current=tiles.get(point).ok_or("Route tile is not loaded")?.clone();
        let existing:Vec<_>=current.iter().filter(|a| layer_of(a)==input.layer).cloned().collect();
        let mut wanted=HashSet::new();
        if i>0 {wanted.insert(direction(pts[i-1].x-point.x,pts[i-1].y-point.y));}
        if i+1<pts.len() {wanted.insert(direction(pts[i+1].x-point.x,pts[i+1].y-point.y));}
        if !existing.is_empty() {
            let candidates:Vec<_>=existing.iter().filter(|a| compatible(a,&input)).cloned().collect();
            if candidates.is_empty() {return Err(format!("Existing {} at ({},{}) is incompatible",input.layer,point.x,point.y));}
            let preferred=if i==0 {input.anchor_port} else if i+1==pts.len() {input.end_port} else {None};
            let mut updated=current.clone();
            if input.layer=="power" {
                if input.end_stub && i+1==pts.len() && wanted.len()==1 {
                    let stub=route_atom(&input.atom,&input.layer,&wanted)?;
                    if !updated.contains(&stub) {updated.push(stub);}
                } else if candidates.iter().any(|a| wanted.is_subset(&ports(a,&input.layer))) {continue;}
                else if wanted.len()==2 {
                    let shared=candidates.iter().find(|a| !ports(a,&input.layer).is_disjoint(&wanted));
                    let replacement=candidates.iter().find(|a| {
                        let p=ports(a,&input.layer); p.len()==1 && p.is_subset(&wanted)
                    });
                    let new=route_atom(shared.map(String::as_str).unwrap_or(&input.atom),&input.layer,&wanted)?;
                    if let Some(old)=replacement { if let Some(pos)=updated.iter().position(|a| a==old) {updated.remove(pos);} }
                    updated.push(new);
                } else {
                    let chosen=candidates.iter().find(|a| preferred.is_some_and(|p| ports(a,&input.layer).contains(&p)))
                        .unwrap_or(&candidates[0]);
                    let chosen_ports=ports(chosen,&input.layer);
                    let route_port=*wanted.iter().next().ok_or("Empty cable route")?;
                    let bridge=preferred.filter(|p| chosen_ports.contains(p))
                        .or_else(|| {let opposite=opposite(route_port); chosen_ports.contains(&opposite).then_some(opposite)})
                        .or_else(|| chosen_ports.iter().min().copied());
                    if candidates.len()==1 && chosen_ports.len()==1 {
                        if let Some(pos)=updated.iter().position(|a| a==chosen) {updated.remove(pos);}
                    }
                    let dirs=bridge.map_or_else(|| wanted.clone(),|port| [route_port,port].into());
                    updated.push(route_atom(chosen,&input.layer,&dirs)?);
                }
            } else {
                let present:HashSet<i32>=candidates.iter().flat_map(|a| ports(a,&input.layer)).collect();
                let missing:HashSet<i32>=wanted.difference(&present).copied().collect();
                if missing.is_empty() {continue;}
                let chosen=&candidates[0];
                let dirs=present.union(&missing).copied().collect();
                if let Some(pos)=updated.iter().position(|a| a==chosen) {updated.remove(pos);}
                updated.push(route_atom(chosen,&input.layer,&dirs)?);
            }
            tiles.insert(*point,sorted_atoms(updated));
            continue;
        }
        let mut dirs=wanted;
        if input.auto_join_neighbors {
            for dir in [1,2,4,8,5,6,9,10] {
                if input.layer!="power" && dir>8 {continue;}
                let (dx,dy)=delta(dir); let neighbor=Point{x:point.x+dx,y:point.y+dy,z:point.z};
                if route_set.contains(&neighbor) {continue;}
                if tiles.get(&neighbor).is_some_and(|atoms| atoms.iter().any(|a|
                    layer_of(a)==input.layer && ports(a,&input.layer).contains(&opposite(dir)))) {
                    dirs.insert(dir);
                }
            }
        }
        let mut updated:Vec<String>=current.into_iter().filter(|a| layer_of(a)!=input.layer).collect();
        if dirs.len()>2 && input.layer=="power" {
            let anchor=*dirs.iter().min().unwrap();
            for dir in dirs.iter().filter(|dir| **dir!=anchor) {
                updated.push(route_atom(&input.atom,&input.layer,&[anchor,*dir].into())?);
            }
        } else {updated.push(route_atom(&input.atom,&input.layer,&dirs)?);}
        tiles.insert(*point,sorted_atoms(updated));
    }
    Ok(route_set.into_iter().filter_map(|point| {
        let before=original.get(&point)?; let after=tiles.get(&point)?;
        (before!=after).then(|| TileDiff{x:point.x,y:point.y,z:point.z,before:before.clone(),after:after.clone()})
    }).collect())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn set(dirs:&[i32])->HashSet<i32> {dirs.iter().copied().collect()}
    #[test]
    fn route_shapes_match_game_fittings() {
        let pipe="/obj/machinery/atmospherics/pipe/simple/hidden/supply";
        let branch=route_atom(pipe,"atmos",&set(&[1,4,8])).unwrap();
        assert!(branch.contains("/manifold/hidden/supply"));
        assert_eq!(ports(&branch,"atmos"),set(&[1,4,8]));
        let disposal=route_atom("/obj/structure/disposalpipe/segment","disposals",&set(&[1,4,8])).unwrap();
        assert_eq!(ports(&disposal,"disposals"),set(&[1,4,8]));
        let cable=route_atom("/obj/structure/cable/green","power",&set(&[5,8])).unwrap();
        assert_eq!(ports(&cable,"power"),set(&[5,8]));
    }
}
