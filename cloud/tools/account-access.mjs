import {parseArgs} from 'node:util';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {query,quote} from './manual-unlocks.mjs';

export function accountAccess(action,options,run=query,now=Date.now()) {
  if(!options.confirm) throw Error('Use --confirm for this maintainer-only account change.');
  if(['offer','remove-offer','gift'].includes(action)) {
    if(!/^LQ-[a-f0-9]{32}$/.test(options.code??'')) throw Error('Use the account code copied after Google sign-in.');
    const account=run(`SELECT uid FROM manual_accounts WHERE code=${quote(options.code)}`)[0];
    if(!account) throw Error('Unknown account code. No access changed.');
    if(action==='offer'||action==='remove-offer') {
      run(`INSERT INTO account_offers(uid,minor,enabled,created) VALUES(${quote(account.uid)},100,${action==='offer'?1:0},${now}) ON CONFLICT(uid) DO UPDATE SET enabled=excluded.enabled,created=excluded.created`);
      return {ok:true,offer:action==='offer',tier:'xxl',amount_minor:100};
    }
    if(!['xl','xxl'].includes(options.tier)||!/^[-a-zA-Z0-9_]{8,100}$/.test(options.reference??'')) throw Error('Gift needs an XL/XXL tier and a private unique reference (8–100 safe characters).');
    run(`INSERT OR IGNORE INTO gift_grants(reference,uid,tier,reason,created) VALUES(${quote(options.reference)},${quote(account.uid)},${quote(options.tier)},'gift',${now})`);
    const gift=run(`SELECT uid,tier,revoked_at FROM gift_grants WHERE reference=${quote(options.reference)}`)[0];
    if(!gift||gift.uid!==account.uid||gift.tier!==options.tier||gift.revoked_at!==null) throw Error('Gift reference already used differently or revoked.');
    return {ok:true,gift:true,tier:options.tier};
  }
  if(action==='revoke-gift') {
    if(!/^[-a-zA-Z0-9_]{8,100}$/.test(options.reference??'')) throw Error('Use the existing gift reference.');
    const gift=run(`SELECT tier FROM gift_grants WHERE reference=${quote(options.reference)}`)[0];
    if(!gift) throw Error('Unknown gift.');
    run(`UPDATE gift_grants SET revoked_at=${now} WHERE reference=${quote(options.reference)} AND revoked_at IS NULL`);
    return {ok:true,revoked:true};
  }
  throw Error('Use offer, remove-offer, gift or revoke-gift.');
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  try {
    const {values,positionals}=parseArgs({allowPositionals:true,options:{code:{type:'string'},tier:{type:'string'},reference:{type:'string'},confirm:{type:'boolean'}}});
    if(positionals.length!==1) throw Error('Choose one maintainer action.');
    console.log(JSON.stringify(accountAccess(positionals[0],values)));
  } catch(error) { console.error(error.message);process.exitCode=1; }
}
