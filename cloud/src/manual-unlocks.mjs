import {effectivePolarTier} from './polar-live.mjs';
import {effectiveCashfreeTier} from './cashfree.mjs';

export async function accountCode(db,owner) {
  const code='LQ-'+crypto.randomUUID().replaceAll('-','');
  await db.prepare('INSERT OR IGNORE INTO manual_accounts(uid,code) VALUES(?,?)').bind(owner,code).run();
  return (await db.prepare('SELECT code FROM manual_accounts WHERE uid=?').bind(owner).first()).code;
}

export async function effectiveTier(db,owner) {
  const cashfree=await effectiveCashfreeTier(db,owner);
  const grants=await db.prepare('SELECT tier FROM manual_grants WHERE uid=? AND revoked_at IS NULL').bind(owner).all();
  const gifts=await db.prepare('SELECT tier FROM gift_grants WHERE uid=? AND revoked_at IS NULL').bind(owner).all();
  const tiers=[cashfree,await effectivePolarTier(db,owner),...grants.results.map(row=>row.tier),...gifts.results.map(row=>row.tier)];
  return tiers.includes('xxl')?'xxl':tiers.includes('xl')?'xl':'free';
}
