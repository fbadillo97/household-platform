export function normalizeWebsite(value){
 if(!value.trim())return '';
 const url=new URL(value.includes('://')?value.trim():'https://'+value.trim());
 if(url.protocol!=='https:'||url.username||url.password||url.port&&url.port!=='443'||!url.hostname.includes('.')||url.href.length>1000)throw Error('Use a public HTTPS website.');
 url.hash='';return url.href;
}
export async function websiteLogoPng(result){
 if(!['image/png','image/jpeg','image/webp','image/x-icon'].includes(result.mime)||typeof result.base64!=='string'||result.base64.length>350000)throw Error('Unsupported website image.');
 const raw=Uint8Array.from(atob(result.base64),c=>c.charCodeAt(0)),url=URL.createObjectURL(new Blob([raw],{type:result.mime}));
 let timer;try{
  const image=new Image();image.src=url;await Promise.race([image.decode(),new Promise((_,reject)=>timer=setTimeout(()=>reject(Error('Website image could not be decoded.')),5000))]);
  if(!image.naturalWidth||!image.naturalHeight||image.naturalWidth>4096||image.naturalHeight>4096)throw Error('Website image dimensions are unsupported.');
  for(const size of [128,96,64,32]){const scale=Math.min(1,size/image.naturalWidth,size/image.naturalHeight),canvas=document.createElement('canvas');canvas.width=Math.max(1,Math.round(image.naturalWidth*scale));canvas.height=Math.max(1,Math.round(image.naturalHeight*scale));canvas.getContext('2d').drawImage(image,0,0,canvas.width,canvas.height);const b64=canvas.toDataURL('image/png').split(',')[1];if(atob(b64).length<=16384)return b64;}
  throw Error('Website icon is too large.');
 }finally{clearTimeout(timer);URL.revokeObjectURL(url);}
}
