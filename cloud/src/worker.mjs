import {createRemoteJWKSet, jwtVerify, importJWK, SignJWT} from 'jose';
import {checkoutPage} from './checkout.mjs';

const encoder = new TextEncoder();
const googleKeys = createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
export const PRODUCTS = Object.freeze({xl: 500, xxl: 1000});
const categories = new Set(['recipe','article','tutorial','place','general']);
const json = (data, status=200) => new Response(JSON.stringify(data), {status, headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff'}});
function fail(code, status=400) { throw Object.assign(new Error(code), {status}); }
export async function digest(value) { return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))), n=>n.toString(16).padStart(2,'0')).join(''); }
async function hmac(secret, body) {
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(body))),n=>n.toString(16).padStart(2,'0')).join('');
}
export async function validSignature(secret, body, supplied) {
  if (!secret || !/^[a-f0-9]{64}$/i.test(supplied??'')) return false;
  const expected=await hmac(secret,body); let difference=0;
  for(let i=0;i<64;i++) difference |= expected.charCodeAt(i)^supplied.toLowerCase().charCodeAt(i);
  return difference===0;
}
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
async function razor(env,path,{method='GET',body}={}) {
  if(!env.RAZORPAY_KEY_ID||!env.RAZORPAY_KEY_SECRET) fail('checkout_not_configured',503);
  const response=await fetch(`https://api.razorpay.com/v1/${path}`,{method,headers:{authorization:`Basic ${btoa(`${env.RAZORPAY_KEY_ID}:${env.RAZORPAY_KEY_SECRET}`)}`,'content-type':'application/json'},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(12000)});
  if(!response.ok) fail('payment_provider_unavailable',503);
  return response.json();
}
export async function effectiveTier(db,uid) {
  const rows=await db.prepare('SELECT o.tier FROM payments p JOIN orders o ON o.id=p.order_id WHERE o.uid=? AND p.captured=1 AND p.refunded=0').bind(uid).all();
  return rows.results.some(x=>x.tier==='xxl')?'xxl':rows.results.some(x=>x.tier==='xl')?'xl':'free';
}
async function entitlement(env,uid,purchaseOwner) {
  const tier=await effectiveTier(env.PURCHASES,purchaseOwner);
  const key=await importJWK(JSON.parse(env.ENTITLEMENT_PRIVATE_JWK),'EdDSA');
  const token=await new SignJWT({tier,version:1}).setProtectedHeader({alg:'EdDSA',kid:env.KEY_ID??'v1'}).setSubject(uid).setAudience('dev.linqo.linqo').setIssuer('linqo-cloud').setIssuedAt().sign(key);
  return {token};
}
export async function recordPayment(env,payment) {
  if (!env.RAZORPAY_KEY_ID?.startsWith('rzp_live_')) fail('live_payment_required',503);
  if(!payment?.id || !/^[a-zA-Z0-9_]+$/.test(payment.id) || !payment.order_id) fail('invalid_payment');
  const order=await env.PURCHASES.prepare('SELECT * FROM orders WHERE id=?').bind(payment.order_id).first();
  // Ignore payments from unrelated products on the same merchant account.
  if(!order) return;
  if(payment.amount!==order.cents || payment.currency!==order.currency || PRODUCTS[order.tier]!==order.cents) fail('payment_mismatch');
  if(!['captured','refunded'].includes(payment.status)) return;
  const refund=payment.status==='refunded'||Number(payment.amount_refunded)>0?1:0;
  await env.PURCHASES.prepare('INSERT INTO payments(id,order_id,refunded,captured) VALUES(?,?,?,1) ON CONFLICT(id) DO UPDATE SET refunded=MAX(payments.refunded,excluded.refunded),captured=1').bind(payment.id,order.id,refund).run();
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
  if(path==='/checkout'&&request.method==='GET') return new Response(checkoutPage,{headers:{'content-type':'text/html;charset=utf-8','cache-control':'no-store','referrer-policy':'no-referrer','x-frame-options':'DENY','content-security-policy':"default-src 'self'; script-src 'unsafe-inline' https://checkout.razorpay.com; style-src 'unsafe-inline'; frame-src https://api.razorpay.com https://checkout.razorpay.com; connect-src 'self' https://*.razorpay.com; img-src 'self' data: https://*.razorpay.com; base-uri 'none'; form-action https://*.razorpay.com"}});
  if(['/checkout/session','/checkout/verify'].includes(path)&&request.method==='POST') {
    const value=JSON.parse(await read(request));
    if(typeof value.session!=='string'||value.session.length>200) fail('invalid_session',401);
    const order=await env.PURCHASES.prepare('SELECT * FROM orders WHERE session=? AND created>?').bind(await digest(value.session),Date.now()-30*60000).first();
    if(!order) fail('checkout_expired',401);
    if(path.endsWith('/session')) return json({order_id:order.id,key_id:env.RAZORPAY_KEY_ID,amount:order.cents,currency:order.currency,tier:order.tier});
    if(!await validSignature(env.RAZORPAY_KEY_SECRET,`${order.id}|${value.payment_id}`,value.signature)) fail('invalid_payment',401);
    const payment=await razor(env,`payments/${encodeURIComponent(value.payment_id)}`);
    if(payment.order_id!==order.id) fail('payment_mismatch');
    await recordPayment(env,payment);
    if(payment.status!=='captured') fail('payment_pending',409);
    return json({ok:true});
  }
  if(path==='/health'&&request.method==='GET') return json({ok:true,payments_enabled:env.PAYMENTS_ENABLED==='true',contributions_enabled:env.CONTRIBUTIONS_ENABLED==='true'});
  if(path==='/webhooks/razorpay'&&request.method==='POST') {
    const raw=await read(request,65536);
    if(!await validSignature(env.RAZORPAY_WEBHOOK_SECRET,raw,request.headers.get('x-razorpay-signature'))) fail('invalid_signature',401);
    const event=JSON.parse(raw), id=request.headers.get('x-razorpay-event-id');
    if(!id||id.length>200) fail('invalid_event');
    if(await env.PURCHASES.prepare('SELECT id FROM events WHERE id=?').bind(id).first()) return json({ok:true});
    const payment=event.payload?.payment?.entity;
    if(['payment.captured','order.paid','refund.processed'].includes(event.event)&&payment) {
      // Fetch provider state even for signed events: handles delayed/out-of-order refunds.
      const current=await razor(env,`payments/${encodeURIComponent(payment.id)}`);
      await recordPayment(env,current);
    } else if(event.event==='refund.processed'&&event.payload?.refund?.entity?.payment_id) {
      await recordPayment(env,await razor(env,`payments/${encodeURIComponent(event.payload.refund.entity.payment_id)}`));
    }
    await env.PURCHASES.prepare('INSERT OR IGNORE INTO events VALUES(?,?)').bind(id,Date.now()).run();
    return json({ok:true});
  }
  const {uid,purchaseOwner}=await identity(request,env);
  if(path==='/entitlement'&&request.method==='GET') return json(await entitlement(env,uid,purchaseOwner));
  if(path==='/orders'&&request.method==='POST') {
    if(env.PAYMENTS_ENABLED!=='true'||!env.RAZORPAY_KEY_ID?.startsWith('rzp_live_')) fail('checkout_not_live',503);
    const {tier}=JSON.parse(await read(request)); if(!Object.hasOwn(PRODUCTS,tier)) fail('invalid_product');
    const day=new Date().toISOString().slice(0,10);
    const limit=await env.PURCHASES.prepare('INSERT INTO request_limits(owner,day,count) VALUES(?,?,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1 WHERE count<10 RETURNING count').bind(purchaseOwner,day).first();
    if(!limit) fail('try_tomorrow',429);
    const order=await razor(env,'orders',{method:'POST',body:{amount:PRODUCTS[tier],currency:'USD',receipt:crypto.randomUUID(),notes:{product:tier}}});
    if(order.amount!==PRODUCTS[tier]||order.currency!=='USD') fail('payment_mismatch',502);
    const session=crypto.randomUUID()+crypto.randomUUID();
    await env.PURCHASES.prepare('INSERT INTO orders VALUES(?,?,?,?,?,?,?)').bind(order.id,purchaseOwner,tier,PRODUCTS[tier],'USD',Date.now(),await digest(session)).run();
    return json({checkout_url:`${url.origin}/checkout#${session}`});
  }
  if(path==='/orders/verify'&&request.method==='POST') {
    const value=JSON.parse(await read(request));
    const order=await env.PURCHASES.prepare('SELECT * FROM orders WHERE id=? AND uid=?').bind(value.order_id??'',purchaseOwner).first();
    if(!order || !await validSignature(env.RAZORPAY_KEY_SECRET,`${order.id}|${value.payment_id}`,value.signature)) fail('invalid_payment',401);
    const payment=await razor(env,`payments/${encodeURIComponent(value.payment_id)}`);
    if(payment.order_id!==order.id) fail('payment_mismatch');
    await recordPayment(env,payment);
    return json(await entitlement(env,uid,purchaseOwner));
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
    await env.PURCHASES.prepare('DELETE FROM account_links WHERE uid=? AND NOT EXISTS(SELECT 1 FROM orders WHERE uid=?)').bind(purchaseOwner,purchaseOwner).run();
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
    await env.PURCHASES.prepare('DELETE FROM request_limits WHERE day<?').bind(new Date(before).toISOString().slice(0,10)).run();
  }
};
