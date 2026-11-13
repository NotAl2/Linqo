import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdir,mkdtemp,readFile,readdir,rm,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {createHash} from 'node:crypto';
import {runExport} from '../tools/export.mjs';
const id='12345678-1234-1234-1234-123456789abc';
const payload=JSON.stringify({source:'Synthetic example',output:'Synthetic result'});
const row={id,payload,sha256:createHash('sha256').update(payload).digest('hex'),created:100};
async function temporary(){const root=fileURLToPath(new URL('../test-output/',import.meta.url));await mkdir(root,{recursive:true});return mkdtemp(join(root,'export-'));}
test('export checksums before ack, retries safely, preserves reviews, and applies deletions',async()=>{
  const destination=await temporary();let ack=0,deleted=false;
  function queryFn(sql){
    if(sql.startsWith('SELECT sequence'))return deleted&&sql.includes('sequence>0 ')?[{sequence:1,id}]:[];
    if(sql.startsWith('SELECT id,payload'))return !deleted&&sql.includes('created>0 ')?[row]:[];
    if(sql.startsWith('UPDATE samples')){ack++;return [];}
    throw Error('Unexpected query');
  }
  try{
    await runExport({destination,queryFn});assert.equal(ack,1);
    const path=join(destination,'examples',id+'.json');
    const saved=JSON.parse(await readFile(path,'utf8'));saved.review.approved=true;
    await writeFile(path,JSON.stringify(saved));
    await runExport({destination,queryFn});assert.equal(ack,1);
    assert.equal(JSON.parse(await readFile(path,'utf8')).review.approved,true);
    for(const name of ['train.jsonl.tmp','eval.jsonl.tmp'])await writeFile(join(destination,name),'withdrawn content');
    deleted=true;await runExport({destination,queryFn});
    assert.deepEqual(await readdir(join(destination,'examples')),[]);
    for(const name of ['train.jsonl.tmp','eval.jsonl.tmp'])await assert.rejects(readFile(join(destination,name)),e=>e.code==='ENOENT');
    assert.equal(JSON.parse(await readFile(join(destination,'checkpoint.json'),'utf8')).deletion,1);
  }finally{await rm(destination,{recursive:true,force:true});}
});
test('invalid checksum never acknowledges data or advances checkpoint',async()=>{
  const destination=await temporary();let ack=0;
  const queryFn=sql=>sql.startsWith('SELECT sequence')?[]:sql.startsWith('SELECT id,payload')?[{...row,sha256:'bad'}]:(ack++,[]);
  try{
    await assert.rejects(runExport({destination,queryFn}),/checksum mismatch/);assert.equal(ack,0);
    assert.deepEqual(await readdir(join(destination,'examples')),[]);
  }finally{await rm(destination,{recursive:true,force:true});}
});
test('failed acknowledgement leaves files verified and cursor retryable',async()=>{
  const destination=await temporary();
  const queryFn=sql=>{if(sql.startsWith('SELECT sequence'))return [];if(sql.startsWith('SELECT id,payload'))return [row];throw Error('Network interrupted');};
  try{
    await assert.rejects(runExport({destination,queryFn}),/Network interrupted/);
    assert.equal(JSON.parse(await readFile(join(destination,'examples',id+'.json'),'utf8')).sha256,row.sha256);
    await assert.rejects(readFile(join(destination,'checkpoint.json')),e=>e.code==='ENOENT');
  }finally{await rm(destination,{recursive:true,force:true});}
});
