import https from 'node:https';
import {lookup} from 'node:dns/promises';
import {isIP} from 'node:net';
export function websiteUrl(value){
 if(typeof value!=='string'||value.length>1000)throw Error('Use a public HTTPS website.');
 const url=new URL(value.includes('://')?value:'https://'+value);
 if(url.protocol!=='https:'||url.username||url.password||url.port&&url.port!=='443'||isIP(url.hostname.replace(/^\[|\]$/g,''))||!url.hostname.includes('.')||/(^|\.)(localhost|local|internal|test|invalid|example)$/.test(url.hostname))throw Error('Use a public HTTPS website.');
 url.hash='';return url;
}
export function publicAddress(ip){
 if(isIP(ip)===4){const b=ip.split('.').map(Number),[a,c,d]=b;return !(a===0||a===10||a===127||a>=224||a===100&&c>=64&&c<=127||a===169&&c===254||a===172&&c>=16&&c<=31||a===192&&(c===168||c===0||c===88&&d===99)||a===198&&(c===18||c===19||c===51&&d===100)||a===203&&c===0&&d===113);}
 if(isIP(ip)===6){const [first,second]=ip.split(':').slice(0,2).map(v=>parseInt(v||'0',16));return first>=0x2000&&first<0x4000&&first!==0x2002&&first!==0x3fff&&!(first===0x2001&&(second<=0x1ff||second===0xdb8));}
 return false;
}
async function resolvePublic(host,resolver,signal){
 if(!signal)return resolver(host,{all:true,verbatim:true});
 if(signal.aborted)throw Error('Website request timed out.');
 let stop;const cancelled=new Promise((_,reject)=>{stop=()=>reject(Error('Website request timed out.'));signal.addEventListener('abort',stop,{once:true});});
 try{return await Promise.race([resolver(host,{all:true,verbatim:true}),cancelled]);}finally{signal.removeEventListener('abort',stop);}
}
// Resolve once and pin the HTTPS socket to that address; TLS still verifies the hostname.
export async function readPublic(value,{limit=262144,signal,redirects=0,resolver=lookup,request=https.request}={}){
 const url=websiteUrl(String(value)),addresses=await resolvePublic(url.hostname,resolver,signal);
 if(!addresses.length||addresses.some(a=>!publicAddress(a.address)))throw Error('Website resolves to an unavailable network address.');
 const chosen=addresses.find(a=>a.family===4)||addresses[0];
 const result=await new Promise((resolve,reject)=>{
  const req=request({protocol:'https:',hostname:url.hostname,servername:url.hostname,port:443,path:url.pathname+url.search,method:'GET',agent:false,signal,maxHeaderSize:16384,
   lookup:(_host,options,cb)=>{if(typeof options==='function'){cb=options;options={};}if(options?.all)cb(null,[chosen]);else cb(null,chosen.address,chosen.family);},
   headers:{'User-Agent':'HouseholdPlatform-WebsiteIcon/1.0','Accept':'text/html,image/png,image/jpeg,image/webp,image/x-icon,image/vnd.microsoft.icon','Accept-Encoding':'identity'}},res=>{
   const status=res.statusCode||0,headers=res.headers;
   if(status>=300&&status<400){res.destroy();resolve({status,headers,body:new Uint8Array()});return;}
   if(status!==200){res.destroy();reject(Error('Website image is unavailable.'));return;}
   if(Number(headers['content-length']||0)>limit){res.destroy();reject(Error('Website response is too large.'));return;}
   const chunks=[];let size=0;res.on('data',part=>{size+=part.length;if(size>limit){res.destroy();reject(Error('Website response is too large.'));}else chunks.push(part);});
   res.on('error',reject);res.on('end',()=>resolve({status,headers,body:Buffer.concat(chunks)}));
  });req.setTimeout(5000,()=>req.destroy(Error('Website request timed out.')));req.on('error',reject);req.end();
 });
 if(result.status>=300&&result.status<400){if(redirects>=3||!result.headers.location)throw Error('Too many website redirects.');return readPublic(new URL(result.headers.location,url),{limit,signal,redirects:redirects+1,resolver,request});}
 return {...result,url:url.href};
}
export function iconCandidates(html,base){
 const icons=[];
 for(const link of html.match(/<link\b[^>]{0,3000}>/gi)||[]){
  const attrs={};for(const m of link.matchAll(/([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g))attrs[m[1].toLowerCase()]=m[2]??m[3]??m[4];
  if(!/(?:^|\s)(?:icon|apple-touch-icon|apple-touch-icon-precomposed)(?:\s|$)/i.test(attrs.rel||'')||!attrs.href)continue;
  try{const u=websiteUrl(new URL(attrs.href.replaceAll('&amp;','&'),base).href);if(!/\.svg(?:\?|$)/i.test(u.href))icons.push(u.href);}catch{}
 }
 return [...new Set([...icons,new URL('/favicon.ico',base).href])].slice(0,5);
}
export function rasterType(body,header=''){
 const b=body;if(b.length>=8&&b[0]===137&&b[1]===80&&b[2]===78&&b[3]===71)return 'image/png';
 if(b.length>=3&&b[0]===255&&b[1]===216&&b[2]===255)return 'image/jpeg';
 if(b.length>=12&&String.fromCharCode(...b.slice(0,4))==='RIFF'&&String.fromCharCode(...b.slice(8,12))==='WEBP')return 'image/webp';
 if(b.length>=6&&b[0]===0&&b[1]===0&&b[2]===1&&b[3]===0)return 'image/x-icon';
 throw Error('No supported website icon was found.');
}
export async function discoverLogo(website,options={}){
 const signal=options.signal||AbortSignal.timeout(15000),read=options.read||readPublic;const page=await read(website,{signal});
 if(!String(page.headers['content-type']||'').includes('text/html'))throw Error('Website did not return an HTML page.');
 const candidates=iconCandidates(new TextDecoder().decode(page.body),page.url);
 for(const url of candidates){try{const img=await read(url,{signal});const mime=rasterType(img.body);return {website:page.url,source_url:img.url,mime,base64:Buffer.from(img.body).toString('base64')};}catch(e){if(signal.aborted)throw Error('Website lookup timed out.');}}
 throw Error('No usable website icon found. Keep the current logo or use a saved logo.');
}
