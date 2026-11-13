import test from 'node:test';
import {DatabaseSync} from 'node:sqlite';
import {readFileSync} from 'node:fs';
import {createHmac} from 'node:crypto';
import assert from 'node:assert/strict';
import {polarSandboxReady,polarSandboxApi,validatePolarProduct,polarSandboxOwner,validPolarSandboxUrl,polarOrderTier,restorePolarSandbox,startPolarSandbox,polarLiveCatalog,receivePolarWebhook,POLAR_LIVE_PRODUCTS,POLAR_SANDBOX_PRODUCTS} from '../src/polar.mjs';
const env={POLAR_SANDBOX_ENABLED:'true',POLAR_ACCEPTANCE_OWNER:'buyer',POLAR_TEST_ACCESS_TOKEN:'test-only-token-placeholder',ACCOUNT_HMAC_SECRET:'x'.repeat(32)};
const json=value=>new Response(JSON.stringify(value));
test('sandbox requires owner restriction and credential',()=>{assert.equal(polarSandboxReady(env),true);for(const key of ['POLAR_SANDBOX_ENABLED','POLAR_ACCEPTANCE_OWNER','POLAR_TEST_ACCESS_TOKEN'])assert.equal(polarSandboxReady({...env,[key]:''}),false);});
test('provider transport rejects redirects, live URLs and oversized responses',async()=>{let calls=0;await assert.rejects(polarSandboxApi(env,'/v1/products/test',{},async(url,options)=>{calls++;assert.equal(new URL(url).host,'sandbox-api.polar.sh');assert.equal(options.redirect,'manual');assert.equal(options.headers['Polar-Version'],'2026-10');return new Response(null,{status:302});}),e=>e.status===503);assert.equal(calls,1);await assert.rejects(polarSandboxApi(env,'https://attacker.example'),e=>e.status===400);await assert.rejects(polarSandboxApi(env,'/v1/products/test',{},async()=>json('x'.repeat(524289))),e=>e.status===503);});
test('catalog rejects wrong price, tax and recurring products',()=>{const p={id:POLAR_SANDBOX_PRODUCTS.xl,is_archived:false,is_recurring:false,organization_id:'same',prices:[{is_archived:false,amount_type:'fixed',price_currency:'inr',price_amount:44900,tax_behavior:'inclusive'}]};assert.equal(validatePolarProduct(p,'xl').amount_minor,44900);assert.equal(validatePolarProduct({...p,prices:[{...p.prices[0],tax_behavior:null}]},'xl').amount_minor,44900);assert.throws(()=>validatePolarProduct({...p,is_recurring:true},'xl'));for(const override of [{tax_behavior:'exclusive'},{price_amount:100},{price_currency:'usd'},{amount_type:'custom'}])assert.throws(()=>validatePolarProduct({...p,prices:[{...p.prices[0],...override}]},'xl'));});
test('checkout URL requires exact sandbox origin',()=>{assert.equal(validPolarSandboxUrl('https://sandbox.polar.sh/checkout/test'),true);for(const u of ['https://polar.sh/checkout/test','https://sandbox.polar.sh.attacker.example/checkout/test','https://user@sandbox.polar.sh/checkout/test','https://sandbox.polar.sh/checkout/test#x','http://sandbox.polar.sh/checkout/test'])assert.equal(validPolarSandboxUrl(u),false);});
test('restoration verifies account, amount, paid state and refunds',async()=>{const external=await polarSandboxOwner(env,'buyer');assert.notEqual(external,await polarSandboxOwner(env,'other'));const order={product_id:POLAR_SANDBOX_PRODUCTS.xxl,customer:{external_id:external},paid:true,status:'paid',currency:'inr',total_amount:64900,refunded_amount:0,subscription_id:null};assert.equal(polarOrderTier(order,external),'xxl');for(const override of [{customer:{external_id:'other'}},{paid:false},{status:'refunded'},{total_amount:100},{refunded_amount:1},{currency:'usd'},{subscription_id:'subscription'}])assert.equal(polarOrderTier({...order,...override},external),'free');assert.equal(await restorePolarSandbox(env,'buyer',async url=>{assert.equal(new URL(url).searchParams.get('external_customer_id'),external);return json({items:[order]});}),'xxl');assert.equal(await restorePolarSandbox(env,'other',async()=>json({items:[order]})),'free');});

test('checkout binds server owner and product; rejects tampered price and other owners',async()=>{
  const external=await polarSandboxOwner(env,'buyer');
  let created=0;
  const api=async(url,options)=>{
    if(options.method==='GET'){const tier=url.endsWith(POLAR_SANDBOX_PRODUCTS.xl)?'xl':'xxl';return json({id:POLAR_SANDBOX_PRODUCTS[tier],is_archived:false,is_recurring:false,organization_id:'same',prices:[{is_archived:false,amount_type:'fixed',price_currency:'inr',price_amount:tier==='xl'?44900:64900,tax_behavior:'inclusive'}]});}
    const body=JSON.parse(options.body);assert.equal(body.external_customer_id,external);assert.deepEqual(body.products,[POLAR_SANDBOX_PRODUCTS.xl]);assert.equal(body.allow_discount_codes,false);assert.equal(body.customer_ip_address,'203.0.113.1');assert.equal(body.phone,undefined);created++;
    return json({id:'12345678-1234-4123-8123-123456789abc',url:'https://sandbox.polar.sh/checkout/test',currency:'inr',total_amount:44900,tax_behavior:'inclusive',external_customer_id:external,expires_at:new Date(Date.now()+3600000).toISOString()});
  };
  const configured={...env,CHECKOUT_ORIGIN:'https://linqo.test',PURCHASES:{prepare(){return {bind(){return this;},async first(){return {count:1};}};}}};
  const value={tier:'xl',request_id:'12345678-1234-4123-8123-123456789abc'};
  const result=await startPolarSandbox(configured,'buyer',value,'203.0.113.1',api);assert.equal(result.provider,'polar');assert.equal(result.sandbox,true);assert.equal(created,1);
  for(const change of [{tax_behavior:'exclusive'},{total_amount:100},{currency:'usd'},{external_customer_id:'other'}])await assert.rejects(startPolarSandbox(configured,'buyer',value,'203.0.113.1',async(...args)=>{const response=await api(...args);const body=await response.json();return json(args[1].method==='POST'?{...body,...change}:body);}),e=>e.message==='polar_checkout_mismatch');
  await assert.rejects(startPolarSandbox(configured,'other',value,null,api));
  await assert.rejects(startPolarSandbox(configured,'buyer',{...value,amount:100},null,api));
});

