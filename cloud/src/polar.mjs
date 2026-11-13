import {Webhook} from 'standardwebhooks';
import {digest} from './crypto.mjs';
import {fail,hmac} from './crypto.mjs';

export const POLAR_API_VERSION='2026-10';
export const POLAR_SANDBOX_PRODUCTS=Object.freeze({xl:'eb52f467-3a44-41be-9d7c-4319eb465961',xxl:'2acc1de5-8940-461d-909a-056ad54ef1d6'});
export const POLAR_LIVE_PRODUCTS=Object.freeze({xl:'eea99c56-1cbe-4b24-922a-cc300ea8aa09',xxl:'960ec47e-2df7-469e-9d57-cb2e077fccd8'});
const amounts={xl:44900,xxl:64900};
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
export function polarSandboxReady(env){return env.POLAR_SANDBOX_ENABLED==='true'&&typeof env.POLAR_ACCEPTANCE_OWNER==='string'&&env.POLAR_ACCEPTANCE_OWNER.length>0&&typeof env.POLAR_TEST_ACCESS_TOKEN==='string'&&env.POLAR_TEST_ACCESS_TOKEN.length>16;}
export async function polarSandboxApi(env,path,options={},fetcher=fetch){
  if(!polarSandboxReady(env))fail('polar_sandbox_not_configured',503);
  return polarApi(env,'sandbox',path,options,fetcher);
}
export async function polarApi(env,mode,path,{method='GET',body}={},fetcher=fetch){
  if(!['sandbox','production'].includes(mode))fail('invalid_environment');
  const token=mode==='sandbox'?env.POLAR_TEST_ACCESS_TOKEN:env.POLAR_ACCESS_TOKEN;
  if(typeof token!=='string'||token.length<17)fail('polar_not_configured',503);
  if(!path.startsWith('/v1/'))fail('invalid_provider_path');
  let response;
  try{response=await fetcher((mode==='sandbox'?'https://sandbox-api.polar.sh':'https://api.polar.sh')+path,{method,redirect:'manual',signal:AbortSignal.timeout(15000),headers:{authorization:'Bearer '+token,'content-type':'application/json','Polar-Version':POLAR_API_VERSION},...(body?{body:JSON.stringify(body)}:{})});}
  catch{fail('polar_unavailable',503);}
  if(!response.ok) {console.warn('polar_provider_failure',mode,response.status);fail(response.status===401||response.status===403?'polar_token_permissions':'polar_unavailable',503);}
  const responseVersion=response.headers.get('Polar-Version');
  if(responseVersion&&responseVersion!==POLAR_API_VERSION)fail('polar_api_version_mismatch',503);
  const reader=response.body?.getReader();if(!reader)fail('polar_invalid_response',503);
  const chunks=[];let length=0;
  while(true){const {done,value}=await reader.read();if(done)break;length+=value.length;if(length>524288){await reader.cancel();fail('polar_response_too_large',503);}chunks.push(value);}
  const bytes=new Uint8Array(length);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  try{return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));}catch{fail('polar_invalid_response',503);}
}
export function validatePolarProduct(product,tier,products=POLAR_SANDBOX_PRODUCTS){
  if(product?.id!==products[tier]||product.is_archived!==false||product.is_recurring!==false||!Array.isArray(product.prices))fail('polar_product_mismatch',503);
  const price=product.prices.find(p=>p.is_archived===false&&p.amount_type==='fixed'&&p.price_currency==='inr'&&p.price_amount===amounts[tier]&&(p.tax_behavior==='inclusive'||p.tax_behavior===null));
  if(!price)fail('polar_inr_price_or_tax_mismatch',503);
  return {tier,product_id:product.id,amount_minor:amounts[tier],currency:'INR',organization_id:product.organization_id};
}
export async function polarSandboxCatalog(env,fetcher=fetch){
  const rows=[];for(const tier of ['xl','xxl'])rows.push(validatePolarProduct(await polarSandboxApi(env,'/v1/products/'+POLAR_SANDBOX_PRODUCTS[tier],{},fetcher),tier));
  if(!rows[0].organization_id||rows[0].organization_id!==rows[1].organization_id)fail('polar_organization_mismatch',503);
  return rows;
}
export async function polarSandboxOwner(env,owner){
  if((env.ACCOUNT_HMAC_SECRET?.length??0)<32)fail('identity_not_configured',503);
  return 'linqo_sandbox_'+await hmac(env.ACCOUNT_HMAC_SECRET,'polar:'+owner);
}
export function validPolarSandboxUrl(value){
  try{const url=new URL(value);return url.protocol==='https:'&&url.hostname==='sandbox.polar.sh'&&!url.port&&!url.username&&!url.password&&!url.hash&&url.pathname.startsWith('/checkout/');}catch{return false;}
}
export async function startPolarSandbox(env,owner,value,ip,fetcher=fetch){
  if(!value||!Object.hasOwn(amounts,value.tier)||!uuid.test(value.request_id??'')||Object.keys(value).some(k=>!['tier','request_id','phone'].includes(k)))fail('invalid_product');
  if(env.POLAR_ACCEPTANCE_OWNER&&env.POLAR_ACCEPTANCE_OWNER!==owner)fail('checkout_not_live',503);
  const day=new Date().toISOString().slice(0,10);
  const allowed=await env.PURCHASES.prepare('INSERT INTO request_limits(owner,day,count) VALUES(?,?,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1 WHERE count<10 RETURNING count').bind('polar:'+owner,day).first();
  if(!allowed)fail('try_tomorrow',429);
  await polarSandboxCatalog(env,fetcher);
  const checkout=await polarSandboxApi(env,'/v1/checkouts/',{method:'POST',body:{products:[POLAR_SANDBOX_PRODUCTS[value.tier]],external_customer_id:await polarSandboxOwner(env,owner),allow_discount_codes:false,allow_trial:false,...(ip?{customer_ip_address:ip}:{}),success_url:env.CHECKOUT_ORIGIN+'/checkout/return'}},fetcher);
  if(!uuid.test(checkout.id??'')||!validPolarSandboxUrl(checkout.url)||checkout.currency!=='inr'||checkout.total_amount!==amounts[value.tier]||checkout.tax_behavior!=='inclusive'||checkout.external_customer_id!==await polarSandboxOwner(env,owner))fail('polar_checkout_mismatch',503);
  const expires=Math.min(Date.parse(checkout.expires_at),Date.now()+3600000);
  if(!Number.isFinite(expires)||expires<=Date.now())fail('polar_checkout_expired',503);
  return {provider:'polar',sandbox:true,tier:value.tier,amount_minor:amounts[value.tier],currency:'INR',order_id:'lq_s_'+checkout.id,checkout_url:checkout.url,expires_at:expires};
}
export function polarOrderTier(order,external){
  const tier=Object.keys(POLAR_SANDBOX_PRODUCTS).find(k=>POLAR_SANDBOX_PRODUCTS[k]===order.product_id);
  if(!tier||order.customer?.external_id!==external||order.subscription_id||order.paid!==true||order.status!=='paid'||order.currency!=='inr'||order.total_amount!==amounts[tier]||order.refunded_amount!==0)return 'free';
  return tier;
}
export async function restorePolarSandbox(env,owner,fetcher=fetch){
  const external=await polarSandboxOwner(env,owner);let tier='free';
  // shortcut: at most 200 sandbox orders per account; add pagination before live qualification.
  for(let page=1;page<=2;page++){
    const result=await polarSandboxApi(env,'/v1/orders/?external_customer_id='+encodeURIComponent(external)+'&limit=100&page='+page,{},fetcher);
    if(!Array.isArray(result.items)||result.items.length>100)fail('polar_invalid_response',503);
    for(const order of result.items){const found=polarOrderTier(order,external);if(found==='xxl')tier='xxl';else if(found==='xl'&&tier==='free')tier='xl';}
    if(result.items.length<100)return tier;
  }
  fail('polar_sandbox_order_limit',503);
}

