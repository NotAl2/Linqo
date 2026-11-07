import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createHmac} from 'node:crypto';
import worker,{PRODUCTS,validSignature,recordPayment,effectiveTier,insertSample,validateSample,withdrawSample,purchaseAccount,verifyFirebaseIdentityToken} from '../src/worker.mjs';
import {generateKeyPair,exportJWK,createLocalJWKSet,SignJWT,jwtVerify} from 'jose';

function database(schema){
  const sqlite=new DatabaseSync(':memory:');sqlite.exec('PRAGMA foreign_keys=ON');sqlite.exec(readFileSync(new URL(schema,import.meta.url),'utf8'));
  const adapter={prepare(sql){let params=[];return {bind(...values){params=values;return this;},async run(){const r=sqlite.prepare(sql).run(...params);return {meta:{changes:Number(r.changes)}};},async first(){return sqlite.prepare(sql).get(...params)??null;},async all(){return {results:sqlite.prepare(sql).all(...params)};}};},async batch(commands){return Promise.all(commands.map(x=>x.run()));}};
  return {db:adapter,sqlite};
}
const sample={version:1,category:'recipe',source:'Ingredients: one cup oats and one cup milk. Mix the oats and milk together in a bowl. Chill overnight and serve cold the next morning.',output:'{"type":"recipe","ingredients":["one cup oats","one cup milk"]}',model:'qwen3-0.6b',schema:'evidence-v1'};
test('fixed products cannot be overridden by client prices',()=>assert.deepEqual(PRODUCTS,{xl:500,xxl:1000}));
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
test('captured ledger restores highest tier; duplicate and delayed capture cannot undo refund',async()=>{
  const {db,sqlite}=database('../migrations/purchases/0001.sql');
  try{
    sqlite.prepare('INSERT INTO orders VALUES(?,?,?,?,?,?,?)').run('order_xl','user','xl',500,'USD',0,'s1');
    sqlite.prepare('INSERT INTO orders VALUES(?,?,?,?,?,?,?)').run('order_xxl','user','xxl',1000,'USD',0,'s2');
    const env={PURCHASES:db,RAZORPAY_KEY_ID:'rzp_live_fixture'};
    assert.equal(await effectiveTier(db,'user'),'free');
    const xl={id:'pay_xl',order_id:'order_xl',amount:500,currency:'USD',status:'captured'};
    await recordPayment(env,xl);await recordPayment(env,xl);
    assert.equal(await effectiveTier(db,'user'),'xl');
    const xxl={id:'pay_xxl',order_id:'order_xxl',amount:1000,currency:'USD',status:'captured'};
    await recordPayment(env,xxl);assert.equal(await effectiveTier(db,'user'),'xxl');
    await recordPayment(env,{...xxl,status:'refunded'});await recordPayment(env,xxl);
    assert.equal(await effectiveTier(db,'user'),'xl');
    assert.equal(await effectiveTier(db,'another'),'free');
    await assert.rejects(recordPayment(env,{...xl,amount:1}),/payment_mismatch/);
    await recordPayment(env,{...xl,status:'refunded'});assert.equal(await effectiveTier(db,'user'),'free');
  } finally{sqlite.close();}
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
test('test-mode provider credentials cannot grant production entitlements',async()=>{
  await assert.rejects(recordPayment({RAZORPAY_KEY_ID:'rzp_test_fixture'},{}),/live_payment_required/);
});
test('public health declares disabled features; webhook and checkout reject forged requests',async()=>{
  const env={PAYMENTS_ENABLED:'false',CONTRIBUTIONS_ENABLED:'false',RAZORPAY_WEBHOOK_SECRET:'s'.repeat(32)};
  const health=await worker.fetch(new Request('https://test/health'),env);
  assert.deepEqual(await health.json(),{ok:true,payments_enabled:false,contributions_enabled:false});
  const response=await worker.fetch(new Request('https://test/webhooks/razorpay',{method:'POST',body:'{}'}),env);
  assert.equal(response.status,401);
});
test('authenticated API integrates consent, order ownership, capture, restoration and refunds with mocked providers',async()=>{
  const purchases=database('../migrations/purchases/0001.sql'),contributions=database('../migrations/contributions/0001.sql');
  const google=await generateKeyPair('RS256'),license=await generateKeyPair('EdDSA',{extractable:true});
  const jwk=await exportJWK(google.publicKey);jwk.kid='route-fixture';
  const env={PURCHASES:purchases.db,CONTRIBUTIONS:contributions.db,FIREBASE_PROJECT_ID:'route-fixture',ACCOUNT_HMAC_SECRET:'a'.repeat(32),CONTRIBUTOR_HMAC_SECRET:'c'.repeat(32),ENTITLEMENT_PRIVATE_JWK:JSON.stringify(await exportJWK(license.privateKey)),RAZORPAY_KEY_ID:'rzp_live_route_fixture',RAZORPAY_KEY_SECRET:'r'.repeat(32),RAZORPAY_WEBHOOK_SECRET:'w'.repeat(32),PAYMENTS_ENABLED:'true',CONTRIBUTIONS_ENABLED:'true'};
  let refunded=false;const originalFetch=globalThis.fetch;
  globalThis.fetch=async (input,options)=>{
    const url=new URL(typeof input==='string'?input:input.url??input);
    if(url.hostname==='www.googleapis.com'&&url.pathname.includes('securetoken'))return new Response(JSON.stringify({keys:[jwk]}),{headers:{'content-type':'application/json'}});
    if(url.hostname==='api.razorpay.com'&&url.pathname==='/v1/orders'){
      const body=JSON.parse(options.body);assert.equal(body.amount,500);assert.equal(body.currency,'USD');
      return new Response(JSON.stringify({id:'order_route',amount:500,currency:'USD'}));
    }
    if(url.hostname==='api.razorpay.com'&&url.pathname==='/v1/payments/pay_route')return new Response(JSON.stringify({id:'pay_route',order_id:'order_route',amount:500,currency:'USD',status:refunded?'refunded':'captured'}));
    throw Error('Unexpected provider request');
  };
  async function token(uid){return new SignJWT({email_verified:true,firebase:{sign_in_provider:'google.com',identities:{'google.com':['same-google-identity']}}}).setProtectedHeader({alg:'RS256',kid:jwk.kid}).setSubject(uid).setIssuer('https://securetoken.google.com/route-fixture').setAudience('route-fixture').setIssuedAt().setExpirationTime('5m').sign(google.privateKey);}
  async function request(path,{uid='original',method='GET',body}={}){
    const response=await worker.fetch(new Request('https://linqo.test'+path,{method,headers:{authorization:'Bearer '+await token(uid),'content-type':'application/json'},body:body?JSON.stringify(body):undefined}),env);
    const value=await response.json();assert.ok(response.ok,JSON.stringify(value));return value;
  }
  try{
    await request('/consent',{method:'PUT',body:{enabled:true,version:1}});
    const example=await request('/samples',{method:'POST',body:sample});
    assert.equal((await request('/samples')).samples.length,1);
    await request('/samples/'+example.id,{method:'DELETE'});
    assert.equal((await request('/samples')).samples.length,0);
    const checkout=await request('/orders',{method:'POST',body:{tier:'xl',amount:1}});
    assert.match(checkout.checkout_url,/https:\/\/linqo.test\/checkout#/);
    const signature=createHmac('sha256',env.RAZORPAY_KEY_SECRET).update('order_route|pay_route').digest('hex');
    const purchased=await request('/orders/verify',{method:'POST',body:{order_id:'order_route',payment_id:'pay_route',signature}});
    assert.equal((await jwtVerify(purchased.token,license.publicKey)).payload.tier,'xl');
    const restored=await request('/entitlement',{uid:'recreated'});
    const claims=(await jwtVerify(restored.token,license.publicKey)).payload;
    assert.equal(claims.sub,'recreated');assert.equal(claims.tier,'xl');
    refunded=true;
    const raw=JSON.stringify({event:'refund.processed',payload:{refund:{entity:{payment_id:'pay_route'}}}});
    const refund=await worker.fetch(new Request('https://linqo.test/webhooks/razorpay',{method:'POST',headers:{'x-razorpay-event-id':'event_route','x-razorpay-signature':createHmac('sha256',env.RAZORPAY_WEBHOOK_SECRET).update(raw).digest('hex')},body:raw}),env);
    assert.equal(refund.status,200);
    const after=(await jwtVerify((await request('/entitlement',{uid:'recreated'})).token,license.publicKey)).payload;
    assert.equal(after.tier,'free');
    await request('/account',{uid:'recreated',method:'DELETE'});
  }finally{globalThis.fetch=originalFetch;purchases.sqlite.close();contributions.sqlite.close();}
});
