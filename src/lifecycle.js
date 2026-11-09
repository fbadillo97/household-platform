// Every protected response belongs to one session generation. Sign-out/revocation invalidates it.
export class SessionFence{
 epoch=0;
 invalidate(){this.epoch++;}
 async run(task){const epoch=this.epoch;try{const result=await task();if(epoch!==this.epoch)throw Error('Stale session');return result;}catch(error){if(epoch!==this.epoch)throw Error('Stale session');throw error;}}
}

// A lifecycle comparison only. Server RPCs still verify approval, passkey and live session.
// Never use decoded browser claims to authorize household access.
export function authSessionIdentity(session){
 const user=session?.user?.id,token=session?.access_token;if(!user||typeof token!=='string')return null;
 try{const part=token.split('.')[1].replace(/-/g,'+').replace(/_/g,'/'),claims=JSON.parse(atob(part.padEnd(Math.ceil(part.length/4)*4,'=')));
  return claims.sub===user&&typeof claims.session_id==='string'&&claims.session_id?JSON.stringify([user,claims.session_id]):null;
 }catch{return null;}
}
