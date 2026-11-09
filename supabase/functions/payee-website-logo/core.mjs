import {Buffer} from 'node:buffer';
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
function responseHead(bytes){
 const end=bytes.indexOf('\r\n\r\n');if(end<0){if(bytes.length>16384)throw Error('Website headers are too large.');return null;}
 if(end>16384)throw Error('Website headers are too large.');
 const lines=bytes.subarray(0,end).toString('latin1').split('\r\n'),status=Number(/^HTTP\/1\.[01] (\d{3})(?: |$)/.exec(lines.shift()||'')?.[1]);
 if(!status)throw Error('Invalid website response.');const headers={};
 for(const line of lines){const split=line.indexOf(':');if(split<1)throw Error('Invalid website headers.');const key=line.slice(0,split).toLowerCase(),value=line.slice(split+1).trim();
 if((key==='content-length'||key==='transfer-encoding')&&key in headers)throw Error('Ambiguous website response.');headers[key]=value;}
 return {status,headers,offset:end+4};
}
export function responseBody(bytes,headers,limit,eof=false){
 if(headers['transfer-encoding']){
  if(headers['transfer-encoding'].toLowerCase()!=='chunked'||headers['content-length'])throw Error('Unsupported website response framing.');
  let offset=0,total=0;const chunks=[];
  while(true){const end=bytes.indexOf('\r\n',offset);if(end<0){if(bytes.length-offset>128)throw Error('Invalid website chunk.');return null;}
   const line=bytes.subarray(offset,end).toString('ascii').split(';')[0];if(!/^[0-9a-f]{1,8}$/i.test(line))throw Error('Invalid website chunk.');
   const size=parseInt(line,16);if(size===0)return Buffer.concat(chunks,total);if(total+size>limit)throw Error('Website response is too large.');
   offset=end+2;if(bytes.length<offset+size+2)return null;if(bytes[offset+size]!==13||bytes[offset+size+1]!==10)throw Error('Invalid website chunk.');
   chunks.push(bytes.subarray(offset,offset+size));total+=size;offset+=size+2;
  }
 }
 const length=headers['content-length'];if(length!==undefined){if(!/^\d+$/.test(length)||!Number.isSafeInteger(Number(length)))throw Error('Invalid website response length.');if(Number(length)>limit)throw Error('Website response is too large.');return bytes.length>=Number(length)?bytes.subarray(0,Number(length)):null;}
 if(bytes.length>limit)throw Error('Website response is too large.');return eof?bytes:null;
}
// Native TCP pins a validated address; TLS still verifies the original hostname.
export async function readPublic(value,{limit=262144,signal,redirects=0,resolver=lookup,connect=options=>Deno.connect(options),startTls=(socket,options)=>Deno.startTls(socket,options)}={}){
 const url=websiteUrl(String(value)),addresses=await resolvePublic(url.hostname,resolver,signal);
 if(!addresses.length||addresses.some(a=>!publicAddress(a.address)))throw Error('Website resolves to an unavailable network address.');
 const chosen=addresses.find(a=>a.family===4)||addresses[0];let socket;let timedOut=false;
 const close=()=>{try{socket?.close();}catch{}};let rejectDeadline;
 const deadline=new Promise((_,reject)=>{rejectDeadline=reject;});
 const abort=()=>{timedOut=true;close();rejectDeadline(Error('Website request timed out.'));};const timer=setTimeout(abort,5000);signal?.addEventListener('abort',abort,{once:true});
 const bounded=promise=>Promise.race([promise,deadline]);
 try{
  socket=await bounded(Promise.resolve(connect({hostname:chosen.address,port:443,transport:'tcp'})).then(s=>{if(timedOut){s.close();throw Error('Website request timed out.');}return s;}));if(timedOut||signal?.aborted)throw Error('Website request timed out.');
  socket=await bounded(startTls(socket,{hostname:url.hostname,alpnProtocols:['http/1.1']}));if(timedOut||signal?.aborted)throw Error('Website request timed out.');
  const request=new TextEncoder().encode('GET '+url.pathname+url.search+' HTTP/1.1\r\nHost: '+url.hostname+'\r\nUser-Agent: HouseholdPlatform-WebsiteIcon/1.0\r\nAccept: text/html,image/png,image/jpeg,image/webp,image/x-icon,image/vnd.microsoft.icon\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n');
  let sent=0;while(sent<request.length){const written=await bounded(socket.write(request.subarray(sent)));if(!written)throw Error('Website connection closed.');sent+=written;}
  let bytes=Buffer.alloc(0),head=null;const chunk=new Uint8Array(16384);
  while(true){const count=await bounded(socket.read(chunk)),eof=count===null;
   if(count)bytes=Buffer.concat([bytes,Buffer.from(chunk.subarray(0,count))]);if(bytes.length>limit+81920)throw Error('Website response is too large.');
   if(!head){head=responseHead(bytes);if(head){bytes=bytes.subarray(head.offset);if(head.status>=100&&head.status<200){if(head.status===101)throw Error('Unsupported website upgrade.');head=null;continue;}
    if(head.status>=300&&head.status<400){if(redirects>=3||!head.headers.location)throw Error('Too many website redirects.');close();return await readPublic(new URL(head.headers.location,url),{limit,signal,redirects:redirects+1,resolver,connect,startTls});}
    if(head.status!==200)throw Error('Website returned HTTP '+head.status+'.');if(head.headers['content-encoding']&&head.headers['content-encoding']!=='identity')throw Error('Website requires unsupported compression.');
   }}
   if(head){const body=responseBody(bytes,head.headers,limit,eof);if(body!==null)return {status:head.status,headers:head.headers,body,url:url.href};}
   if(eof)throw Error('Website response ended early.');
  }
 }catch(e){if(timedOut||signal?.aborted)throw Error('Website request timed out.');throw e;}finally{clearTimeout(timer);signal?.removeEventListener('abort',abort);close();}
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
 const signal=options.signal||AbortSignal.timeout(15000),read=options.read||readPublic,base=websiteUrl(website).href;let page=null;
 // Large or blocked homepages must not prevent direct icon discovery.
 try{page=await read(base,{signal});}catch(e){if(signal.aborted)throw Error('Website lookup timed out.');}
 const candidates=page&&String(page.headers['content-type']||'').includes('text/html')?iconCandidates(new TextDecoder().decode(page.body),page.url):[];
 for(const path of ['/favicon.ico','/favicon.png','/apple-touch-icon.png']){const url=new URL(path,page?.url||base).href;if(!candidates.includes(url))candidates.push(url);}
 for(const url of candidates.slice(0,8)){try{const img=await read(url,{signal});const mime=rasterType(img.body);return {website:page?.url||base,source_url:img.url,mime,base64:Buffer.from(img.body).toString('base64')};}catch(e){if(signal.aborted)throw Error('Website lookup timed out.');}}
 throw Error('No usable website icon found. Keep the current logo or use a saved logo.');
}
