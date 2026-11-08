import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createHmac} from 'node:crypto';
import worker,{PRODUCTS,validSignature,effectiveTier,insertSample,validateSample,withdrawSample,purchaseAccount,verifyFirebaseIdentityToken} from '../src/worker.mjs';
import {startShopPurchase,recordShopEvent,shopReady} from '../src/bmc_shop.mjs';
import {generateKeyPair,exportJWK,createLocalJWKSet,SignJWT,jwtVerify} from 'jose';

function database(schema){
  const sqlite=new DatabaseSync(':memory:');sqlite.exec('PRAGMA foreign_keys=ON');sqlite.exec(readFileSync(new URL(schema,import.meta.url),'utf8'));if(schema.includes('/purchases/'))sqlite.exec(readFileSync(new URL('../migrations/purchases/0002_shop.sql',import.meta.url),'utf8'));
  const adapter={prepare(sql){let params=[];return {bind(...values){params=values;return this;},async run(){const r=sqlite.prepare(sql).run(...params);return {meta:{changes:Number(r.changes)}};},async first(){return sqlite.prepare(sql).get(...params)??null;},async all(){return {results:sqlite.prepare(sql).all(...params)};}};},async batch(commands){return Promise.all(commands.map(x=>x.run()));}};
  return {db:adapter,sqlite};
}
const sample={version:1,category:'recipe',source:'Ingredients: one cup oats and one cup milk. Mix the oats and milk together in a bowl. Chill overnight and serve cold the next morning.',output:'{"type":"recipe","ingredients":["one cup oats","one cup milk"]}',model:'qwen3-0.6b',schema:'evidence-v1'};
test('fixed products cannot be overridden by client prices',()=>assert.deepEqual(PRODUCTS,{xl:500,xxl:700}));
test('Firebase identity verifies signature, project, expiry, provider and verified email',async()=>{
  const {privateKey,publicKey}=await generateKeyPair('RS256');
  const jwk=await exportJWK(publicKey);jwk.kid='fixture';const keys=createLocalJWKSet({keys:[jwk]});
  async function token({project='linqo',issuer='https://securetoken.google.com/linqo',email=true,provider='google.com',expires='5m'}={}){
    return new SignJWT({email_verified:email,firebase:{sign_in_provider:provider,identities:{'google.com':['stable-google-subject']}}}).setProtectedHeader({alg:'RS256',kid:'fixture'}).setSubject('user').setIssuer(issuer).setAudience(project).setIssuedAt().setExpirationTime(expires).sign(privateKey);
  }
  assert.equal((await verifyFirebaseIdentityToken(await token(),'linqo',keys)).sub,'user');
  for(const changed of [{project:'other'},{issuer:'https://attacker.example'},{email:false},{provider:'password'},{expires:-100}]){
    await assert.rejects(verifyFirebaseIdentityToken(await token(changed),'linqo',keys),error=>error.status===401);
  }
  await assert.rejects(verifyFirebaseIdentityToken('forged','linqo',keys),error=>error.status===401);
});
test('account recreation and concurrent old tokens resolve to one immutable purchase account',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql');
  try{
    assert.equal(await purchaseAccount(db,'google-key','original'),'original');
    const owners=await Promise.all([purchaseAccount(db,'google-key','recreated'),purchaseAccount(db,'google-key','original')]);
    assert.deepEqual(owners,['original','original']);
    assert.equal(await purchaseAccount(db,'another-google','someone-else'),'someone-else');
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM account_links').get().n,2);
  }finally{sqlite.close();}
});
test('webhook signatures use the exact raw body and reject malformed or changed input',async()=>{
  const body='{"x":1}',secret='s'.repeat(32),signature=createHmac('sha256',secret).update(body).digest('hex');
  assert.equal(await validSignature(secret,body,signature),true);
  assert.equal(await validSignature(secret,body+' ',signature),false);
  assert.equal(await validSignature(secret,body,'a'),false);
  assert.equal(await validSignature('',body,signature),false);
});
const shopConfig={PAYMENTS_ENABLED:'true',BMC_XL_PRODUCT_ID:'101',BMC_XXL_PRODUCT_ID:'102',BMC_WEBHOOK_SECRET:'w'.repeat(32)};
function shopEvent(session,{id=1,type='extra_purchase.created',live=true,created=Math.floor(Date.now()/1000)}={}) {
  return {event_id:id,type,live_mode:live,created,attempt:1,data:{id,object:'payment',status:'succeeded',refunded:'false',amount:session.amount_cents/100,currency:'USD',support_type:'Extra',created_at:created,supporter_email:'untrusted@example.com',extras:[{id:session.tier==='xl'?101:102,object:'extra',quantity:1,amount:session.amount_cents/100,currency:'USD',question_answers:[session.claim_code]}]}};
}
test('Shop purchases restore the highest account-bound tier and refunds dominate delayed captures',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql'); const env={...shopConfig,PURCHASES:db};
  try{
    const xl=await startShopPurchase(env,'buyer','xl');const event=shopEvent(xl);
    assert.equal((await recordShopEvent(env,event)).linked,true);
    await recordShopEvent(env,event);assert.equal(await effectiveTier(db,'buyer'),'xl');
    const xxl=await startShopPurchase(env,'buyer','xxl');const upgraded=shopEvent(xxl,{id:2});
    await recordShopEvent(env,upgraded);assert.equal(await effectiveTier(db,'buyer'),'xxl');
    await recordShopEvent(env,{...upgraded,type:'extra_purchase.refunded'});
    await recordShopEvent(env,upgraded);assert.equal(await effectiveTier(db,'buyer'),'xl');
    await recordShopEvent(env,{...event,type:'extra_purchase.refunded'});
    assert.equal(await effectiveTier(db,'buyer'),'free');assert.equal(await effectiveTier(db,'another'),'free');
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM bmc_purchases').get().n,2);
  }finally{sqlite.close();}
});
test('refund-before-purchase, reused codes, donations and dashboard tests cannot grant an unlock',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql');const env={...shopConfig,PURCHASES:db};
  try{
    const session=await startShopPurchase(env,'buyer','xl');const event=shopEvent(session);
    await recordShopEvent(env,{...event,type:'donation.created'});
    await recordShopEvent(env,{...event,live_mode:false});assert.equal(await effectiveTier(db,'buyer'),'free');
    await recordShopEvent(env,{...event,type:'extra_purchase.refunded'});
    await recordShopEvent(env,event);assert.equal(await effectiveTier(db,'buyer'),'free');
    const valid=await startShopPurchase(env,'buyer','xxl');
    await Promise.all([recordShopEvent(env,shopEvent(valid,{id:2})),recordShopEvent(env,shopEvent(valid,{id:3}))]);
    assert.equal(sqlite.prepare("SELECT count(*) AS n FROM bmc_purchases WHERE uid IS NOT NULL AND tier='xxl'").get().n,1);
    assert.equal(await effectiveTier(db,'buyer'),'xxl');
  }finally{sqlite.close();}
});
test('product IDs, prices, currencies and the pre-issued purchase code are mandatory',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql');const env={...shopConfig,PURCHASES:db};
  try{
    const session=await startShopPurchase(env,'buyer','xl');
    const missing=shopEvent(session);missing.data.extras[0].question_answers=[];
    await recordShopEvent(env,missing);assert.equal(await effectiveTier(db,'buyer'),'free');
    await recordShopEvent(env,{...shopEvent(session),type:'extra_purchase.updated'});
    assert.equal(await effectiveTier(db,'buyer'),'xl');
    const cheap=shopEvent(session,{id:4});cheap.data.extras[0].amount=0.01;
    await assert.rejects(recordShopEvent(env,cheap),/shop_price_mismatch/);
    const foreign=shopEvent(session,{id:5});foreign.data.currency='INR';
    await assert.rejects(recordShopEvent(env,foreign),/invalid_shop_event/);
    const unknown=shopEvent(session,{id:6});unknown.data.extras[0].id=999;
    assert.equal((await recordShopEvent(env,unknown)).ignored,'other_shop_item');
    const mixed=shopEvent(session,{id:7});mixed.data.extras.push({...mixed.data.extras[0]});
    assert.equal((await recordShopEvent(env,mixed)).ignored,'unsupported_cart');
    const other=await startShopPurchase(env,'someone-else','xxl');
    const wrong=shopEvent(other,{id:8});wrong.data.extras[0].id=101;wrong.data.extras[0].amount=5;wrong.data.amount=5;
    await recordShopEvent(env,wrong);assert.equal(await effectiveTier(db,'someone-else'),'free');
  }finally{sqlite.close();}
});
test('checkout readiness, rate limiting, expiry and delayed webhook delivery are enforced',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql');const env={...shopConfig,PURCHASES:db};const now=Date.now();
  try{
    assert.equal(shopReady({...env,BMC_WEBHOOK_SECRET:''}),false);
    assert.equal(shopReady({...env,BMC_XXL_PRODUCT_ID:'101'}),false);
    await assert.rejects(startShopPurchase({...env,PAYMENTS_ENABLED:'false'},'a','xl'),/checkout_not_live/);
    await assert.rejects(startShopPurchase(env,'a','free'),/invalid_product/);
    const session=await startShopPurchase(env,'buyer','xl',now-31*86400000);
    await recordShopEvent(env,shopEvent(session),now);assert.equal(await effectiveTier(db,'buyer'),'free');
    const old=await startShopPurchase(env,'delayed','xxl',now-31*86400000);
    await recordShopEvent(env,shopEvent(old,{id:2,created:Math.floor((now-2*86400000)/1000)}),now);
    assert.equal(await effectiveTier(db,'delayed'),'xxl');
    for(let i=0;i<10;i++) await startShopPurchase(env,'limited','xl');
    await assert.rejects(startShopPurchase(env,'limited','xl'),error=>error.status===429);
  }finally{sqlite.close();}
});
test('replacement migration refuses to discard legacy financial records',()=>{
  const db=new DatabaseSync(':memory:');
  try{
    db.exec(readFileSync(new URL('../migrations/purchases/0001.sql',import.meta.url),'utf8'));
    db.prepare('INSERT INTO orders VALUES(?,?,?,?,?,?,?)').run('legacy','u','xl',500,'USD',0,'session');
    assert.throws(()=>db.exec(readFileSync(new URL('../migrations/purchases/0002_shop.sql',import.meta.url),'utf8')),/CHECK constraint failed/);
    assert.equal(db.prepare('SELECT count(*) AS n FROM orders').get().n,1);
  }finally{db.close();}
});

