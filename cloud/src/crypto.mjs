const encoder = new TextEncoder();
export function fail(code, status=400) { throw Object.assign(new Error(code), {status}); }
export async function digest(value) {
  return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', encoder.encode(value))), n=>n.toString(16).padStart(2,'0')).join('');
}
export async function hmac(secret, body) {
  const key=await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,encoder.encode(body))),n=>n.toString(16).padStart(2,'0')).join('');
}
export async function validSignature(secret, body, supplied) {
  if (!secret || !/^[a-f0-9]{64}$/i.test(supplied??'')) return false;
  const expected=await hmac(secret,body); let difference=0;
  for(let i=0;i<64;i++) difference |= expected.charCodeAt(i)^supplied.toLowerCase().charCodeAt(i);
  return difference===0;
}
