import { expect, test } from 'bun:test';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { compilerSourcesDirty, dmbcCacheKey } from './dmbc_cache';

function git(root:string,args:string[]):void {
  const result=spawnSync('git',['-c','user.name=Compiler cache test','-c','user.email=cache-test@example.invalid',...args],{cwd:root,encoding:'utf8',windowsHide:true});
  if(result.error||result.status!==0) throw new Error(`fixture git failed: ${result.error?.message||result.stderr}`);
}
function put(root:string,file:string,text:string):void {const p=path.join(root,file);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,text);}
function fixture():string {
  const parent=process.env.DQ_TEST_SCRATCH_ROOT||'E:/dq-cache/test-runs';fs.mkdirSync(parent,{recursive:true});
  const root=fs.mkdtempSync(path.join(parent,'dmbc-source-key-'));
  git(root,['init','-q']);
  put(root,'tools/dmb/Cargo.toml','[workspace]\n');
  put(root,'tools/dmb/crates/dm-tree/src/lib.rs','pub fn native() {}\n');
  put(root,'tools/analyze/src/policy.rs','pub fn policy() {}\n');
  put(root,'tools/dmb/shared/helper.rs','pub fn shared() {}\n');
  put(root,'code/content.dm','/obj/content\n');
  git(root,['add','.']);git(root,['commit','-qm','initial fixture']);return root;
}
function key(root:string):string {const result=dmbcCacheKey(root);if(!('key' in result)) throw new Error(result.bypass);return result.key;}
test('committed analyzer policy changes invalidate native compiler identity',()=>{
  const root=fixture();try {
    const before=key(root);put(root,'tools/analyze/src/policy.rs','pub fn changed_policy() {}\n');
    git(root,['add','tools/analyze']);git(root,['commit','-qm','change linked analyzer']);
    expect(key(root)).not.toBe(before);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('dirty and new analyzer sources select private compiler development',()=>{
  const root=fixture();try {
    put(root,'tools/analyze/src/policy.rs','pub fn dirty_policy() {}\n');
    const dirty=dmbcCacheKey(root);expect('bypass' in dirty && dirty.bypass.startsWith('uncommitted')).toBe(true);
    expect(compilerSourcesDirty(root)).toBe(true);
    put(root,'tools/analyze/src/policy.rs','pub fn policy() {}\n');
    put(root,'tools/analyze/src/new_policy.rs','pub fn new_policy() {}\n');
    const added=dmbcCacheKey(root);expect('bypass' in added && added.bypass.includes('new_policy.rs')).toBe(true);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('shared source edits affect dirty detection and committed compiler key',()=>{
  const root=fixture();try {
    const before=key(root);put(root,'tools/dmb/shared/helper.rs','pub fn changed_shared() {}\n');
    expect(compilerSourcesDirty(root)).toBe(true);
    git(root,['add','tools/dmb/shared']);git(root,['commit','-qm','change shared compiler source']);
    expect(key(root)).not.toBe(before);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
});
test('content-only changes do not mark compiler sources dirty',()=>{
  const root=fixture();try {
    const before=key(root);put(root,'code/content.dm','/obj/changed_content\n');
    expect(key(root)).toBe(before);expect(compilerSourcesDirty(root)).toBe(false);
  } finally {fs.rmSync(root,{recursive:true,force:true});}
});
