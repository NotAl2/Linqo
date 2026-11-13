import {digest,hmac,fail} from './crypto.mjs';

export const PRODUCTS=Object.freeze({xl:44900,xxl:64900});
export async function productPrice(db,owner,tier) {
  if(tier==='xxl') {
    const offer=await db.prepare('SELECT minor FROM account_offers WHERE uid=? AND enabled=1').bind(owner).first();
    if(offer?.minor===100) return 100;
  }
  return PRODUCTS[tier];
}
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const orderPattern=/^lq_[ps]_[a-f0-9-]{36}$/;
const environments=new Set(['sandbox','production']);
const apiVersion='2025-01-01';
export function minor(value) {
  if(typeof value!=='number'||!Number.isFinite(value)||value<0) return null;
  const result=Math.round(value*100);
  return Number.isSafeInteger(result)&&Math.abs(value*100-result)<0.000001?result:null;
}
function id(value) {
  if(typeof value==='number'&&Number.isSafeInteger(value)&&value>0) return String(value);
  return typeof value==='string'&&/^[1-9][0-9]{0,39}$/.test(value)?value:null;
}
function credentials(env,mode) {
  if(!environments.has(mode)) fail('checkout_not_live',503);
  const prefix=mode==='sandbox'?'CASHFREE_TEST_':'CASHFREE_';
  const app=env[prefix+'APP_ID'],secret=env[prefix+'SECRET_KEY'];
  if(typeof app!=='string'||!app.trim()||typeof secret!=='string'||secret.length<16) fail('checkout_not_live',503);
  return {app,secret};
}
function origin(env) {
  try {
    const url=new URL(env.CHECKOUT_ORIGIN);
    if(url.protocol!=='https:'||url.username||url.password||url.port||url.pathname!=='/'||url.search||url.hash) throw Error();
    return url.origin;
  } catch { fail('checkout_not_live',503); }
}
export function checkoutReady(env) {
  if(env.PAYMENTS_ENABLED!=='true') return false;
  try {
    credentials(env,env.CASHFREE_MODE);origin(env);
    return env.CASHFREE_MODE==='sandbox'||env.CASHFREE_LIVE_APPROVED==='true';
  } catch {return false;}
}
export async function verifyCashfreeSignature(env,mode,raw,timestamp,supplied,now=Date.now()) {
  if(!/^\d{13}$/.test(timestamp??'')||Number(timestamp)>now+300000||!/^[A-Za-z0-9+/]{43}=$/.test(supplied??'')) return false;
  let secret;try{({secret}=credentials(env,mode));}catch{return false;}
  const hex=await hmac(secret,timestamp+raw);
  const expected=btoa(String.fromCharCode(...hex.match(/../g).map(n=>parseInt(n,16))));
  let diff=0;for(let i=0;i<expected.length;i++) diff|=expected.charCodeAt(i)^supplied.charCodeAt(i);
  // Delayed genuine retries are safe: immutable order/payment/refund IDs make
  // processing idempotent. Reject future timestamps, not old signed deliveries.
  return diff===0;
}
async function api(env,mode,path,{method='GET',body,requestId,timeout=8000}={},fetcher=fetch) {
  const {app,secret}=credentials(env,mode);
  const base=mode==='sandbox'?'https://sandbox.cashfree.com/pg':'https://api.cashfree.com/pg';
  let response;
  try {
    // Workers supports manual, not error; reject 3xx below without forwarding keys.
    response=await fetcher(base+path,{method,redirect:'manual',signal:AbortSignal.timeout(timeout),headers:{
      'content-type':'application/json','x-client-id':app,'x-client-secret':secret,'x-api-version':apiVersion,
      ...(requestId?{'x-idempotency-key':requestId}:{}),
    },...(body?{body:JSON.stringify(body)}:{})});
  } catch (error) {
    const reason=['TimeoutError','AbortError','TypeError'].includes(error?.name)?error.name:'network';
    console.warn('cashfree_provider_failure',mode,reason);
    fail('payment_provider_unavailable',503);
  }
  if(!response.ok) {
    // Status only: never log provider bodies, contact fields or credentials.
    console.warn('cashfree_provider_failure',mode,response.status);
    fail('payment_provider_unavailable',503);
  }
  // Provider responses contain contact data. Never log or persist the raw body.
  const reader=response.body.getReader();let bytes=0,text='';const decoder=new TextDecoder();
  while(true){const {done,value}=await reader.read();if(done)break;bytes+=value.length;if(bytes>262144){await reader.cancel();fail('payment_provider_unavailable',503);}text+=decoder.decode(value,{stream:true});}
  try{return JSON.parse(text+decoder.decode());}catch{fail('payment_provider_unavailable',503);}
}
function responseFor(row,key,env) {
  return {provider:'cashfree',tier:row.tier,amount_minor:row.minor,currency:'INR',order_id:row.id,
    sandbox:row.environment==='sandbox',expires_at:row.expires,checkout_url:`${origin(env)}/checkout/${key}`};
}
export async function startCheckout(env,owner,value,now=Date.now(),fetcher=fetch) {
  if(!checkoutReady(env)) fail('checkout_not_live',503);
  if(env.CASHFREE_ACCEPTANCE_OWNER&&env.CASHFREE_ACCEPTANCE_OWNER!==owner) fail('checkout_not_live',503);
  if(!value||Object.keys(value).some(k=>!['tier','phone','request_id'].includes(k))||!Object.hasOwn(PRODUCTS,value.tier)) fail('invalid_product');
  if(!uuid.test(value.request_id??'')) fail('invalid_purchase_request');
  if(typeof value.phone!=='string'||!/^\+[1-9][0-9]{7,14}$/.test(value.phone)) fail('invalid_checkout_phone');
  const db=env.PURCHASES,mode=env.CASHFREE_MODE;
  let row=await db.prepare('SELECT * FROM cashfree_orders WHERE uid=? AND request_id=?').bind(owner,value.request_id).first();
  // A deterministic opaque checkout key survives an API timeout without storing
  // the bearer value. The HMAC secret is separate from provider credentials.
  if((env.ACCOUNT_HMAC_SECRET?.length??0)<32) fail('identity_not_configured',503);
  const key=await hmac(env.ACCOUNT_HMAC_SECRET,`checkout:${owner}:${value.request_id}`);
  if(row&&(row.tier!==value.tier||row.environment!==mode||row.expires<=now||row.minor!==await productPrice(db,owner,value.tier))) fail('purchase_request_expired',409);
  if(!row){
    const day=new Date(now).toISOString().slice(0,10);
    const allowed=await db.prepare('INSERT INTO request_limits(owner,day,count) VALUES(?,?,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1 WHERE count<10 RETURNING count').bind(owner,day).first();
    if(!allowed) fail('try_tomorrow',429);
    const order=`lq_${mode==='sandbox'?'s':'p'}_${value.request_id}`;
    await db.prepare(`INSERT OR IGNORE INTO cashfree_orders(id,uid,request_id,tier,minor,currency,environment,created,expires,checkout_key)
      VALUES(?,?,?,?,?,'INR',?,?,?,?)`).bind(order,owner,value.request_id,value.tier,await productPrice(db,owner,value.tier),mode,now,now+3600000,await digest(key)).run();
    row=await db.prepare('SELECT * FROM cashfree_orders WHERE uid=? AND request_id=?').bind(owner,value.request_id).first();
    // UUID collisions from another account must not reuse or reveal its order.
    if(!row) fail('invalid_purchase_request',409);
  }
  if(row.session) return responseFor(row,key,env);
  const result=await api(env,mode,'/orders',{method:'POST',requestId:value.request_id,body:{
    order_id:row.id,order_amount:row.minor/100,order_currency:'INR',
    customer_details:{customer_id:(await digest(owner)).slice(0,40),customer_phone:value.phone},
    order_expiry_time:new Date(row.expires).toISOString(),
    order_meta:{return_url:`${origin(env)}/checkout/return`,notify_url:`${origin(env)}/webhooks/cashfree/${mode}`},
    order_note:`Linqo ${row.tier.toUpperCase()} one-time unlock`,
  }},fetcher);
  if(result.order_id!==row.id||minor(result.order_amount)!==row.minor||result.order_currency!=='INR'||result.order_status!=='ACTIVE'||
    typeof result.payment_session_id!=='string'||!/^session_[A-Za-z0-9_-]{10,4096}$/.test(result.payment_session_id)) fail('invalid_provider_order',503);
  await db.prepare('UPDATE cashfree_orders SET session=? WHERE id=? AND session IS NULL').bind(result.payment_session_id,row.id).run();
  return responseFor(row,key,env);
}
export async function effectiveCashfreeTier(db,owner) {
  const rows=await db.prepare(`SELECT o.tier FROM cashfree_orders o WHERE o.uid=? AND o.environment='production'
    AND EXISTS(SELECT 1 FROM cashfree_payments p WHERE p.order_id=o.id AND p.environment=o.environment AND p.captured=1
      AND COALESCE((SELECT SUM(r.minor) FROM cashfree_refunds r WHERE r.environment=p.environment AND r.payment_id=p.id AND r.order_id=o.id),0)<o.minor)`).bind(owner).all();
  return rows.results.some(x=>x.tier==='xxl')?'xxl':rows.results.some(x=>x.tier==='xl')?'xl':'free';
}
function validateOrder(row,data) {
  if(data?.order_id!==row.id||minor(data.order_amount)!==row.minor||data.order_currency!=='INR') fail('payment_order_mismatch');
}
export async function capturePayment(db,row,payment) {
  if(payment?.payment_status!=='SUCCESS') return;
  const paymentId=id(payment.cf_payment_id);
  if(!paymentId||payment.is_captured===false||minor(payment.payment_amount)!==row.minor||payment.payment_currency!=='INR') fail('payment_order_mismatch');
  const existing=await db.prepare('SELECT order_id,minor FROM cashfree_payments WHERE environment=? AND id=?').bind(row.environment,paymentId).first();
  if(existing&&(existing.order_id!==row.id||existing.minor!==row.minor)) fail('payment_order_mismatch');
  await db.prepare('INSERT OR IGNORE INTO cashfree_payments(id,environment,order_id,minor,captured) VALUES(?,?,?,?,1)').bind(paymentId,row.environment,row.id,row.minor).run();
  const stored=await db.prepare('SELECT order_id FROM cashfree_payments WHERE environment=? AND id=?').bind(row.environment,paymentId).first();
  if(stored.order_id!==row.id) fail('payment_order_mismatch');
}
export async function captureRefund(db,row,refund,now=Date.now()) {
  if(refund?.refund_status!=='SUCCESS') return;
  const refundId=id(refund.cf_refund_id),paymentId=id(refund.cf_payment_id),amount=minor(refund.refund_amount);
  if(!refundId||!paymentId||refund.order_id!==row.id||refund.refund_currency!=='INR'||amount===null||amount<=0||amount>row.minor) fail('refund_order_mismatch');
  const existing=await db.prepare('SELECT order_id,payment_id,minor FROM cashfree_refunds WHERE environment=? AND id=?').bind(row.environment,refundId).first();
  if(existing&&(existing.order_id!==row.id||existing.payment_id!==paymentId||existing.minor!==amount)) fail('refund_order_mismatch');
  // Refunds are retained even before a delayed successful-payment event.
  await db.prepare('INSERT OR IGNORE INTO cashfree_refunds VALUES(?,?,?,?,?,?)').bind(refundId,row.environment,row.id,paymentId,amount,now).run();
}
export async function recordCashfreeEvent(env,mode,event,now=Date.now()) {
  if(!environments.has(mode)) fail('not_found',404);
  if(!['PAYMENT_SUCCESS_WEBHOOK','REFUND_STATUS_WEBHOOK','AUTO_REFUND_STATUS_WEBHOOK'].includes(event?.type)) return {ok:true,ignored:'not_success_or_refund'};
  const refund=event.data?.refund??event.data?.auto_refund;
  const orderId=refund?.order_id??event.data?.order?.order_id;
  if(typeof orderId!=='string'||!orderPattern.test(orderId)) return {ok:true,ignored:'unknown_order'};
  const row=await env.PURCHASES.prepare('SELECT * FROM cashfree_orders WHERE id=? AND environment=?').bind(orderId,mode).first();
  if(!row) return {ok:true,ignored:'unknown_order'};
  if(event.type==='PAYMENT_SUCCESS_WEBHOOK') {
    validateOrder(row,event.data.order);
    await capturePayment(env.PURCHASES,row,event.data.payment);
  } else await captureRefund(env.PURCHASES,row,refund,now);
  return {ok:true,sandbox:mode==='sandbox'};
}
export async function reconcileOrder(env,row,fetcher=fetch,now=Date.now()) {
  // Signed webhooks normally do the work. Bounded owner-only API reconciliation
  // recovers missing deliveries on Restore purchase, including completed refunds.
  const remote=await api(env,row.environment,`/orders/${row.id}`,{timeout:2500},fetcher);
  validateOrder(row,remote);
  if(remote.order_status==='PAID') {
    const payments=await api(env,row.environment,`/orders/${row.id}/payments`,{timeout:2500},fetcher);
    const refunds=await api(env,row.environment,`/orders/${row.id}/refunds`,{timeout:2500},fetcher);
    if(!Array.isArray(payments)||!Array.isArray(refunds)||payments.length>100||refunds.length>100) fail('payment_provider_unavailable',503);
    // Apply refund tombstones first so a crash cannot temporarily regrant access.
    for(const refund of refunds) await captureRefund(env.PURCHASES,row,refund,now);
    for(const payment of payments) await capturePayment(env.PURCHASES,row,payment);
  }
  await env.PURCHASES.prepare('UPDATE cashfree_orders SET checked=? WHERE id=?').bind(now,row.id).run();
}
export async function reconcileOwner(env,owner,fetcher=fetch,now=Date.now()) {
  const rows=await env.PURCHASES.prepare(`SELECT * FROM cashfree_orders WHERE uid=? AND checked<?
    AND (expires>? OR EXISTS(SELECT 1 FROM cashfree_payments p WHERE p.order_id=cashfree_orders.id AND p.captured=1))
    ORDER BY checked,created DESC LIMIT 1`).bind(owner,now-60000,now-30*86400000).all();
  for(const row of rows.results) {
    try {credentials(env,row.environment);} catch {continue;}
    // Reserve before network work; repeated restore taps cannot hammer the API.
    const reserved=await env.PURCHASES.prepare('UPDATE cashfree_orders SET checked=? WHERE id=? AND checked<?').bind(now,row.id,now-60000).run();
    if(!reserved.meta.changes) continue;
    try{await reconcileOrder(env,row,fetcher,now);}catch{/* Preserve the known ledger during outages. */}
  }
}
export async function checkoutPage(env,key,now=Date.now()) {
  if(!checkoutReady(env)) fail('checkout_not_live',503);
  const row=await env.PURCHASES.prepare('SELECT * FROM cashfree_orders WHERE checkout_key=?').bind(await digest(key)).first();
  if(!row||row.expires<=now||!row.session||row.environment!==env.CASHFREE_MODE) fail('checkout_expired',410);
  if(env.CASHFREE_ACCEPTANCE_OWNER&&row.uid!==env.CASHFREE_ACCEPTANCE_OWNER) fail('checkout_expired',410);
  const nonce=btoa(crypto.randomUUID());
  const html=`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Linqo checkout</title>
<style nonce="${nonce}">body{font:18px system-ui;background:#faf5ff;color:#301047;max-width:32rem;padding:2rem;margin:4vh auto;line-height:1.6}button{font:inherit;padding:1rem 2rem;border:0;border-radius:2rem;background:#7034cb;color:white}a{color:#7034cb}</style>
<h1>Linqo ${row.tier.toUpperCase()}</h1><p>₹${row.minor/100} once · ${row.tier==='xl'?'500 saves and 30 collections':'Unlimited saves and collections; compatible custom-model imports'}</p>
${row.environment==='sandbox'?'<p><strong>Sandbox test. No real unlock or payment. Use Cashfree test details only.</strong></p>':''}
${row.environment==='production'&&env.CASHFREE_ACCEPTANCE_OWNER?'<p><strong>Private live acceptance test. This charges real money. Refund completion depends on Cashfree and your bank; merchant processing fees may not be returned.</strong></p>':''}
<p>Your purchase belongs to the Google account used in Linqo. Cashfree handles payment details. Return to Linqo and choose Restore purchase after checkout.</p>
<p><a href="https://linqo-app-notal2.web.app/purchases">Purchase and refund information</a></p><button id="pay" disabled>Continue to Cashfree</button><p id="status" role="status">Loading secure checkout…</p>
<script nonce="${nonce}" src="https://sdk.cashfree.com/js/v3/cashfree.js"></script><script nonce="${nonce}">
const button=document.getElementById('pay'),status=document.getElementById('status');
if(typeof Cashfree==='function'){const cf=Cashfree({mode:${JSON.stringify(row.environment)}});button.disabled=false;status.textContent='Review the amount before paying.';button.onclick=async()=>{button.disabled=true;try{await cf.checkout({paymentSessionId:${JSON.stringify(row.session)},redirectTarget:'_self'});}catch{status.textContent='Checkout could not open. Return to Linqo and try again.';button.disabled=false;}};}else{status.textContent='Checkout could not load. Return to Linqo and try again.';}
</script></html>`;
  return new Response(html,{headers:{'content-type':'text/html;charset=utf-8','cache-control':'no-store','referrer-policy':'no-referrer',
    'x-content-type-options':'nosniff','content-security-policy':`default-src 'none'; script-src 'nonce-${nonce}' https://sdk.cashfree.com; style-src 'nonce-${nonce}'; connect-src https://*.cashfree.com; frame-src https://*.cashfree.com; img-src https://*.cashfree.com data:; frame-ancestors 'none'; base-uri 'none'; form-action https://*.cashfree.com`}});
}
export function checkoutReturn() {
  return new Response('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Return to Linqo</title><h1>Return to Linqo</h1><p>Choose Restore purchase using the same Google account. This page does not confirm payment. Pending or cancelled payments do not unlock a tier.</p></html>',{headers:{'content-type':'text/html;charset=utf-8','cache-control':'no-store','referrer-policy':'no-referrer','content-security-policy':"default-src 'none'; frame-ancestors 'none'; base-uri 'none'"}});
}