export async function polarLiveCatalog(env,fetcher=fetch){
  const rows=[];
  for(const tier of ['xl','xxl'])rows.push(validatePolarProduct(await polarApi(env,'production','/v1/products/'+POLAR_LIVE_PRODUCTS[tier],{},fetcher),tier,POLAR_LIVE_PRODUCTS));
  if(!rows[0].organization_id||rows[0].organization_id!==rows[1].organization_id)fail('polar_organization_mismatch',503);
  return rows;
}
export async function receivePolarWebhook(env,mode,raw,headers,now=Date.now()){
  if(!['sandbox','production'].includes(mode))fail('invalid_environment');
  const secret=mode==='sandbox'?env.POLAR_TEST_WEBHOOK_SECRET:env.POLAR_WEBHOOK_SECRET;
  if(typeof secret!=='string'||secret.length<16)fail('polar_webhook_not_configured',503);
  let event;
  try{event=new Webhook(secret).verify(raw,Object.fromEntries(headers));}catch{fail('invalid_signature',401);}
  if(!event||typeof event!=='object'||Array.isArray(event)||typeof event.type!=='string')fail('invalid_polar_event');
  if(event.api_version!==POLAR_API_VERSION)fail('unsupported_polar_api_version',409);
  if(!['order.paid','order.updated','order.refunded'].includes(event.type))return {ok:true,ignored:'event_type'};
  const products=mode==='sandbox'?POLAR_SANDBOX_PRODUCTS:POLAR_LIVE_PRODUCTS;
  if(!Object.values(products).includes(event.data?.product_id))return {ok:true,ignored:'unrelated_product'};
  const id=headers.get('webhook-id'),resource=event.data?.id;
  if(typeof id!=='string'||id.length>200||!uuid.test(resource??''))fail('invalid_polar_event');
  const hash=await digest(raw),db=env.PURCHASES;
  await db.prepare('INSERT OR IGNORE INTO polar_webhook_inbox(environment,id,type,resource_id,hash,received) VALUES(?,?,?,?,?,?)').bind(mode,id,event.type,resource,hash,now).run();
  const row=await db.prepare('SELECT hash FROM polar_webhook_inbox WHERE environment=? AND id=?').bind(mode,id).first();
  if(row?.hash!==hash)fail('polar_event_conflict',409);
  // Persist before acknowledgement; the Worker reconciles production orders separately.
  return {ok:true,received:true};
}
