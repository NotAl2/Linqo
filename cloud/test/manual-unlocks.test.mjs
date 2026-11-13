import test from 'node:test';
import assert from 'node:assert/strict';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {accountCode,effectiveTier} from '../src/manual-unlocks.mjs';
import {manualUnlock} from '../tools/manual-unlocks.mjs';
import {accountAccess} from '../tools/account-access.mjs';
import {productPrice} from '../src/cashfree.mjs';

function database({upgrade=true}={}) {
  const sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');
  for(const name of ['0001.sql','0002_shop.sql','0003_cashfree.sql',...(upgrade?['0004_manual_unlocks.sql','0005_manual_prices.sql','0006_private_offers_gifts.sql','0007_polar_webhooks.sql','0008_polar_fulfillment.sql','0009_polar_checkout_requests.sql']:[])])sql.exec(readFileSync(new URL('../migrations/purchases/'+name,import.meta.url),'utf8'));
  const db={prepare(text){let params=[];return {bind(...values){params=values;return this;},async run(){return {meta:{changes:Number(sql.prepare(text).run(...params).changes)}};},async first(){return sql.prepare(text).get(...params)??null;},async all(){return {results:sql.prepare(text).all(...params)};}};}};
  const query=text=>sql.prepare(text).all();
  return {sql,db,query};
}