test('contribution consent, duplicate, daily caps and deletion tombstones are atomic SQL rules',async()=>{
  const {db,sqlite}=database('../migrations/contributions/0001.sql');const now=Date.now();
  try{
    await assert.rejects(insertSample(db,'owner',sample,now),/contribution_not_accepted/);
    sqlite.prepare('INSERT INTO consent VALUES(?,1,1,?)').run('owner',now);
    const first=await insertSample(db,'owner',sample,now);
    await assert.rejects(insertSample(db,'owner',sample,now),/contribution_not_accepted/);
    await insertSample(db,'owner',{...sample,source:sample.source+' Add cinnamon.'},now);
    await assert.rejects(insertSample(db,'owner',{...sample,source:sample.source+' Add honey.'},now),/contribution_not_accepted/);
    await withdrawSample(db,'owner',first.id);
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM deletions').get().n,1);
    // Deleting uploads must not reset daily intake counters.
    await assert.rejects(insertSample(db,'owner',sample,now),/contribution_not_accepted/);
    sqlite.prepare('UPDATE consent SET enabled=0').run();
    await assert.rejects(insertSample(db,'owner',sample,now+86400000),/contribution_not_accepted/);
  }finally{sqlite.close();}
});
test('server expiry preserves owner deletion ability for exported examples',async()=>{
  const {db,sqlite}=database('../migrations/contributions/0001.sql');
  try{
    sqlite.prepare('INSERT INTO consent VALUES(?,1,1,?)').run('owner',Date.now());
    const row=await insertSample(db,'owner',sample);
    sqlite.prepare('DELETE FROM samples').run();
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM deletions').get().n,0);
    await withdrawSample(db,'owner',row.id);
    assert.equal(sqlite.prepare('SELECT count(*) AS n FROM deletions').get().n,1);
  }finally{sqlite.close();}
});
test('global contribution cap and storage ceiling reject intake without affecting purchases',async()=>{
  const {db,sqlite}=database('../migrations/contributions/0001.sql');const now=Date.now(),day=new Date(now).toISOString().slice(0,10);
  try{
    sqlite.prepare('INSERT INTO consent VALUES(?,1,1,?)').run('owner',now);
    sqlite.prepare('INSERT INTO daily VALUES(?,?,100)').run('*',day);
    await assert.rejects(insertSample(db,'owner',sample,now),/contribution_not_accepted/);
    sqlite.prepare('DELETE FROM daily').run();sqlite.prepare('UPDATE intake_budget SET bytes=100000000').run();
    await assert.rejects(insertSample(db,'owner',sample,now),/contribution_not_accepted/);
  }finally{sqlite.close();}
});
test('sample validation rejects identifiers, unknown fields and oversized content',()=>{
  assert.ok(validateSample(sample).bytes<8192);
  assert.throws(()=>validateSample({...sample,email:'a@b.com'}),/invalid_sample/);
  assert.throws(()=>validateSample({...sample,source:sample.source+' alice@example.com'}),/sensitive_sample/);
  assert.throws(()=>validateSample({...sample,output:'x'.repeat(9000)}),/payload_too_large/);
});
test('health stays disabled until Shop is configured and forged webhooks are rejected',async()=>{
  const env={PAYMENTS_ENABLED:'false',CONTRIBUTIONS_ENABLED:'false',BMC_WEBHOOK_SECRET:'s'.repeat(32)};
  assert.deepEqual(await (await worker.fetch(new Request('https://test/health'),env)).json(),{ok:true,payments_enabled:false,contributions_enabled:false});
  assert.equal((await worker.fetch(new Request('https://test/webhooks/buymeacoffee',{method:'POST',body:'{}'}),env)).status,401);
});
test('retired checkout routes return 404 without identity or database work',async()=>{
  for(const [path,method] of [['/checkout','GET'],['/orders','POST'],['/orders/verify','POST']]) {
    const response=await worker.fetch(new Request('https://test'+path,{method}),{});
    assert.equal(response.status,404);
    assert.deepEqual(await response.json(),{error:'not_found'});
  }
});
test('authenticated Google identity, signed Shop webhook, restoration and refunds work end to end with fixtures',async()=>{
  const purchases=database('../migrations/purchases/0001.sql'),contributions=database('../migrations/contributions/0001.sql');
  const google=await generateKeyPair('RS256'),license=await generateKeyPair('EdDSA',{extractable:true});
  const jwk=await exportJWK(google.publicKey);jwk.kid='route-fixture';
  const env={...shopConfig,PURCHASES:purchases.db,CONTRIBUTIONS:contributions.db,FIREBASE_PROJECT_ID:'route-fixture',ACCOUNT_HMAC_SECRET:'a'.repeat(32),CONTRIBUTOR_HMAC_SECRET:'c'.repeat(32),ENTITLEMENT_PRIVATE_JWK:JSON.stringify(await exportJWK(license.privateKey)),CONTRIBUTIONS_ENABLED:'true'};
  const originalFetch=globalThis.fetch;
  globalThis.fetch=async input=>{
    const url=new URL(typeof input==='string'?input:input.url??input);
    if(url.hostname==='www.googleapis.com'&&url.pathname.includes('securetoken'))return new Response(JSON.stringify({keys:[jwk]}),{headers:{'content-type':'application/json'}});
    throw Error('Unexpected provider request');
  };
  async function token(uid){return new SignJWT({email_verified:true,firebase:{sign_in_provider:'google.com',identities:{'google.com':['same-google-identity']}}}).setProtectedHeader({alg:'RS256',kid:jwk.kid}).setSubject(uid).setIssuer('https://securetoken.google.com/route-fixture').setAudience('route-fixture').setIssuedAt().setExpirationTime('5m').sign(google.privateKey);}
  async function request(path,{uid='original',method='GET',body}={}){
    const response=await worker.fetch(new Request('https://linqo.test'+path,{method,headers:{authorization:'Bearer '+await token(uid),'content-type':'application/json'},body:body?JSON.stringify(body):undefined}),env);
    const value=await response.json();assert.ok(response.ok,JSON.stringify(value));return value;
  }
  async function webhook(event){const raw=JSON.stringify(event);return worker.fetch(new Request('https://linqo.test/webhooks/buymeacoffee',{method:'POST',headers:{'x-signature-sha256':createHmac('sha256',env.BMC_WEBHOOK_SECRET).update(raw).digest('hex')},body:raw}),env);}
  try{
    await request('/consent',{method:'PUT',body:{enabled:true,version:1}});
    const example=await request('/samples',{method:'POST',body:sample});
    assert.equal((await request('/samples')).samples.length,1);
    await request('/samples/'+example.id,{method:'DELETE'});assert.equal((await request('/samples')).samples.length,0);
    const checkout=await request('/shop/start',{method:'POST',body:{tier:'xl',amount:1}});
    assert.equal(checkout.shop_url,'https://buymeacoffee.com/notal2/e/101');assert.equal(checkout.amount_cents,500);
    assert.equal((await webhook(shopEvent(checkout,{live:false}))).status,200);
    assert.equal((await jwtVerify((await request('/entitlement')).token,license.publicKey)).payload.tier,'free');
    assert.equal((await webhook(shopEvent(checkout))).status,200);
    const claims=(await jwtVerify((await request('/entitlement',{uid:'recreated'})).token,license.publicKey)).payload;
    assert.equal(claims.sub,'recreated');assert.equal(claims.tier,'xl');
    await webhook({...shopEvent(checkout),type:'extra_purchase.refunded'});
    assert.equal((await jwtVerify((await request('/entitlement',{uid:'recreated'})).token,license.publicKey)).payload.tier,'free');
    await request('/account',{uid:'recreated',method:'DELETE'});
    assert.equal((await request('/entitlement',{uid:'another-recreated'})).token.split('.').length,3);
  }finally{globalThis.fetch=originalFetch;purchases.sqlite.close();contributions.sqlite.close();}
});
