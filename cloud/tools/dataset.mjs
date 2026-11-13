import {readFile,readdir,writeFile,rename,unlink,open} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {existsSync} from 'node:fs';
const root=resolve(process.env.LINQO_DATA_DIRECTORY??fileURLToPath(new URL('../../.private/linqo-training/',import.meta.url)));
const lock=join(root,'.export.lock');
let handle;
try{handle=await open(lock,'wx',0o600);}catch{throw Error('Another export or dataset preparation is running.');}
try {
for(const name of ['train.jsonl','eval.jsonl','train.jsonl.tmp','eval.jsonl.tmp','dataset-manifest.json'])await unlink(join(root,name)).catch(e=>{if(e.code!=='ENOENT')throw e;});
const state=JSON.parse(await readFile(join(root,'checkpoint.json'),'utf8'));
if(Date.now()-state.last_success>7*86400000)throw Error('Pull contributions and deletion requests before preparing a dataset.');
const buckets={train:[],eval:[]},seen=new Set();
for(const name of (await readdir(join(root,'examples'))).sort()){
  if(!name.endsWith('.json'))continue;
  const row=JSON.parse(await readFile(join(root,'examples',name),'utf8'));
  if(!row.review?.approved||!row.review.rights_confirmed)continue;
  if(typeof row.review.target!=='string'||!row.review.target.trim()||!row.review.category)throw Error(`Approved example ${row.id} requires an independently reviewed target/category.`);
  JSON.parse(row.review.target);
  if(createHash('sha256').update(JSON.stringify(row.sample)).digest('hex')!==row.sha256)throw Error(`Original example ${row.id} changed. Keep reviewed corrections in review.target.`);
  // Split by normalized source, preventing repeated source leakage across splits.
  const key=createHash('sha256').update(row.sample.source.trim().toLowerCase().replace(/\s+/g,' ')).digest('hex');
  if(seen.has(key))continue;seen.add(key);
  const split=parseInt(key.slice(0,8),16)%5===0?'eval':'train';
  buckets[split].push(JSON.stringify({id:row.id,source:row.sample.source,category:row.review.category,target:row.review.target}));
}
if(!buckets.train.length||!buckets.eval.length)throw Error('Need reviewed examples in both training and held-out evaluation splits.');
for(const [split,rows]of Object.entries(buckets)){await writeFile(join(root,split+'.jsonl.tmp'),rows.join('\n')+'\n',{mode:0o600});}
const project=fileURLToPath(new URL('../../',import.meta.url));
const localDart=join(project,'.tools','flutter','bin','cache','dart-sdk','bin',process.platform==='win32'?'dart.exe':'dart');
const dart=process.env.LINQO_DART??(existsSync(localDart)?localDart:'dart');
execFileSync(dart,[join(project,'tool','validate_training_dataset.dart'),join(root,'train.jsonl.tmp'),join(root,'eval.jsonl.tmp')],{cwd:project,stdio:['ignore','pipe','pipe']});
for(const split of Object.keys(buckets)){await rename(join(root,split+'.jsonl.tmp'),join(root,split+'.jsonl'));}
await writeFile(join(root,'dataset-manifest.json'),JSON.stringify({prepared:Date.now(),deletion_cursor:state.deletion,counts:{train:buckets.train.length,eval:buckets.eval.length}}),{mode:0o600});
console.log(`Prepared ${buckets.train.length} training and ${buckets.eval.length} evaluation examples. No training was started.`);

} catch(error) {
  for(const name of ['train.jsonl','eval.jsonl','train.jsonl.tmp','eval.jsonl.tmp','dataset-manifest.json'])await unlink(join(root,name)).catch(e=>{if(e.code!=='ENOENT')throw e;});
  throw error;
} finally { await handle.close(); await unlink(lock); }
