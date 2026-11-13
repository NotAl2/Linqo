import {fail,hmac} from './crypto.mjs';
import {polarApi,polarLiveCatalog,POLAR_LIVE_PRODUCTS} from './polar.mjs';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
const prices={xl:44900,xxl:64900};
export async function livePolarOwner(env,owner){
  if((env.ACCOUNT_HMAC_SECRET?.length??0)<32)fail('identity_not_configured',503);
  return 'linqo_live_'+await hmac(env.ACCOUNT_HMAC_SECRET,'polar:'+owner);
}
export function liveAcceptanceReady(env,owner){
  return env.POLAR_FREE_ACCEPTANCE_ENABLED==='true'&&!!owner&&env.POLAR_ACCEPTANCE_OWNER===owner&&uuid.test(env.POLAR_ACCEPTANCE_DISCOUNT_ID??'')&&typeof env.POLAR_ACCESS_TOKEN==='string'&&env.POLAR_ACCESS_TOKEN.length>16;
}
export function validLivePolarUrl(value){
  try{const u=new URL(value);return u.protocol==='https:'&&u.hostname==='polar.sh'&&!u.port&&!u.username&&!u.password&&!u.hash&&u.pathname.startsWith('/checkout/');}catch{return false;}
}
export async function startLiveAcceptance(env,owner,value,ip,fetcher=fetch,now=Date.now()){
  if(!liveAcceptanceReady(env,owner))fail('polar_live_acceptance_disabled',503);
  return startPolarLive(env,owner,value,ip,fetcher,now,true);
}
export async function startPaidPolarCheckout(env,owner,value,ip,fetcher=fetch,now=Date.now()){
  if(!polarCheckoutReady(env))fail('checkout_not_live',503);
  return startPolarLive(env,owner,value,ip,fetcher,now,false);
}
export function polarCheckoutReady(env){
  return env.PAYMENTS_ENABLED==='true'&&env.POLAR_LIVE_APPROVED==='true'&&env.PAYMENTS_PROVIDER==='polar'&&typeof env.POLAR_ACCESS_TOKEN==='string'&&env.POLAR_ACCESS_TOKEN.length>16&&typeof env.POLAR_WEBHOOK_SECRET==='string'&&env.POLAR_WEBHOOK_SECRET.length>=16&&/^https:\/\/[^/?#@]+$/.test(env.CHECKOUT_ORIGIN??'');
}
async function startPolarLive(env,owner,value,ip,fetcher,now,acceptance){
  if(!value||!Object.hasOwn(prices,value.tier)||!uuid.test(value.request_id??'')||Object.keys(value).some(k=>!['tier','request_id'].includes(k)))fail('invalid_product');
  const db=env.PURCHASES;
  const previous=await db.prepare('SELECT * FROM polar_live_checkouts WHERE uid=? AND request_id=?').bind(owner,value.request_id).first();
  if(previous){
    if(previous.tier!==value.tier||previous.expires<=now||previous.minor!==(acceptance?0:prices[value.tier])||previous.discount_id!==(acceptance?env.POLAR_ACCEPTANCE_DISCOUNT_ID:null))fail('purchase_request_expired',409);
    const checkout=await polarApi(env,'production','/v1/checkouts/'+previous.id,{},fetcher);
    return acceptanceResponse(checkout,previous,now);
  }
  const allowed=await db.prepare('INSERT INTO request_limits(owner,day,count) VALUES(?,?,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1 WHERE count<5 RETURNING count').bind('polar-live:'+owner,new Date(now).toISOString().slice(0,10)).first();
  if(!allowed)fail('try_tomorrow',429);
  // A timed-out provider POST must not be replayed with the same request ID.
  const reserved=await db.prepare('INSERT OR IGNORE INTO polar_checkout_requests(uid,request_id,created) VALUES(?,?,?)').bind(owner,value.request_id,now).run();
  if(!reserved.meta.changes)fail('purchase_request_expired',409);
  const catalog=await polarLiveCatalog(env,fetcher),external=await livePolarOwner(env,owner);
  const checkout=await polarApi(env,'production','/v1/checkouts/',{method:'POST',body:{products:[POLAR_LIVE_PRODUCTS[value.tier]],external_customer_id:external,...(acceptance?{discount_id:env.POLAR_ACCEPTANCE_DISCOUNT_ID}:{}),allow_discount_codes:false,allow_trial:false,metadata:{linqo_request:value.request_id},...(ip?{customer_ip_address:ip}:{}),success_url:env.CHECKOUT_ORIGIN+'/checkout/return'}},fetcher);
  const row={id:checkout.id,uid:owner,request_id:value.request_id,tier:value.tier,product_id:POLAR_LIVE_PRODUCTS[value.tier],organization_id:catalog[0].organization_id,external_id:external,minor:acceptance?0:prices[value.tier],currency:'inr',discount_id:acceptance?env.POLAR_ACCEPTANCE_DISCOUNT_ID:null,created:now,expires:Math.min(Date.parse(checkout.expires_at),now+3600000)};
  const response=acceptanceResponse(checkout,row,now);
  await db.prepare('INSERT INTO polar_live_checkouts(id,uid,request_id,tier,product_id,organization_id,external_id,minor,currency,discount_id,created,expires) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').bind(...['id','uid','request_id','tier','product_id','organization_id','external_id','minor','currency','discount_id','created','expires'].map(k=>row[k])).run();
  return response;
}
function acceptanceResponse(checkout,row,now){
  if(!uuid.test(checkout.id??'')||checkout.id!==row.id||!validLivePolarUrl(checkout.url)||checkout.external_customer_id!==row.external_id||checkout.organization_id!==row.organization_id||checkout.product_id!==row.product_id||checkout.currency!==row.currency||checkout.total_amount!==row.minor||(checkout.discount_id??null)!==row.discount_id||checkout.discount_amount!==(row.minor===0?prices[row.tier]:0)||(row.minor>0&&checkout.tax_behavior!=='inclusive')||!Number.isFinite(row.expires)||row.expires<=now)fail('polar_free_checkout_mismatch',503);
  return {provider:'polar',sandbox:false,acceptance:row.minor===0,tier:row.tier,amount_minor:row.minor,currency:'INR',order_id:'lq_p_'+row.id,expires_at:row.expires,checkout_url:checkout.url};
}
export async function recordLivePolarOrder(env,order){
  if(!uuid.test(order?.id??'')||!uuid.test(order.checkout_id??''))fail('invalid_polar_order');
  const db=env.PURCHASES,row=await db.prepare('SELECT * FROM polar_live_checkouts WHERE id=?').bind(order.checkout_id).first();
  if(!row)return false;
  if(order.product_id!==row.product_id||order.customer?.organization_id!==row.organization_id||order.product?.organization_id!==row.organization_id||order.product?.id!==row.product_id||order.customer?.external_id!==row.external_id||order.currency!==row.currency||order.total_amount!==row.minor||order.subscription_id||((order.discount_id??null)!==row.discount_id))fail('polar_order_mismatch');
  const modified=Date.parse(order.modified_at??order.created_at);
  if(!Number.isFinite(modified)||!Number.isSafeInteger(order.refunded_amount)||order.refunded_amount<0)fail('invalid_polar_order');
  const revoked=(row.minor>0&&order.refunded_amount>=row.minor)||['refunded','void'].includes(order.status)?1:0;
  const active=order.paid===true&&['paid','partially_refunded'].includes(order.status)&&!revoked?1:0;
  const old=await db.prepare('SELECT checkout_id FROM polar_live_orders WHERE id=?').bind(order.id).first();
  if(old&&old.checkout_id!==row.id)fail('polar_order_conflict',409);
  await db.prepare(`INSERT INTO polar_live_orders(id,checkout_id,active,revoked,modified) VALUES(?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET active=CASE WHEN excluded.modified>=polar_live_orders.modified THEN excluded.active ELSE polar_live_orders.active END,
    revoked=MAX(polar_live_orders.revoked,excluded.revoked),modified=MAX(polar_live_orders.modified,excluded.modified) WHERE polar_live_orders.checkout_id=excluded.checkout_id`).bind(order.id,row.id,active,revoked,modified).run();
  return true;
}
export async function effectivePolarTier(db,owner){
  const rows=await db.prepare(`SELECT c.tier FROM polar_live_orders o JOIN polar_live_checkouts c ON c.id=o.checkout_id WHERE c.uid=? AND o.active=1 AND o.revoked=0`).bind(owner).all();
  return rows.results.some(r=>r.tier==='xxl')?'xxl':rows.results.some(r=>r.tier==='xl')?'xl':'free';
}
export async function processPolarInbox(env,fetcher=fetch,now=Date.now()){
  const db=env.PURCHASES;
  const rows=await db.prepare("SELECT id,resource_id FROM polar_webhook_inbox WHERE environment='production' AND processed=0 AND attempted<? ORDER BY attempted,received LIMIT 5").bind(now-60000).all();
  await Promise.all(rows.results.map(async row=>{
    const reserved=await db.prepare("UPDATE polar_webhook_inbox SET attempted=? WHERE environment='production' AND id=? AND processed=0 AND attempted<?").bind(now,row.id,now-60000).run();
    if(!reserved.meta.changes)return;
    try{
      const order=await polarApi(env,'production','/v1/orders/'+row.resource_id,{},fetcher);
      if(order.id!==row.resource_id)fail('polar_order_mismatch');
      await recordLivePolarOrder(env,order);
      await db.prepare("UPDATE polar_webhook_inbox SET processed=? WHERE environment='production' AND id=?").bind(now,row.id).run();
    }catch{/* The verified receipt stays pending for the next retry. */}
  }));
}
export async function reconcilePolarOwner(env,owner,fetcher=fetch,now=Date.now()){
  if(!env.POLAR_ACCESS_TOKEN)return;
  const db=env.PURCHASES;
  const rows=await db.prepare('SELECT id FROM polar_live_checkouts WHERE uid=? AND checked<? ORDER BY checked,created DESC LIMIT 3').bind(owner,now-15000).all();
  await Promise.all(rows.results.map(async row=>{
    const reserved=await db.prepare('UPDATE polar_live_checkouts SET checked=? WHERE id=? AND checked<?').bind(now,row.id,now-15000).run();
    if(!reserved.meta.changes)return;
    try{
      const result=await polarApi(env,'production','/v1/orders/?checkout_id='+row.id+'&limit=100',{},fetcher);
      if(!Array.isArray(result.items)||result.items.length>100)fail('polar_invalid_response',503);
      for(const order of result.items){if(order.checkout_id!==row.id)fail('polar_order_mismatch');await recordLivePolarOrder(env,order);}
    }catch{/* Keep known grants during provider outages; never invent a new grant. */}
  }));
}