test('private offers and gifts require admin confirmation and remain account-bound',async()=>{
  const {sql,db,query}=database();
  try {
    const code=await accountCode(db,'buyer'),other=await accountCode(db,'other');
    assert.throws(()=>accountAccess('offer',{code},query));
    assert.throws(()=>accountAccess('offer',{code:'LQ-'+'0'.repeat(32),confirm:true},query));
    assert.throws(()=>accountAccess('offer',{code:"bad'; DROP TABLE account_offers;",confirm:true},query));
    accountAccess('offer',{code,confirm:true},query);
    assert.equal(await productPrice(db,'buyer','xxl'),100);
    assert.equal(await productPrice(db,'buyer','xl'),44900);
    assert.equal(await productPrice(db,'other','xxl'),64900);
    assert.equal(await effectiveTier(db,'buyer'),'free');
    accountAccess('remove-offer',{code,confirm:true},query);
    assert.equal(await productPrice(db,'buyer','xxl'),64900);
    const gift={code,tier:'xxl',reference:'private-gift-001',confirm:true};
    accountAccess('gift',gift,query);accountAccess('gift',gift,query);
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM gift_grants').get().n,1);
    assert.equal(await effectiveTier(db,'buyer'),'xxl');
    assert.equal(await effectiveTier(db,'other'),'free');
    assert.throws(()=>accountAccess('gift',{...gift,code:other},query));
    accountAccess('revoke-gift',{reference:gift.reference,confirm:true},query);
    assert.equal(await effectiveTier(db,'buyer'),'free');
    assert.throws(()=>accountAccess('gift',gift,query));
  } finally {sql.close();}
});
test('migration retains old-priced orders, captured payments, refunds and foreign keys',()=>{
  const {sql}=database({upgrade:false});
  try {
    sql.exec("INSERT INTO cashfree_orders VALUES('old','buyer','request','xl',44900,'INR','production',1,2,NULL,'old-key',0); INSERT INTO cashfree_payments VALUES('1','production','old',44900,1); INSERT INTO cashfree_refunds VALUES('2','production','old','1',1000,3)");
    const before=['cashfree_orders','cashfree_payments','cashfree_refunds'].map(t=>sql.prepare('SELECT * FROM '+t).all());
    sql.exec(readFileSync(new URL('../migrations/purchases/0004_manual_unlocks.sql',import.meta.url),'utf8'));
    assert.deepEqual(['cashfree_orders','cashfree_payments','cashfree_refunds'].map(t=>sql.prepare('SELECT * FROM '+t).all()),before);
    assert.deepEqual(sql.prepare('PRAGMA foreign_key_check').all(),[]);
    sql.exec("INSERT INTO cashfree_orders VALUES('new','buyer','new-request','xl',39900,'INR','sandbox',1,2,NULL,'new-key',0)");
    sql.exec(readFileSync(new URL('../migrations/purchases/0005_manual_prices.sql',import.meta.url),'utf8'));
    const retained=['cashfree_orders','cashfree_payments','cashfree_refunds'].map(t=>sql.prepare('SELECT * FROM '+t).all());
    sql.exec(readFileSync(new URL('../migrations/purchases/0006_private_offers_gifts.sql',import.meta.url),'utf8'));
    assert.deepEqual(['cashfree_orders','cashfree_payments','cashfree_refunds'].map(t=>sql.prepare('SELECT * FROM '+t).all()),retained);
    assert.deepEqual(sql.prepare('PRAGMA foreign_key_check').all(),[]);
    sql.exec("INSERT INTO cashfree_orders VALUES('discount','buyer','discount-request','xxl',100,'INR','production',1,2,NULL,'discount-key',0)");
  } finally {sql.close();}
});
test('manual grants require verification, minimum amount and an existing private account code',async()=>{
  const {sql,db,query}=database();
  try {
    const code=await accountCode(db,'buyer');assert.match(code,/^LQ-[a-f0-9]{32}$/);
    assert.equal(await accountCode(db,'buyer'),code);
    assert.notEqual(await accountCode(db,'other'),code);
    const options={code,tier:'xl',reference:'payment-123','amount-minor':'499',verified:true};
    for(const change of [{verified:false},{'amount-minor':'498'},{tier:'xxl'},{code:'LQ-'+'0'.repeat(32)},{reference:"bad'; DROP TABLE manual_grants;"}])assert.throws(()=>manualUnlock('grant',{...options,...change},query));
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM manual_grants').get().n,0);
    manualUnlock('grant',options,query);manualUnlock('grant',options,query);
    assert.equal(sql.prepare('SELECT COUNT(*) n FROM manual_grants').get().n,1);
    assert.equal(await effectiveTier(db,'buyer'),'xl');assert.equal(await effectiveTier(db,'other'),'free');
    const other=await accountCode(db,'other');
    assert.throws(()=>manualUnlock('grant',{...options,code:other},query));
    assert.equal(await effectiveTier(db,'other'),'free');
  } finally {sql.close();}
});
test('updated USD amounts preserve older grants while accepting a 6.99 XXL grant',()=>{
  const {sql}=database({upgrade:false});
  try {
    sql.exec(readFileSync(new URL('../migrations/purchases/0004_manual_unlocks.sql',import.meta.url),'utf8'));
    sql.exec("INSERT INTO manual_accounts VALUES('buyer','LQ-old'); INSERT INTO manual_grants VALUES('old-xl','buyer','xl',400,'USD',1,NULL,''); INSERT INTO manual_grants VALUES('old-xxl','buyer','xxl',700,'USD',2,NULL,'')");
    const before=sql.prepare('SELECT * FROM manual_grants ORDER BY receipt_hash').all();
    sql.exec(readFileSync(new URL('../migrations/purchases/0005_manual_prices.sql',import.meta.url),'utf8'));
    assert.deepEqual(sql.prepare('SELECT * FROM manual_grants ORDER BY receipt_hash').all(),before);
    sql.exec("INSERT INTO manual_grants VALUES('new-xxl','buyer','xxl',699,'USD',3,NULL,'')");
    assert.deepEqual(sql.prepare('PRAGMA foreign_key_check').all(),[]);
  } finally {sql.close();}
});
test('revocation falls back across independent manual grants and Cashfree purchases',async()=>{
  const {sql,db,query}=database();
  try {
    const code=await accountCode(db,'buyer');
    const base={code,verified:true};
    manualUnlock('grant',{...base,tier:'xl',reference:'payment-xl','amount-minor':'499'},query);
    manualUnlock('grant',{...base,tier:'xxl',reference:'payment-xxl','amount-minor':'699'},query);
    assert.equal(await effectiveTier(db,'buyer'),'xxl');
    assert.throws(()=>manualUnlock('revoke',{reference:'payment-xxl',reason:'refund'},query));
    manualUnlock('revoke',{reference:'payment-xxl',reason:'refund',confirm:true},query);
    assert.equal(await effectiveTier(db,'buyer'),'xl');
    assert.throws(()=>manualUnlock('grant',{...base,tier:'xxl',reference:'payment-xxl','amount-minor':'699'},query));
    manualUnlock('revoke',{reference:'payment-xl',reason:'chargeback',confirm:true},query);
    assert.equal(await effectiveTier(db,'buyer'),'free');
    sql.exec("INSERT INTO cashfree_orders VALUES('live','buyer','r','xl',39900,'INR','production',1,2,NULL,'key',0); INSERT INTO cashfree_payments VALUES('1','production','live',39900,1)");
    assert.equal(await effectiveTier(db,'buyer'),'xl');
    assert.deepEqual(sql.prepare('PRAGMA foreign_key_check').all(),[]);
  } finally {sql.close();}
});
