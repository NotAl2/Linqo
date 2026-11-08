import {digest, fail} from './crypto.mjs';

export const PRODUCTS = Object.freeze({xl:500, xxl:700});
const codePattern=/^LQ-[A-F0-9]{32}$/;
function positiveId(value) {
  if(typeof value==='number' && Number.isSafeInteger(value) && value>0) return String(value);
  if(typeof value==='string' && /^[1-9][0-9]{0,14}$/.test(value)) return value;
  return null;
}
function cents(value) {
  if(typeof value!=='number' || !Number.isFinite(value) || value<0) return null;
  const rounded=Math.round(value*100);
  return Number.isSafeInteger(rounded) && Math.abs(value*100-rounded)<0.000001 ? rounded : null;
}
function productId(env,tier) {
  return positiveId(tier==='xl'?env.BMC_XL_PRODUCT_ID:env.BMC_XXL_PRODUCT_ID);
}
export function shopReady(env) {
  return env.PAYMENTS_ENABLED==='true' && (env.BMC_WEBHOOK_SECRET?.length??0)>=32 &&
    productId(env,'xl')!==null && productId(env,'xxl')!==null && productId(env,'xl')!==productId(env,'xxl');
}
export async function startShopPurchase(env,owner,tier,now=Date.now()) {
  if(!Object.hasOwn(PRODUCTS,tier)) fail('invalid_product');
  if(!shopReady(env)) fail('checkout_not_live',503);
  const day=new Date(now).toISOString().slice(0,10);
  const limit=await env.PURCHASES.prepare('INSERT INTO request_limits(owner,day,count) VALUES(?,?,1) ON CONFLICT(owner,day) DO UPDATE SET count=count+1 WHERE count<10 RETURNING count').bind(owner,day).first();
  if(!limit) fail('try_tomorrow',429);
  const random=Array.from(crypto.getRandomValues(new Uint8Array(16)),n=>n.toString(16).padStart(2,'0')).join('').toUpperCase();
  const code='LQ-'+random, id=productId(env,tier), expires=now+30*86400000;
  await env.PURCHASES.prepare('INSERT INTO shop_sessions(claim_hash,uid,tier,product_id,cents,issued,expires) VALUES(?,?,?,?,?,?,?)').bind(await digest(code),owner,tier,id,PRODUCTS[tier],now,expires).run();
  return {tier,amount_cents:PRODUCTS[tier],currency:'USD',claim_code:code,expires_at:expires,
    shop_url:`https://buymeacoffee.com/notal2/e/${id}`};
}
export async function effectiveShopTier(db,owner) {
  const rows=await db.prepare('SELECT tier FROM bmc_purchases WHERE uid=? AND captured=1 AND refunded=0').bind(owner).all();
  return rows.results.some(x=>x.tier==='xxl')?'xxl':rows.results.some(x=>x.tier==='xl')?'xl':'free';
}

// Only signed Shop events reach here. No donor email, caller-supplied UID or
// receipt number can bind a purchase; a pre-issued account-bound code is needed.
export async function recordShopEvent(env,event,now=Date.now()) {
  if(event?.live_mode!==true) return {ok:true,ignored:'test_event'};
  if(!['extra_purchase.created','extra_purchase.updated','extra_purchase.refunded'].includes(event.type)) {
    return {ok:true,ignored:'not_shop_purchase'};
  }
  const data=event.data, id=positiveId(data?.id);
  if(!id || !Number.isSafeInteger(event.event_id) || !Number.isSafeInteger(event.created) || event.created<=0 || event.created*1000>now+300000) fail('invalid_shop_event');
  const db=env.PURCHASES;
  const refund=event.type==='extra_purchase.refunded'||data.refunded==='true'||data.status==='refunded';
  if(refund) {
    // Tombstones survive refund-before-purchase and delayed/retried captures.
    await db.batch([
      db.prepare('INSERT OR IGNORE INTO bmc_refunds(id,created) VALUES(?,?)').bind(id,now),
      db.prepare('UPDATE bmc_purchases SET refunded=1 WHERE id=?').bind(id),
    ]);
    return {ok:true,refunded:true};
  }
  if(data.status!=='succeeded'||data.refunded!=='false') return {ok:true,ignored:'not_completed'};
  if(data.object!=='payment'||data.support_type!=='Extra'||data.currency!=='USD'||!Array.isArray(data.extras)) fail('invalid_shop_event');
  // Mixed carts/multiple licences are intentionally not supported for launch.
  if(data.extras.length!==1) return {ok:true,ignored:'unsupported_cart'};
  const item=data.extras[0], itemId=positiveId(item.id);
  if(!itemId) fail('invalid_shop_event');
  const tier=itemId===productId(env,'xl')?'xl':itemId===productId(env,'xxl')?'xxl':null;
  if(!tier) return {ok:true,ignored:'other_shop_item'};
  const amount=PRODUCTS[tier];
  if(item.object!=='extra'||item.quantity!==1||item.currency!=='USD'||cents(item.amount)!==amount||cents(data.amount)===null||cents(data.amount)<amount) fail('shop_price_mismatch');
  const created=data.created_at*1000;
  if(!Number.isSafeInteger(data.created_at)||created<=0||created>now+300000) fail('invalid_shop_event');
  const existing=await db.prepare('SELECT * FROM bmc_purchases WHERE id=?').bind(id).first();
  if(existing) {
    if(existing.product_id!==itemId||existing.cents!==amount||existing.tier!==tier) fail('shop_purchase_mismatch');
    if(existing.uid!==null) return {ok:true,linked:true};
  }
  const codes=Array.isArray(item.question_answers)?item.question_answers
    .filter(x=>typeof x==='string').map(x=>x.trim().toUpperCase()).filter(x=>codePattern.test(x)):[];
  const codeHash=codes.length===1?await digest(codes[0]):null;
  // The payment timestamp, not delivery time, determines whether the code was
  // valid. Normal provider retry delays must not invalidate a paid order.
  const session=codeHash?await db.prepare('SELECT * FROM shop_sessions WHERE claim_hash=? AND tier=? AND product_id=? AND cents=? AND issued<=? AND expires>=?').bind(codeHash,tier,itemId,amount,created+300000,created).first():null;
  // Keep a minimal unmatched ledger for support; never guess ownership by email.
  await db.prepare(`INSERT INTO bmc_purchases(id,uid,tier,product_id,cents,currency,captured,refunded,created,claim_hash)
    VALUES(?,NULL,?,?,?,?,1,EXISTS(SELECT 1 FROM bmc_refunds WHERE id=?),?,NULL) ON CONFLICT(id) DO NOTHING`)
    .bind(id,tier,itemId,amount,'USD',id,created).run();
  if(session) {
    // Atomic conditional update plus UNIQUE claim_hash handles concurrent
    // duplicate orders and a later signed update supplying a missing answer.
    await db.prepare(`UPDATE bmc_purchases SET uid=?,claim_hash=? WHERE id=? AND uid IS NULL
      AND NOT EXISTS(SELECT 1 FROM bmc_purchases WHERE claim_hash=?)`)
      .bind(session.uid,codeHash,id,codeHash).run();
  }
  const stored=await db.prepare('SELECT uid FROM bmc_purchases WHERE id=?').bind(id).first();
  return {ok:true,linked:stored.uid!==null};
}
