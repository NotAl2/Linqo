import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdir,readFile,writeFile,rename,unlink,readdir} from 'node:fs/promises';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';

const here=dirname(fileURLToPath(import.meta.url));
const root=resolve(here,'..');
const defaultDestination=resolve(process.env.LINQO_DATA_DIRECTORY??join(root,'..','.private','linqo-training'));
const db=process.env.LINQO_CONTRIBUTIONS_DATABASE??'linqo-contributions';
const wrangler=join(root,'node_modules','wrangler','bin','wrangler.js');
const hash=x=>createHash('sha256').update(x).digest('hex');
const safe=id=>{if(!/^[0-9a-f-]{36}$/.test(id))throw Error('Invalid contribution ID');return id;};
async function atomic(path,value){const temporary=path+'.tmp';await writeFile(temporary,JSON.stringify(value),{mode:0o600});await rename(temporary,path);}
async function load(path,fallback){try{return JSON.parse(await readFile(path,'utf8'));}catch(e){if(e.code==='ENOENT')return fallback;throw e;}}
function query(sql){
  // Credentials are resolved by Wrangler's OAuth store or inherited environment,
  // never placed in arguments or printed by this script.
  const output=execFileSync(process.execPath,[wrangler,'d1','execute',db,'--remote','--json','--command',sql],{cwd:root,encoding:'utf8',maxBuffer:16*1024*1024,stdio:['ignore','pipe','pipe']});
  const result=JSON.parse(output);if(!Array.isArray(result)||result.some(x=>x.success===false))throw Error('D1 export failed');
  return result.flatMap(x=>x.results??[]);
}
export async function runExport({destination=defaultDestination,queryFn=query}={}) {
await mkdir(join(destination,'examples'),{recursive:true,mode:0o700});
const lock=join(destination,'.export.lock');
const {open}=await import('node:fs/promises');
let handle;
try{handle=await open(lock,'wx',0o600);}catch{throw Error('Another export is running. Remove a stale .export.lock only after checking no export is active.');}
try {
  const checkpointPath=join(destination,'checkpoint.json');
  const state=await load(checkpointPath,{created:0,id:'',deletion:0});
  for(const name of ['train.jsonl','eval.jsonl','dataset-manifest.json'])await unlink(join(destination,name)).catch(e=>{if(e.code!=='ENOENT')throw e;});
  // Process deletions first, including examples reviewed on the maintainer laptop.
  while(true){
    const rows=queryFn(`SELECT sequence,id FROM deletions WHERE sequence>${Number(state.deletion)} ORDER BY sequence LIMIT 500`);
    if(!rows.length)break;
    for(const row of rows){await unlink(join(destination,'examples',safe(row.id)+'.json')).catch(e=>{if(e.code!=='ENOENT')throw e;});state.deletion=row.sequence;}
    await atomic(checkpointPath,state);
  }
  let count=0;
  while(true){
    const rows=queryFn(`SELECT id,payload,sha256,created FROM samples WHERE created>${Number(state.created)} OR (created=${Number(state.created)} AND id>'${state.id?safe(state.id):''}') ORDER BY created,id LIMIT 100`);
    if(!rows.length)break;
    for(const row of rows){
      if(hash(row.payload)!==row.sha256)throw Error('Contribution checksum mismatch; export was not acknowledged.');
      const path=join(destination,'examples',safe(row.id)+'.json');
      const prior=await load(path,null);
      if(prior&&prior.sha256!==row.sha256)throw Error('Contribution ID changed content.');
      if(!prior)await atomic(path,{id:row.id,created:row.created,downloaded:Date.now(),sha256:row.sha256,sample:JSON.parse(row.payload),review:{approved:false,rights_confirmed:false,category:null,target:null}});
      count++;
    }
    // Local files are complete and checksummed before any acknowledgement.
    queryFn(`UPDATE samples SET exported=${Date.now()} WHERE id IN (${rows.map(x=>`'${safe(x.id)}'`).join(',')})`);
    state.created=rows.at(-1).created;state.id=rows.at(-1).id;
    await atomic(checkpointPath,state);
  }
  for(const name of await readdir(join(destination,'examples'))){
    if(!name.endsWith('.json'))continue;
    const path=join(destination,'examples',name),row=await load(path,null);
    if(!row.review?.approved&&Date.now()-row.downloaded>90*86400000)await unlink(path);
  }
  state.last_success=Date.now();await atomic(checkpointPath,state);
  console.log(`Export verified: ${count} examples processed. Private destination: ${destination}`);
} finally {await handle.close();await unlink(lock);}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))await runExport();
