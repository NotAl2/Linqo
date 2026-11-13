import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import worker,{PRODUCTS,insertSample,validateSample,withdrawSample,purchaseAccount,verifyFirebaseIdentityToken} from '../src/worker.mjs';
import {generateKeyPair,exportJWK,createLocalJWKSet,SignJWT} from 'jose';

function database(schema){
  const sqlite=new DatabaseSync(':memory:');sqlite.exec('PRAGMA foreign_keys=ON');sqlite.exec(readFileSync(new URL(schema,import.meta.url),'utf8'));if(schema.includes('/purchases/')) for(const name of ['0002_shop.sql','0003_cashfree.sql','0004_manual_unlocks.sql','0005_manual_prices.sql','0006_private_offers_gifts.sql','0007_polar_webhooks.sql','0008_polar_fulfillment.sql','0009_polar_checkout_requests.sql']) sqlite.exec(readFileSync(new URL('../migrations/purchases/'+name,import.meta.url),'utf8'));
  const adapter={prepare(sql){let params=[];return {bind(...values){params=values;return this;},async run(){const r=sqlite.prepare(sql).run(...params);return {meta:{changes:Number(r.changes)}};},async first(){return sqlite.prepare(sql).get(...params)??null;},async all(){return {results:sqlite.prepare(sql).all(...params)};}};},async batch(commands){return Promise.all(commands.map(x=>x.run()));}};
  return {db:adapter,sqlite};
}
const sample={version:1,category:'recipe',source:'Ingredients: one cup oats and one cup milk. Mix the oats and milk together in a bowl. Chill overnight and serve cold the next morning.',output:'{"type":"recipe","ingredients":["one cup oats","one cup milk"]}',model:'qwen3-0.6b',schema:'evidence-v1'};
test('fixed products cannot be overridden by client prices',()=>assert.deepEqual(PRODUCTS,{xl:44900,xxl:64900}));
test('checkout origin has public product and policy information without authentication or payment activation',async()=>{
  const response=await worker.fetch(new Request('https://linqo.test/'),{});
  assert.equal(response.status,200);
  assert.match(response.headers.get('content-type'),/text\/html/);
  const html=await response.text();
  for(const value of ['NotAl2','15 calendar days','₹449','₹649','active development','not enabled','/purchases','/privacy','/terms','/support'])assert.ok(html.includes(value));
  assert.ok(!html.includes('<script'));
  const enabled={PAYMENTS_ENABLED:'true',CASHFREE_MODE:'production',CASHFREE_LIVE_APPROVED:'true',CHECKOUT_ORIGIN:'https://linqo.test',CASHFREE_APP_ID:'fixture',CASHFREE_SECRET_KEY:'fixture-secret-key'};
  const live=await (await worker.fetch(new Request('https://linqo.test/'),enabled)).text();
  assert.match(live,/Live checkout is available through account-bound links/);
  assert.ok(!live.includes('Public live checkout is not enabled'));
  const sandbox=await (await worker.fetch(new Request('https://linqo.test/'),{...enabled,CASHFREE_MODE:'sandbox',CASHFREE_TEST_APP_ID:'fixture',CASHFREE_TEST_SECRET_KEY:'fixture-secret-key'})).text();
  assert.ok(sandbox.includes('Public live checkout is not enabled'));
  assert.equal((await worker.fetch(new Request('https://linqo.test/',{method:'POST'}),{})).status,404);
});
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
test('Cashfree defaults stay disabled; old provider and checkout routes are gone',async()=>{
  const env={PAYMENTS_ENABLED:'false',CASHFREE_MODE:'sandbox',CONTRIBUTIONS_ENABLED:'false'};
  assert.deepEqual(await (await worker.fetch(new Request('https://test/health'),env)).json(),{ok:true,provider:'cashfree',sandbox:true,payments_enabled:false,contributions_enabled:false});
  for(const [path,method] of [['/shop/start','POST'],['/webhooks/buymeacoffee','POST'],['/checkout','GET'],['/orders','POST'],['/orders/verify','POST']]){
    assert.equal((await worker.fetch(new Request('https://test'+path,{method}),env)).status,404);
  }
  assert.equal((await worker.fetch(new Request('https://test/webhooks/cashfree/sandbox',{method:'POST',body:'{}'}),env)).status,401);
});

test('health reports the configured Polar provider without enabling unapproved checkout',async()=>{
 const response=await worker.fetch(new Request('https://linqo.test/health'),{PAYMENTS_PROVIDER:'polar',PAYMENTS_ENABLED:'true',POLAR_LIVE_APPROVED:'false'});
 const body=await response.json();assert.equal(body.provider,'polar');assert.equal(body.sandbox,false);assert.equal(body.payments_enabled,false);
});
