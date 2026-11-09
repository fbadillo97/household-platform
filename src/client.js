import {createClient} from '@supabase/supabase-js';
import {operationEndpoint} from './planning.js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const configured=Boolean(url&&key&&key.startsWith('sb_publishable_'));
export const client=configured?createClient(url,key,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:false,experimental:{passkey:true}}}):null;
export async function call(operation,payload={}){
 if(!client)throw Error('Project configuration is missing');
 if(operation==='payee_website_logo'){
  const {data,error}=await client.functions.invoke('payee-website-logo',{body:payload});
  if(error){let message='Website logo could not be fetched.';try{message=(await error.context?.json())?.error||message;}catch{}const failure=new Error(message);failure.status=error.context?.status;throw failure;}
  return data;
 }
 const {data,error}=await client.rpc(operationEndpoint(operation),{operation,payload});
 if(error)throw error;
 return data;
}

export async function receiptStorage(action,path,file,mime,bucketName='household-receipts'){
 if(!client)throw Error('Project configuration is missing');
 if(!['household-receipts','household-tax-documents'].includes(bucketName))throw Error('Unknown document bucket');
 const bucket=client.storage.from(bucketName);let result;
 if(action==='upload')result=await bucket.upload(path,file,{contentType:mime,upsert:false,cacheControl:'0'});
 else if(action==='download')result=await bucket.download(path);
 else if(action==='remove')result=await bucket.remove([path]);
 else throw Error('Unknown receipt action');
 if(result.error)throw result.error;
 return result.data;
}
