import {createRemoteJWKSet, jwtVerify, importJWK, SignJWT} from 'jose';
import {digest,hmac,fail} from './crypto.mjs';
import {PRODUCTS,checkoutReady,startCheckout,effectiveCashfreeTier,recordCashfreeEvent,verifyCashfreeSignature,reconcileOwner,checkoutPage,checkoutReturn} from './cashfree.mjs';
export {digest,PRODUCTS};

const encoder = new TextEncoder();
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
const categories = new Set(['recipe','article','tutorial','place','general']);
const authenticatedRoutes = new Set(['GET /entitlement','POST /checkout/start','PUT /consent','POST /samples','GET /samples','DELETE /account']);
const json = (data, status=200) => new Response(JSON.stringify(data), {status, headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
async function read(request, max=12288) {
  if(Number(request.headers.get('content-length'))>max) fail('payload_too_large',413);
  const reader=request.body?.getReader(); if(!reader) return '';
  let size=0; const chunks=[];
  while(true) { const {done,value}=await reader.read(); if(done) break; size+=value.length; if(size>max){await reader.cancel();fail('payload_too_large',413);} chunks.push(value); }
  const bytes=new Uint8Array(size); let offset=0; for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  return new TextDecoder('utf-8',{fatal:true}).decode(bytes);
}
export async function verifyFirebaseIdentityToken(token,projectId,keys=googleKeys) {
  if(!token || token.length>8192 || !projectId) fail('sign_in_required',401);
  let payload;
  try { ({payload}=await jwtVerify(token,keys,{algorithms:['RS256'],issuer:`https://securetoken.google.com/${projectId}`,audience:projectId,clockTolerance:5})); }
  catch { fail('sign_in_required',401); }
  if(!payload.sub || payload.sub.length>128 || payload.email_verified!==true || payload.firebase?.sign_in_provider!=='google.com') fail('google_sign_in_required',401);
  return payload;
}
async function identity(request,env) {
  const token=request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];
  const payload=await verifyFirebaseIdentityToken(token,env.FIREBASE_PROJECT_ID);
  // A stable, keyed provider subject allows restoring a purchase even after
  // deleting/recreating the Firebase account with the same Google identity.
  const provider=payload.firebase?.identities?.['google.com']?.[0];
  if(typeof provider!=='string'||(env.ACCOUNT_HMAC_SECRET?.length??0)<32) fail('identity_not_configured',503);
  const subject=await hmac(env.ACCOUNT_HMAC_SECRET,provider);
  return {uid:payload.sub,purchaseOwner:await purchaseAccount(env.PURCHASES,subject,payload.sub)};
}
export async function purchaseAccount(db,subject,currentUid) {
  // Immutable canonical purchase identity. Old/new Firebase tokens for the same
  // Google identity cannot move orders back and forth after account recreation.
  await db.prepare('INSERT OR IGNORE INTO account_links VALUES(?,?)').bind(subject,currentUid).run();
  return (await db.prepare('SELECT uid FROM account_links WHERE subject=?').bind(subject).first()).uid;
}
export const effectiveTier = effectiveCashfreeTier;
async function entitlement(env,uid,purchaseOwner) {
  await reconcileOwner(env,purchaseOwner);
  const tier=await effectiveTier(env.PURCHASES,purchaseOwner);
  const key=await importJWK(JSON.parse(env.ENTITLEMENT_PRIVATE_JWK),'EdDSA');
  const token=await new SignJWT({tier,version:1}).setProtectedHeader({alg:'EdDSA',kid:env.KEY_ID??'v1'}).setSubject(uid).setAudience('dev.linqo.linqo').setIssuer('linqo-cloud').setIssuedAt().sign(key);
  return {token,payments_enabled:checkoutReady(env),sandbox:env.CASHFREE_MODE!=='production'};
}
export function validateSample(value) {
  const allowed=['version','category','source','output','correction','model','schema'];
  if(!value || Object.keys(value).some(k=>!allowed.includes(k)) || value.version!==1 || !categories.has(value.category)) fail('invalid_sample');
  if(!['source','output','model','schema'].every(k=>typeof value[k]==='string' && value[k].length>0)) fail('invalid_sample');
  if(value.correction!==undefined&&typeof value.correction!=='string') fail('invalid_sample');
  if(value.model.length>120||value.schema.length>40) fail('invalid_sample');
  const payload=JSON.stringify(value),bytes=encoder.encode(payload).length;
  if(bytes>8192) fail('payload_too_large',413);
  // Defence in depth, not a claim that personal information can always be detected.
  const text=[value.source,value.output,value.correction??''].join('\n');
  // Any remaining @ is rejected rather than using a backtracking email regex
  // on attacker-controlled long strings in a 10 ms free Worker CPU budget.
  if(text.includes('@')||/https?:\/\/|www\.|\b(?:\d[ -]?){9,}\b|\b(password|api[_ -]?key|bearer|credit card|medical record|home address)\b/i.test(text)) fail('sensitive_sample');
  if(value.source.length<80 || !/[a-zA-Z]/.test(value.source) || (value.source.match(/[^\x00-\x7f]/g)?.length??0)>value.source.length*.15) fail('ineligible_sample');
  return {payload,bytes};
}
export async function insertSample(db,owner,value,now=Date.now(),id=crypto.randomUUID()) {
  const {payload,bytes}=validateSample(value), day=new Date(now).toISOString().slice(0,10);
  const hash=await digest(payload);
  const result=await db.prepare(`INSERT INTO samples(id,owner,day,payload,sha256,bytes,created)
    SELECT ?,?,?,?,?,?,? WHERE EXISTS(SELECT 1 FROM consent WHERE owner=? AND enabled=1 AND version=1)
    AND COALESCE((SELECT count FROM daily WHERE owner=? AND day=?),0)<2
    AND COALESCE((SELECT count FROM daily WHERE owner='*' AND day=?),0)<100
    AND (SELECT bytes FROM intake_budget WHERE id=1)+?<100000000
    AND NOT EXISTS(SELECT 1 FROM samples WHERE owner=? AND sha256=?)`).bind(id,owner,day,payload,hash,bytes,now,owner,owner,day,day,bytes,owner,hash).run();
  if(!result.meta.changes) fail('contribution_not_accepted',429);
  return {id};
}
export async function withdrawSample(db,owner,id) {
  await db.batch([
    db.prepare('INSERT OR IGNORE INTO deletions(id,created) SELECT id,? FROM registry WHERE id=? AND owner=?').bind(Date.now(),id,owner),
    db.prepare('DELETE FROM samples WHERE id=? AND owner=?').bind(id,owner),
    db.prepare('DELETE FROM registry WHERE id=? AND owner=?').bind(id,owner)
  ]);
}
async function route(request,env) {
  const url=new URL(request.url), path=url.pathname;
  if(path==='/health'&&request.method==='GET') return json({ok:true,provider:'cashfree',sandbox:env.CASHFREE_MODE!=='production',payments_enabled:checkoutReady(env),contributions_enabled:env.CONTRIBUTIONS_ENABLED==='true'});
  if(path==='/checkout/return'&&request.method==='GET') return checkoutReturn();
  if(/^\/checkout\/[a-f0-9]{64}$/.test(path)&&request.method==='GET') return checkoutPage(env,path.slice(10));
  if(/^\/webhooks\/cashfree\/(sandbox|production)$/.test(path)&&request.method==='POST') {
    const mode=path.split('/').at(-1);
    const raw=await read(request,65536);
    if(!await verifyCashfreeSignature(env,mode,raw,request.headers.get('x-webhook-timestamp'),request.headers.get('x-webhook-signature'))) fail('invalid_signature',401);
    return json(await recordCashfreeEvent(env,mode,JSON.parse(raw)));
  }
  if(!authenticatedRoutes.has(`${request.method} ${path}`) && !(request.method==='DELETE'&&path.startsWith('/samples/'))) fail('not_found',404);
  const {uid,purchaseOwner}=await identity(request,env);
  if(path==='/entitlement'&&request.method==='GET') return json(await entitlement(env,uid,purchaseOwner));
  if(path==='/checkout/start'&&request.method==='POST') {
    return json(await startCheckout(env,purchaseOwner,JSON.parse(await read(request))));
  }
  if((env.CONTRIBUTOR_HMAC_SECRET?.length??0)<32) fail('contributions_not_configured',503);
  const owner=await hmac(env.CONTRIBUTOR_HMAC_SECRET,uid), db=env.CONTRIBUTIONS;
  if(path==='/consent'&&request.method==='PUT') {
    const value=JSON.parse(await read(request)); if(typeof value.enabled!=='boolean'||value.version!==1) fail('invalid_consent');
    await db.prepare('INSERT INTO consent VALUES(?,?,1,?) ON CONFLICT(owner) DO UPDATE SET enabled=excluded.enabled,version=1,changed=excluded.changed').bind(owner,value.enabled?1:0,Date.now()).run();
    return json({ok:true});
  }
  if(path==='/samples'&&request.method==='POST') {
    if(env.CONTRIBUTIONS_ENABLED!=='true') fail('contributions_paused',503);
    return json(await insertSample(db,owner,JSON.parse(await read(request,8192))),201);
  }
  if(path==='/samples'&&request.method==='GET') {
    const before=Number(url.searchParams.get('before')??Number.MAX_SAFE_INTEGER);
    if(!Number.isSafeInteger(before)||before<1) fail('invalid_cursor');
    const rows=await db.prepare('SELECT r.sequence,r.id,r.created,s.payload FROM registry r LEFT JOIN samples s ON s.id=r.id WHERE r.owner=? AND r.sequence<? ORDER BY r.sequence DESC LIMIT 60').bind(owner,before).all();
    return json({samples:rows.results.map(x=>({id:x.id,created:x.created,sample:x.payload?JSON.parse(x.payload):null})),next_cursor:rows.results.length===60?rows.results.at(-1).sequence:null});
  }
  if(path.startsWith('/samples/')&&request.method==='DELETE') {
    await withdrawSample(db,owner,path.slice(9));
    return json({ok:true});
  }
  if(path==='/account'&&request.method==='DELETE') {
    await db.batch([db.prepare('INSERT OR IGNORE INTO deletions(id,created) SELECT id,? FROM registry WHERE owner=?').bind(Date.now(),owner),db.prepare('DELETE FROM samples WHERE owner=?').bind(owner),db.prepare('DELETE FROM registry WHERE owner=?').bind(owner),db.prepare('DELETE FROM consent WHERE owner=?').bind(owner)]);
    await env.PURCHASES.prepare('DELETE FROM account_links WHERE uid=? AND NOT EXISTS(SELECT 1 FROM cashfree_orders WHERE uid=?)').bind(purchaseOwner,purchaseOwner).run();
    // Payment records are retained for purchase restoration/refunds; no library data exists here.
    return json({ok:true});
  }
  fail('not_found',404);
}
export default {
  async fetch(request,env) {
    try { return await route(request,env); }
    catch(error) { return json({error:error.status?error.message:'service_unavailable'},error.status??503); }
  },
  async scheduled(_event,env) {
    const before=Date.now()-30*86400000;
    await env.CONTRIBUTIONS.batch([env.CONTRIBUTIONS.prepare('DELETE FROM samples WHERE created<?').bind(before),env.CONTRIBUTIONS.prepare('DELETE FROM daily WHERE day<?').bind(new Date(before).toISOString().slice(0,10))]);
    await env.PURCHASES.prepare('UPDATE cashfree_orders SET session=NULL WHERE expires<? AND session IS NOT NULL').bind(Date.now()).run();
    await env.PURCHASES.prepare('DELETE FROM cashfree_orders WHERE created<? AND NOT EXISTS(SELECT 1 FROM cashfree_payments p WHERE p.order_id=cashfree_orders.id) AND NOT EXISTS(SELECT 1 FROM cashfree_refunds r WHERE r.order_id=cashfree_orders.id)').bind(Date.now()-90*86400000).run();
    await env.PURCHASES.prepare('DELETE FROM request_limits WHERE day<?').bind(new Date(before).toISOString().slice(0,10)).run();
  }
};
