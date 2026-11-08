import {createClient} from '@supabase/supabase-js';
const url=import.meta.env.VITE_SUPABASE_URL;
const key=import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;
export const configured=Boolean(url&&key&&key.startsWith('sb_publishable_'));
export const client=configured?createClient(url,key,{auth:{persistSession:false,autoRefreshToken:true,detectSessionInUrl:true,experimental:{passkey:true}}}):null;
export async function call(operation,payload={}){
 if(!client)throw Error('Project configuration is missing');
 const {data,error}=await client.rpc('household_v1',{operation,payload});
 if(error)throw error;
 return data;
}
