import React,{useState,useEffect,useRef} from 'react';
import {createRoot} from 'react-dom/client';
import {client,configured,call} from './client.js';
import {SessionFence} from './lifecycle.js';
import {Finance} from './Finance.jsx';
import './style.css';
function App(){
 const [phase,setPhase]=useState('signed_out'),[role,setRole]=useState(null),[error,setError]=useState(''),[notice,setNotice]=useState(''),[busy,setBusy]=useState(false),[people,setPeople]=useState([]),[keys,setKeys]=useState([]),[generation,setGeneration]=useState(0);
 const fence=useRef(new SessionFence()),alive=useRef(true),currentUser=useRef(null);
 const passkeys=Boolean(globalThis.isSecureContext&&globalThis.PublicKeyCredential);
 function clear(next='signed_out'){fence.current.invalidate();setGeneration(g=>g+1);setPhase(next);setRole(null);setPeople([]);setKeys([]);setNotice('');}
 async function secureCall(operation,payload){
  try{return await fence.current.run(()=>call(operation,payload));}
  catch(e){if(e.code==='42501'||e.status===401||e.status===403){clear('access_required');setError('Your access could not be confirmed. Sign in again or ask the owner.');}throw e;}
 }
 async function access(request=false){
  const state=await fence.current.run(()=>call(request?'request_access':'access_state'));
  if(!alive.current)return;
  if(state.status!=='approved'){clear(state.status);return;}
  setPhase('approved');setRole(state.role);
  if(state.role==='owner')setPeople(await secureCall('list_requests'));
 }
 async function run(task){setBusy(true);setError('');try{await task();}catch(e){if(e.message!=='Stale session'&&alive.current)setError(e.message);}finally{if(alive.current)setBusy(false);}}
 useEffect(()=>{
  alive.current=true;
  if(!client)return;
  const {data:{subscription}}=client.auth.onAuthStateChange((event,session)=>{
   if(event==='TOKEN_REFRESHED'&&currentUser.current===session?.user.id)return;
   currentUser.current=session?.user.id||null;clear(session?'checking':'signed_out');setError('');
   if(session){const expected=fence.current.epoch;setTimeout(()=>{if(alive.current&&expected===fence.current.epoch)run(()=>access(true)).catch(()=>{});},0);}
  });
  const recheck=()=>{if(!currentUser.current)return;access().catch(e=>{if(e.message!=='Stale session'){clear('access_required');setError('Access check failed. Please sign in again.');}});};
  const timer=setInterval(recheck,30000);document.addEventListener('visibilitychange',recheck);
  return()=>{alive.current=false;fence.current.invalidate();subscription.unsubscribe();clearInterval(timer);document.removeEventListener('visibilitychange',recheck);};
 },[]);
 async function signOut(){currentUser.current=null;clear();await client.auth.signOut({scope:'local'});}
 async function listKeys(){const {data,error}=await fence.current.run(()=>client.auth.passkey.list());if(error)throw error;setKeys(data||[]);}
 async function emailLink(event){event.preventDefault();const email=new FormData(event.currentTarget).get('email');await run(async()=>{const {error}=await client.auth.signInWithOtp({email,options:{shouldCreateUser:true,emailRedirectTo:location.origin+import.meta.env.BASE_URL}});if(error)throw error;setNotice('Check your email for a sign-in link. After verification, your access request will be submitted.');});}
 return <div className="shell"><header><div className="brand">H<span>Household</span></div><span className="tag">Private household · Mock records only</span>{currentUser.current&&<button disabled={busy} onClick={()=>run(signOut)}>Sign out</button>}</header><main><p className="eyebrow">YOUR HOUSEHOLD, CONNECTED</p><h1>A clearer view of home.</h1><p className="intro">Finance, property and the things that keep home running.</p>
 {error&&<p className="error" role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
 {!configured?<section className="panel"><h2>Project setup needed</h2><p>Add the project URL and publishable key using the setup guide, then rebuild.</p></section>:
 phase==='signed_out'?<section className="panel login"><h2>Sign in to your household</h2><button disabled={busy||!passkeys} onClick={()=>run(async()=>{const {error}=await client.auth.signInWithPasskey();if(error)throw error;})}>Sign in with a passkey</button>{!passkeys&&<p>Passkeys need a supported browser and a secure connection.</p>}<form onSubmit={emailLink}><label>Email<input name="email" type="email" required autoComplete="email"/></label><button disabled={busy}>Send sign-in link</button></form><p>New accounts require email verification and owner approval. A sign-in link also provides recovery if your passkey is unavailable.</p></section>:
 phase==='checking'?<p role="status">Checking your household access…</p>:
 phase!=='approved'?<section className="panel"><h2>{phase==='pending'?'Waiting for owner approval':phase==='rejected'?'Request declined':phase==='removed'?'Household access removed':'Access needs confirmation'}</h2><p>Household records are available only after approval.</p><button disabled={busy} onClick={()=>run(()=>access(phase==='unrequested'))}>Check access</button><button disabled={busy} onClick={()=>run(signOut)}>Return to sign-in</button></section>:<>
 <section className="panel"><h2>Account security</h2><p>Add a passkey on your device or password manager. Keep email access available for recovery.</p><button disabled={busy||!passkeys} onClick={()=>run(async()=>{const state=await secureCall('access_state');if(state.status!=='approved'){clear(state.status);throw Error('Approval is required before enrollment');}const {error}=await fence.current.run(()=>client.auth.registerPasskey());if(error)throw error;setNotice('Passkey added.');await listKeys();})}>Add a passkey</button> <button disabled={busy} onClick={()=>run(listKeys)}>Manage passkeys</button>{keys.map(k=><p key={k.id}>{k.friendly_name||'Passkey'} <button disabled={busy} onClick={()=>run(async()=>{const {error}=await fence.current.run(()=>client.auth.passkey.delete({passkeyId:k.id}));if(error)throw error;await listKeys();setNotice('Passkey removed. Email-link recovery remains available.');})}>Remove</button></p>)}</section>
 {role==='owner'&&<section className="panel"><h2>Household access requests</h2><p>Approve only people who should share access to this household’s records. Approved members can read and manage finance records.</p>{people.map(p=><article key={p.user_id}><strong>{p.email}</strong><small>{p.role} · {p.status}</small>{p.role!=='owner'&&['approved','rejected','removed'].filter(status=>status!==p.status).map(status=><button key={status} disabled={busy} onClick={()=>run(async()=>{await secureCall('decide_access',{user_id:p.user_id,status,revision:p.revision});setPeople(await secureCall('list_requests'));setNotice('Access decision saved.');})}>{status==='approved'?'Approve':status==='rejected'?'Reject':'Remove access'}</button>)}</article>)}</section>}
 <Finance key={generation} secureCall={secureCall}/>
 </>}
 </main><footer>Household Platform · Canada Central · Foundation v0.2</footer></div>;
}
createRoot(document.getElementById('root')).render(<App/>);
