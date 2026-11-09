import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createHmac,randomUUID} from 'node:crypto';
import {generateKeyPair,exportJWK,SignJWT,jwtVerify} from 'jose';
import worker,{purchaseAccount} from '../src/worker.mjs';
import {startCheckout,checkoutReady,verifyCashfreeSignature,recordCashfreeEvent,effectiveCashfreeTier,reconcileOwner,checkoutPage} from '../src/cashfree.mjs';

function database(){
  const sqlite=new DatabaseSync(':memory:');sqlite.exec('PRAGMA foreign_keys=ON');
  for(const name of ['0001.sql','0002_shop.sql','0003_cashfree.sql'])sqlite.exec(readFileSync(new URL('../migrations/purchases/'+name,import.meta.url),'utf8'));
  const db={prepare(sql){let params=[];return {bind(...v){params=v;return this;},async run(){const r=sqlite.prepare(sql).run(...params);return {meta:{changes:Number(r.changes)}};},async first(){return sqlite.prepare(sql).get(...params)??null;},async all(){return {results:sqlite.prepare(sql).all(...params)};}};}};
  return {db,sqlite};
}
const config={PAYMENTS_ENABLED:'true',CASHFREE_MODE:'production',CASHFREE_LIVE_APPROVED:'true',
  CHECKOUT_ORIGIN:'https://linqo.test',ACCOUNT_HMAC_SECRET:'a'.repeat(32),CASHFREE_APP_ID:'production-fixture',CASHFREE_SECRET_KEY:'p'.repeat(32),
  CASHFREE_TEST_APP_ID:'sandbox-fixture',CASHFREE_TEST_SECRET_KEY:'s'.repeat(32)};
const json=value=>new Response(JSON.stringify(value),{headers:{'content-type':'application/json'}});
const createApi=async (_url,options)=>{const body=JSON.parse(options.body);return json({...body,order_status:'ACTIVE',payment_session_id:'session_fixture12345678'});};
const request=(tier='xl',request_id=randomUUID())=>({tier,request_id,phone:'+919876543210'});
async function start(env,owner='buyer',tier='xl'){return startCheckout(env,owner,request(tier),Date.now(),createApi);}
function payment(order,cf_payment_id='100') {return {type:'PAYMENT_SUCCESS_WEBHOOK',data:{order:{order_id:order.order_id,order_amount:order.amount_minor/100,order_currency:'INR'},payment:{cf_payment_id,payment_status:'SUCCESS',payment_amount:order.amount_minor/100,payment_currency:'INR',is_captured:true}}};}
function refund(order,{id='200',paymentId='100',amount=order.amount_minor/100,status='SUCCESS'}={}){return {type:'REFUND_STATUS_WEBHOOK',data:{refund:{cf_refund_id:id,cf_payment_id:paymentId,order_id:order.order_id,refund_amount:amount,refund_currency:'INR',refund_status:status}}};}

