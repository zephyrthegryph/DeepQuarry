import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { cargoSourceInputs, cargoSourceKey, parseCargoToml } from './cargo_source_inputs';
function fixture(label:string):string {
  const parent=process.env.DQ_TEST_SCRATCH_ROOT || 'E:/dq-cache/test-runs';
  fs.mkdirSync(parent,{recursive:true});
  const root=fs.mkdtempSync(path.join(parent,`source-key-${label}-`));
  put(root,'app/Cargo.toml',"[package]\nname='app'\nversion='0.1.0'\n[dependencies]\na={path='../native/a',optional=true}\n[workspace]\n");
  put(root,'app/src/lib.rs','pub fn app() {}');
  put(root,'app/Cargo.lock','# lock');
  put(root,'native/Cargo.toml',"[workspace]\nmembers=['a','b']\n[workspace.dependencies]\nb={path='b'}\n[workspace.metadata.dq-source-key]\ninputs=['shared/helper.rs','fixtures/source.dm']\n");
  put(root,'native/a/Cargo.toml',"[package]\nname='a'\nversion='0.1.0'\n[target.'cfg(windows)'.build-dependencies]\nb={workspace=true}\n");
  put(root,'native/a/src/lib.rs','pub fn a() {}');
  put(root,'native/b/Cargo.toml',"[package]\nname='b'\nversion='0.1.0'\n");
  put(root,'native/b/src/lib.rs','pub fn b() {}');
  put(root,'native/shared/helper.rs','pub fn helper() {}');
  put(root,'native/fixtures/source.dm','/datum/probe');
  return root;
}
function put(root:string,p:string,text:string){const f=path.join(root,p);fs.mkdirSync(path.dirname(f),{recursive:true});fs.writeFileSync(f,text);}
const key=(root:string)=>cargoSourceKey(root,path.join(root,'app/Cargo.toml'),'profile|platform');
test('strict Cargo parser rejects malformed and duplicate TOML, retaining real dotted-table values',()=>{
  expect(()=>parseCargoToml('[package\ninvalid')).toThrow();
  expect(()=>parseCargoToml('[dependencies]\na="1"\na="2"\n')).toThrow();
  expect(parseCargoToml('[target.\'cfg(windows)\'.build-dependencies]\n"renamed-dep"={path="../dep",optional=true}\n')).toEqual({target:{'cfg(windows)':{'build-dependencies':{'renamed-dep':{path:'../dep',optional:true}}}}});
});
test('invalid UTF8 manifest bytes cannot be replaced before strict TOML admission',()=>{
  const root=fixture('invalid-utf8');try{
    fs.writeFileSync(path.join(root,'native/b/Cargo.toml'),Buffer.concat([Buffer.from('[package]\nname="b"\nversion="0.1.0"\n# invalid '),Buffer.from([0xff]),Buffer.from('\n')]));
    expect(()=>key(root)).toThrow();
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('transitive workspace target deps, insertions and shared includes affect key',()=>{
  const root=fixture('transitive');try{
    const old=key(root);put(root,'native/b/src/lib.rs','pub fn changed() {}');expect(key(root)).not.toBe(old);
    const second=key(root);put(root,'native/b/src/data.bin','new');expect(key(root)).not.toBe(second);
    const third=key(root);put(root,'native/shared/helper.rs','changed');expect(key(root)).not.toBe(third);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('missing dependencies and invalid TOML fail closed',()=>{
  const root=fixture('missing');try{
    fs.rmSync(path.join(root,'native/b/Cargo.toml'));expect(()=>key(root)).toThrow();
    put(root,'native/b/Cargo.toml','[package\ninvalid');expect(()=>key(root)).toThrow();
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('relocated roots are reproducible and output directories do not key',()=>{
  const a=fixture('a'),b=fixture('b');try{
    expect(key(a)).toBe(key(b));put(a,'native/b/target/release/blob','output');expect(key(a)).toBe(key(b));
    expect(cargoSourceInputs(a,path.join(a,'app/Cargo.toml')).files.every(p=>!path.isAbsolute(p)&&!p.includes('\\'))).toBe(true);
  }finally{fs.rmSync(a,{recursive:true,force:true});fs.rmSync(b,{recursive:true,force:true});}
});
test('new package-root source and previously absent Cargo config change published key',()=>{
  const root=fixture('insert');try{
    expect(cargoSourceInputs(root,path.join(root,'app/Cargo.toml')).missingPaths).toContain('.cargo/config.toml');
    const before=key(root);put(root,'native/b/root_source.rs','pub fn added() {}');expect(key(root)).not.toBe(before);
    const beforeConfig=key(root);put(root,'.cargo/config.toml','[build]\nrustflags=["--cfg","source_key_probe"]\n');expect(key(root)).not.toBe(beforeConfig);
    // A module named target under src is source, not Cargo's output directory.
    const beforeModule=key(root);put(root,'native/b/src/target/mod.rs','pub fn target() {}');expect(key(root)).not.toBe(beforeModule);
  }finally{fs.rmSync(root,{recursive:true,force:true});}
});