test('live preflight uses only live token and GET on the live API',async()=>{
  let calls=0;
  const configured={...env,POLAR_LIVE_PREFLIGHT:'true',POLAR_ACCESS_TOKEN:'live-token-fixture-only'};
  const products=await polarLiveCatalog(configured,async(url,options)=>{calls++;assert.equal(new URL(url).host,'api.polar.sh');assert.equal(options.method,'GET');assert.equal(options.headers['Polar-Version'],'2026-10');assert.equal(options.headers.authorization,'Bearer '+configured.POLAR_ACCESS_TOKEN);const tier=url.endsWith(POLAR_LIVE_PRODUCTS.xl)?'xl':'xxl';return json({id:POLAR_LIVE_PRODUCTS[tier],is_archived:false,is_recurring:false,organization_id:'live-organization',prices:[{is_archived:false,amount_type:'fixed',price_currency:'inr',price_amount:tier==='xl'?44900:64900,tax_behavior:null}]});});
  assert.equal(calls,2);assert.equal(products[0].product_id,POLAR_LIVE_PRODUCTS.xl);
  await assert.rejects(polarLiveCatalog({...configured,POLAR_ACCESS_TOKEN:''}));
  assert.throws(()=>validatePolarProduct({id:POLAR_SANDBOX_PRODUCTS.xl},'xl',POLAR_LIVE_PRODUCTS));
});
test('Standard Webhooks verifier rejects forged, expired and cross-environment signatures; inbox deduplicates',async()=>{
  const sql=new DatabaseSync(':memory:');sql.exec(readFileSync(new URL('../migrations/purchases/0007_polar_webhooks.sql',import.meta.url),'utf8'));
  const db={prepare(text){let args=[];return {bind(...v){args=v;return this;},async run(){return sql.prepare(text).run(...args);},async first(){return sql.prepare(text).get(...args);}};}};
  const secret='whsec_'+Buffer.from('sandbox-webhook-fixture-secret-32').toString('base64');
  const configured={...env,PURCHASES:db,POLAR_TEST_WEBHOOK_SECRET:secret,POLAR_WEBHOOK_SECRET:'whsec_'+Buffer.from('different-live-fixture-secret-32').toString('base64')};
  const payload={api_version:'2026-10',type:'order.paid',data:{id:'12345678-1234-4123-8123-123456789abc',product_id:POLAR_SANDBOX_PRODUCTS.xl}};
  const raw=JSON.stringify(payload),timestamp=String(Math.floor(Date.now()/1000)),id='fixture-event';
  const headers=(body=raw,t=timestamp)=>new Headers({'webhook-id':id,'webhook-timestamp':t,'webhook-signature':'v1,'+createHmac('sha256',Buffer.from(secret.slice(6),'base64')).update(id+'.'+t+'.'+body).digest('base64')});
  try{
    await assert.rejects(receivePolarWebhook(configured,'sandbox',raw,new Headers()),e=>e.status===401);
    await assert.rejects(receivePolarWebhook(configured,'sandbox',raw,headers(raw,'1')),e=>e.status===401);
    await assert.rejects(receivePolarWebhook(configured,'production',raw,headers()),e=>e.status===401);
    await assert.rejects(receivePolarWebhook(configured,'sandbox','null',headers('null')),e=>e.status===400);
    const unsupported=JSON.stringify({...payload,api_version:'2027-01'});await assert.rejects(receivePolarWebhook(configured,'sandbox',unsupported,headers(unsupported)),e=>e.status===409&&e.message==='unsupported_polar_api_version');
    assert.deepEqual(await receivePolarWebhook(configured,'sandbox',raw,headers()),{ok:true,received:true});
    await receivePolarWebhook(configured,'sandbox',raw,headers());assert.equal(sql.prepare('SELECT count(*) n FROM polar_webhook_inbox').get().n,1);
    const changed=JSON.stringify({...payload,type:'order.refunded'});await assert.rejects(receivePolarWebhook(configured,'sandbox',changed,headers(changed)),e=>e.status===409);
    const unrelated=JSON.stringify({...payload,data:{...payload.data,product_id:POLAR_LIVE_PRODUCTS.xl}});assert.equal((await receivePolarWebhook(configured,'sandbox',unrelated,headers(unrelated))).ignored,'unrelated_product');
    assert.equal(sql.prepare('PRAGMA table_info(polar_webhook_inbox)').all().some(x=>/email|payload|token/.test(x.name)),false);
  }finally{sql.close();}
});

test('provider response with another API version fails closed',async()=>{
  await assert.rejects(polarSandboxApi(env,'/v1/products/test',{},async()=>new Response('{}',{headers:{'Polar-Version':'2027-01'}})),e=>e.message==='polar_api_version_mismatch');
});
