// The production App and Finance with fabricated auth/events only; no real credentials or APIs.
import React from 'react';import {createRoot} from 'react-dom/client';import {App} from '../../src/App.jsx';import {mockCall} from './fixture.jsx';
function session(user='mock-owner',sid='mock-passkey-session',version=1){return {user:{id:user},access_token:'mock.'+btoa(JSON.stringify({sub:user,session_id:sid,version})) +'.signature'};}
let subscriber,current=session();const state={status:'approved',passkey_verified:true,role:'owner',calls:[],emit(event,next=current){current=next;subscriber?.(event,next);},session};window.__authFixture=state;
const authClient={auth:{onAuthStateChange(callback){subscriber=callback;queueMicrotask(()=>callback('INITIAL_SESSION',current));return {data:{subscription:{unsubscribe(){subscriber=null;}}}};},async signOut(){state.emit('SIGNED_OUT',null);return {};} }};
// Match the SDK's existing-session SIGNED_IN notification when a tab becomes visible.
document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&current)state.emit('SIGNED_IN');});
async function invoke(operation,payload){state.calls.push(operation);if(['access_state','request_access'].includes(operation))return {status:state.status,passkey_verified:state.passkey_verified,role:state.role};if(operation==='list_requests')return [];return mockCall(operation,payload);}
createRoot(document.getElementById('root')).render(<App authClient={authClient} invoke={invoke} ready storeReceipt={async()=>{throw Error('No real documents in auth fixture');}}/>);