test('live readiness requires explicit approval, mode, origin and credentials',()=>{
  assert.equal(checkoutReady(config),true);
  for(const field of ['PAYMENTS_ENABLED','CASHFREE_LIVE_APPROVED'])assert.equal(checkoutReady({...config,[field]:'false'}),false);
  for(const field of ['CASHFREE_APP_ID','CASHFREE_SECRET_KEY'])assert.equal(checkoutReady({...config,[field]:''}),false);
  for(const url of ['http://linqo.test','https://user@linqo.test','https://linqo.test/path','https://linqo.test/?token=x'])assert.equal(checkoutReady({...config,CHECKOUT_ORIGIN:url}),false);
  assert.equal(checkoutReady({...config,CASHFREE_MODE:'other'}),false);
  assert.equal(checkoutReady({...config,CASHFREE_MODE:'sandbox',CASHFREE_LIVE_APPROVED:'false'}),true);
});
test('Cashfree signature is base64 HMAC of timestamp plus exact raw body; modes are isolated',async()=>{
  const raw='{"amount":5.00}',timestamp=String(Date.now());
  const signature=createHmac('sha256',config.CASHFREE_SECRET_KEY).update(timestamp+raw).digest('base64');
  assert.equal(await verifyCashfreeSignature(config,'production',raw,timestamp,signature),true);
  assert.equal(await verifyCashfreeSignature(config,'sandbox',raw,timestamp,signature),false);
  for(const [body,ts,sig] of [[raw+' ',timestamp,signature],[raw,'0',signature],[raw,timestamp,'notbase64'],[raw,String(Date.now()+999999),signature]])assert.equal(await verifyCashfreeSignature(config,'production',body,ts,sig),false);
  const old=String(Date.now()-86400000),oldSig=createHmac('sha256',config.CASHFREE_SECRET_KEY).update(old+raw).digest('base64');
  assert.equal(await verifyCashfreeSignature(config,'production',raw,old,oldSig),true);
});
test('server prices, Google ownership, idempotency and contact minimisation survive retries',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const value=request();let calls=0;
    const fetcher=async(url,opts)=>{calls++;assert.equal(url,'https://api.cashfree.com/pg/orders');assert.equal(opts.headers['x-idempotency-key'],value.request_id);const body=JSON.parse(opts.body);assert.equal(body.order_amount,449);assert.equal(body.order_currency,'INR');assert.equal(body.customer_details.customer_phone,value.phone);assert.ok(!JSON.stringify(body).includes('buyer'));return createApi(url,opts);};
    const first=await startCheckout(env,'buyer',value,Date.now(),fetcher);
    const second=await startCheckout(env,'buyer',value,Date.now(),fetcher);
    assert.deepEqual(first,second);assert.equal(calls,1);
    const row=sqlite.prepare('SELECT * FROM cashfree_orders').get();assert.equal(row.uid,'buyer');assert.ok(!JSON.stringify(row).includes(value.phone));assert.ok(!row.checkout_key.includes(new URL(first.checkout_url).pathname.split('/').at(-1)));
    await assert.rejects(startCheckout(env,'buyer',{...value,tier:'xxl'},Date.now(),fetcher),/purchase_request_expired/);
    await assert.rejects(startCheckout(env,'attacker',value,Date.now(),fetcher),/invalid_purchase_request/);
    for(const change of [{phone:'123'},{amount:1},{tier:'free'},{request_id:'same-id'}])await assert.rejects(startCheckout(env,'buyer',{...request(),...change},Date.now(),fetcher));
    assert.equal(sqlite.prepare('SELECT count(*) n FROM cashfree_orders').get().n,1);
  }finally{sqlite.close();}
});
test('provider outages preserve the request for retry without creating another order',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db},value=request();
  try{
    await assert.rejects(startCheckout(env,'buyer',value,Date.now(),async()=>{throw Error('offline');}),/payment_provider_unavailable/);
    const result=await startCheckout(env,'buyer',value,Date.now(),createApi);
    assert.equal(sqlite.prepare('SELECT count(*) n FROM cashfree_orders').get().n,1);
    assert.ok(result.checkout_url.startsWith('https://linqo.test/checkout/'));
    const wrong=async(url,opts)=>{const r=await (await createApi(url,opts)).json();return json({...r,order_amount:1});};
    await assert.rejects(startCheckout(env,'buyer',request(),Date.now(),wrong),/invalid_provider_order/);
  }finally{sqlite.close();}
});
test('purchase starts are capped and expire; page never proves payment',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const value=request(),session=await startCheckout(env,'buyer',value,Date.now()-7200000,createApi);
    await assert.rejects(startCheckout(env,'buyer',value,Date.now(),createApi),/purchase_request_expired/);
    await assert.rejects(checkoutPage(env,new URL(session.checkout_url).pathname.split('/').at(-1)),/checkout_expired/);
    for(let n=0;n<10;n++)await start(env,'limited');
    await assert.rejects(start(env,'limited'),e=>e.status===429);
    const checkout=await start(env,'page'),key=new URL(checkout.checkout_url).pathname.split('/').at(-1);
    const page=await checkoutPage(env,key);const html=await page.text();
    assert.equal(page.headers.get('cache-control'),'no-store');assert.equal(page.headers.get('referrer-policy'),'no-referrer');assert.ok(html.includes('sdk.cashfree.com/js/v3/cashfree.js'));assert.ok(!html.includes(config.CASHFREE_SECRET_KEY));
    await assert.rejects(checkoutPage({...env,PAYMENTS_ENABLED:'false'},key),/checkout_not_live/);
    assert.equal(await effectiveCashfreeTier(db,'page'),'free');
    const ret=await worker.fetch(new Request('https://linqo.test/checkout/return?status=SUCCESS'),env);assert.ok((await ret.text()).includes('does not confirm payment'));
  }finally{sqlite.close();}
});
test('captured live payments restore highest tier; refund IDs prevent replay and delayed regrant',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const xl=await start(env),xxl=await start(env,'buyer','xxl');
    await recordCashfreeEvent(env,'production',payment(xl));await recordCashfreeEvent(env,'production',payment(xl));
    await recordCashfreeEvent(env,'production',payment(xxl,'101'));assert.equal(await effectiveCashfreeTier(db,'buyer'),'xxl');
    await recordCashfreeEvent(env,'production',refund(xxl,{paymentId:'101'}));await recordCashfreeEvent(env,'production',payment(xxl,'101'));
    assert.equal(await effectiveCashfreeTier(db,'buyer'),'xl');
    await recordCashfreeEvent(env,'production',refund(xl,{id:'201',amount:200}));await recordCashfreeEvent(env,'production',refund(xl,{id:'201',amount:200}));
    assert.equal(await effectiveCashfreeTier(db,'buyer'),'xl');
    await recordCashfreeEvent(env,'production',refund(xl,{id:'202',amount:249}));assert.equal(await effectiveCashfreeTier(db,'buyer'),'free');
    assert.equal(await effectiveCashfreeTier(db,'attacker'),'free');
  }finally{sqlite.close();}
});
test('refund before payment stays revoked; canceled refunds and extra refunded attempts do not revoke another payment',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const xl=await start(env);await recordCashfreeEvent(env,'production',refund(xl));await recordCashfreeEvent(env,'production',payment(xl));assert.equal(await effectiveCashfreeTier(db,'buyer'),'free');
    const xxl=await start(env,'buyer','xxl');await recordCashfreeEvent(env,'production',payment(xxl,'102'));
    await recordCashfreeEvent(env,'production',refund(xxl,{id:'203',paymentId:'102',status:'CANCELLED'}));
    await recordCashfreeEvent(env,'production',refund(xxl,{id:'204',paymentId:'999'}));assert.equal(await effectiveCashfreeTier(db,'buyer'),'xxl');
  }finally{sqlite.close();}
});
test('sandbox, unknown, failed, forged-price and other-owner payment IDs cannot grant access',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const sandbox=await start({...env,CASHFREE_MODE:'sandbox'});await recordCashfreeEvent(env,'sandbox',payment(sandbox));assert.equal(await effectiveCashfreeTier(db,'buyer'),'free');
    assert.equal((await recordCashfreeEvent(env,'production',payment(sandbox))).ignored,'unknown_order');
    const xl=await start(env),event=payment(xl);event.data.payment.payment_status='PENDING';await recordCashfreeEvent(env,'production',event);assert.equal(await effectiveCashfreeTier(db,'buyer'),'free');
    for(const change of [{payment_amount:0.01},{payment_currency:'USD'},{is_captured:false}]){const bad=payment(xl);Object.assign(bad.data.payment,change);await assert.rejects(recordCashfreeEvent(env,'production',bad),/payment_order_mismatch/);}
    const bad=payment(xl);bad.data.order.order_amount=0.01;await assert.rejects(recordCashfreeEvent(env,'production',bad),/payment_order_mismatch/);
    await recordCashfreeEvent(env,'production',payment(xl));
    const other=await start(env,'someone-else');await assert.rejects(recordCashfreeEvent(env,'production',payment(other)),/payment_order_mismatch/);
    assert.equal(await effectiveCashfreeTier(db,'someone-else'),'free');
  }finally{sqlite.close();}
});
test('owner-only reconciliation recovers lost payment/refund delivery with bounded requests and preserves state on outage',async()=>{
  const {db,sqlite}=database(),env={...config,PURCHASES:db};
  try{
    const xl=await start(env);let refunded=false,calls=0;
    const fetcher=async url=>{calls++;if(url.endsWith('/payments'))return json([payment(xl).data.payment]);if(url.endsWith('/refunds'))return json(refunded?[refund(xl).data.refund]:[]);return json({...payment(xl).data.order,order_status:'PAID'});};
    await reconcileOwner(env,'attacker',fetcher);assert.equal(calls,0);
    const now=Date.now();await reconcileOwner(env,'buyer',fetcher,now);assert.equal(calls,3);assert.equal(await effectiveCashfreeTier(db,'buyer'),'xl');
    await reconcileOwner(env,'buyer',fetcher,now+1000);assert.equal(calls,3);
    await reconcileOwner(env,'buyer',async()=>{throw Error('offline');},now+61000);assert.equal(await effectiveCashfreeTier(db,'buyer'),'xl');
    refunded=true;await reconcileOwner(env,'buyer',fetcher,now+122000);assert.equal(await effectiveCashfreeTier(db,'buyer'),'free');
  }finally{sqlite.close();}
});
test('migration preserves Google identity and refuses to drop any Shop financial history',()=>{
  for(const table of ['bmc_purchases','bmc_refunds']){
    const sqlite=new DatabaseSync(':memory:');
    try{
      for(const name of ['0001.sql','0002_shop.sql'])sqlite.exec(readFileSync(new URL('../migrations/purchases/'+name,import.meta.url),'utf8'));
      sqlite.exec("INSERT INTO account_links VALUES('google-key','original')");
      if(table==='bmc_purchases')sqlite.exec("INSERT INTO bmc_purchases(id,tier,product_id,cents,currency,created) VALUES('paid','xl','101',500,'USD',0)");else sqlite.exec("INSERT INTO bmc_refunds VALUES('refund',0)");
      assert.throws(()=>sqlite.exec(readFileSync(new URL('../migrations/purchases/0003_cashfree.sql',import.meta.url),'utf8')),/CHECK constraint failed/);
      assert.equal(sqlite.prepare(`SELECT count(*) n FROM ${table}`).get().n,1);assert.equal(sqlite.prepare('SELECT uid FROM account_links').get().uid,'original');
    }finally{sqlite.close();}
  }
});
test('Google-authenticated checkout, signed Cashfree events, recreated-account restore and refund fallback route end to end',async()=>{
  const {db,sqlite}=database(),google=await generateKeyPair('RS256'),license=await generateKeyPair('EdDSA',{extractable:true});
  const jwk=await exportJWK(google.publicKey);jwk.kid='cashfree-route';
  const env={...config,PURCHASES:db,FIREBASE_PROJECT_ID:'cashfree-route',ENTITLEMENT_PRIVATE_JWK:JSON.stringify(await exportJWK(license.privateKey))};
  const originalFetch=globalThis.fetch;
  globalThis.fetch=async(input,opts)=>{const url=new URL(typeof input==='string'?input:input.url??input);if(url.hostname==='www.googleapis.com')return json({keys:[jwk]});if(opts?.method==='POST')return createApi(input,opts);throw Error('Provider reconciliation unavailable in this fixture');};
  async function auth(uid,provider='same-google'){return new SignJWT({email_verified:true,firebase:{sign_in_provider:'google.com',identities:{'google.com':[provider]}}}).setProtectedHeader({alg:'RS256',kid:jwk.kid}).setSubject(uid).setIssuer('https://securetoken.google.com/cashfree-route').setAudience('cashfree-route').setIssuedAt().setExpirationTime('5m').sign(google.privateKey);}
  async function call(path,{uid='original',method='GET',body,provider}={}){return worker.fetch(new Request('https://linqo.test'+path,{method,headers:{authorization:'Bearer '+await auth(uid,provider),'content-type':'application/json'},body:body?JSON.stringify(body):undefined}),env);}
  async function hook(event,sig){const raw=JSON.stringify(event),timestamp=String(Date.now());return worker.fetch(new Request('https://linqo.test/webhooks/cashfree/production',{method:'POST',headers:{'x-webhook-timestamp':timestamp,'x-webhook-signature':sig??createHmac('sha256',config.CASHFREE_SECRET_KEY).update(timestamp+raw).digest('base64')},body:raw}),env);}
  try{
    const response=await call('/checkout/start',{method:'POST',body:request()});assert.equal(response.status,200);const checkout=await response.json();
    assert.equal((await hook(payment(checkout),'forged')).status,401);
    assert.equal((await hook(payment(checkout))).status,200);
    const claims=async(uid,provider)=>{const result=await (await call('/entitlement',{uid,provider})).json();assert.equal(result.payments_enabled,true);assert.equal(result.sandbox,false);return (await jwtVerify(result.token,license.publicKey)).payload;};
    assert.equal((await claims('recreated')).tier,'xl');assert.equal((await claims('recreated')).sub,'recreated');
    assert.equal((await claims('other','other-google')).tier,'free');
    await hook(refund(checkout));assert.equal((await claims('original')).tier,'free');
    assert.equal(await purchaseAccount(db,'fixture-stable-google','first'),'first');assert.equal(await purchaseAccount(db,'fixture-stable-google','second'),'first');
  }finally{globalThis.fetch=originalFetch;sqlite.close();}
});
