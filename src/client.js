import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const configured=Boolean(url&&key&&key.startsWith('sb_publishable_'));
export const client=configured?createClient(url,key,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:false,experimental:{passkey:true}}}):null;
export async function call(operation,payload={}){
 if(!client)throw Error('Project configuration is missing');
 const {data,error}=await client.rpc('household_v1',{operation,payload});
 if(error)throw error;
 return data;
}

export async function receiptStorage(action,path,file,mime){
 if(!client)throw Error('Project configuration is missing');
 const bucket=client.storage.from('household-receipts');let result;
 if(action==='upload')result=await bucket.upload(path,file,{contentType:mime,upsert:false,cacheControl:'0'});
 else if(action==='download')result=await bucket.download(path);
 else if(action==='remove')result=await bucket.remove([path]);
 else throw Error('Unknown receipt action');
 if(result.error)throw result.error;
 return result.data;
}
