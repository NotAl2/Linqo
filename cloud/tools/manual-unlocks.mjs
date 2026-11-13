import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {parseArgs} from 'node:util';
import {dirname,resolve,join} from 'node:path';
import {fileURLToPath} from 'node:url';

const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
export const quote=value=>"'"+value.replaceAll("'","''")+"'";
export function query(sql) {
  // Wrangler uses its protected local OAuth store; no admin API in the app.
  let output;
  try { output=execFileSync(process.execPath,[join(root,'node_modules/wrangler/bin/wrangler.js'),'d1','execute','linqo-purchases','--remote','--json','--command',sql],{cwd:root,encoding:'utf8',stdio:['ignore','pipe','pipe']}); }
  catch { throw Error('Cloudflare operation failed. Check Wrangler authorization; no credentials printed.'); }
  const rows=JSON.parse(output);
  if(!Array.isArray(rows)||rows.some(row=>row.success===false)) throw Error('D1 operation failed');
  return rows.flatMap(row=>row.results??[]);
}

export function manualUnlock(action,options,queryFn=query,now=Date.now()) {
  const {reference}=options;
  if(typeof reference!=='string'||!/^[-a-zA-Z0-9_]{4,120}$/.test(reference)) throw Error('Use the verified provider payment ID, without buyer details.');
  const receipt=createHash('sha256').update('buymeacoffee:'+reference.toLowerCase()).digest('hex');
  if(action==='grant') {
    const {code,tier,verified}=options, amount=Number(options['amount-minor']);
    if(!verified) throw Error('Verify the settled payment in your provider dashboard first, then use --verified.');
    if(!/^LQ-[a-f0-9]{32}$/.test(code??'')||!['xl','xxl'].includes(tier)||!Number.isSafeInteger(amount)||amount<(tier==='xl'?499:699)||amount>100000000) throw Error('Use a valid account code, tier and verified USD cents (XL at least 499; XXL at least 699).');
    const account=queryFn(`SELECT uid FROM manual_accounts WHERE code=${quote(code)}`)[0];
    if(!account) throw Error('Unknown account code. Buyer must sign in and copy it from Linqo.');
    queryFn(`INSERT OR IGNORE INTO manual_grants(receipt_hash,uid,tier,minor,currency,verified_at) VALUES(${quote(receipt)},${quote(account.uid)},${quote(tier)},${amount},'USD',${now})`);
    const grant=queryFn(`SELECT uid,tier,minor,revoked_at FROM manual_grants WHERE receipt_hash=${quote(receipt)}`)[0];
    if(!grant||grant.uid!==account.uid||grant.tier!==tier||grant.minor!==amount||grant.revoked_at!==null) throw Error('Payment already used differently or revoked; no new unlock granted.');
    return {ok:true,tier,code};
  }
  if(action==='revoke') {
    const {reason,confirm}=options;
    if(!confirm||!['refund','chargeback','mistake'].includes(reason)) throw Error('Use --confirm and --reason refund, chargeback or mistake.');
    const grant=queryFn(`SELECT tier FROM manual_grants WHERE receipt_hash=${quote(receipt)}`)[0];
    if(!grant) throw Error('No manual grant exists for this payment.');
    queryFn(`UPDATE manual_grants SET revoked_at=${now},reason=${quote(reason)} WHERE receipt_hash=${quote(receipt)} AND revoked_at IS NULL`);
    return {ok:true,revoked:true};
  }
  throw Error('Use grant or revoke.');
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const {values,positionals}=parseArgs({allowPositionals:true,options:{code:{type:'string'},tier:{type:'string'},reference:{type:'string'},'amount-minor':{type:'string'},verified:{type:'boolean'},reason:{type:'string'},confirm:{type:'boolean'}}});
    if(positionals.length!==1) throw Error('Use grant or revoke with explicit options.');
    console.log(JSON.stringify(manualUnlock(positionals[0],values)));
  } catch(error) { console.error(error.message); process.exitCode=1; }
}
