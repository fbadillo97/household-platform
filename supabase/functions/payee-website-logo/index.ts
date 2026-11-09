import {discoverLogo} from './core.mjs';
const origins=new Set(['https://fbadillo97.github.io','http://127.0.0.1:5173','http://localhost:5173']);
Deno.serve(async(req:Request)=>{
 const origin=req.headers.get('origin'),headers={'Content-Type':'application/json','Cache-Control':'no-store','Vary':'Origin',...(origin&&origins.has(origin)?{'Access-Control-Allow-Origin':origin}:{})};
 if(origin&&!origins.has(origin))return new Response(JSON.stringify({error:'Origin unavailable'}),{status:403,headers});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:{...headers,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST'}});
 if(req.method!=='POST')return new Response(JSON.stringify({error:'Use POST'}),{status:405,headers});
 const authorization=req.headers.get('authorization');if(!authorization?.startsWith('Bearer '))return new Response(JSON.stringify({error:'Sign in with a passkey'}),{status:401,headers});
 try{
  const auth=await fetch(Deno.env.get('SUPABASE_URL')+'/rest/v1/rpc/household_payee_websites_v1',{method:'POST',headers:{authorization,apikey:Deno.env.get('SUPABASE_ANON_KEY')!,'Content-Type':'application/json'},body:JSON.stringify({operation:'payee_website_access',payload:{}}),signal:AbortSignal.timeout(5000)});
  if(!auth.ok){const err=await auth.json().catch(()=>({}));const status=err.code==='54000'?429:auth.status===401?401:auth.status===403?403:503;return new Response(JSON.stringify({error:status===429?'Please wait before fetching more logos.':'Logo lookup access could not be confirmed.'}),{status,headers});}
  const raw=await req.text();if(raw.length>1500)throw Error('Website request is too large.');const p=JSON.parse(raw);
  if(Object.keys(p).some(k=>k!=='website')||typeof p.website!=='string')throw Error('Provide a website.');
  return new Response(JSON.stringify(await discoverLogo(p.website)),{headers});
 }catch(e){return new Response(JSON.stringify({error:e instanceof Error?e.message:'Website icon unavailable.'}),{status:400,headers});}
});
