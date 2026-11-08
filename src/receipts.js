export const MAX_RECEIPT_BYTES=10*1024*1024;
export async function receiptMetadata(file){
 if(!file||file.size<1||file.size>MAX_RECEIPT_BYTES)throw Error('Choose a receipt up to 10 MB.');
 if(!file.name||file.name.length>180||/[\x00-\x1f/\\]/.test(file.name))throw Error('Use a filename up to 180 characters without slashes.');
 const bytes=new Uint8Array(await file.arrayBuffer());
 const starts=(...values)=>values.every((v,i)=>bytes[i]===v);
 const text=(a,b)=>String.fromCharCode(...bytes.slice(a,b));
 let mime;
 if(starts(0x25,0x50,0x44,0x46,0x2d))mime='application/pdf';
 else if(starts(0xff,0xd8,0xff))mime='image/jpeg';
 else if(starts(137,80,78,71,13,10,26,10))mime='image/png';
 else if(text(0,4)==='RIFF'&&text(8,12)==='WEBP')mime='image/webp';
 else throw Error('Choose a PDF, JPEG, PNG or WebP receipt.');
 const hash=await globalThis.crypto.subtle.digest('SHA-256',bytes);
 return {filename:file.name,mime_type:mime,byte_size:bytes.length,sha256:[...new Uint8Array(hash)].map(x=>x.toString(16).padStart(2,'0')).join('')};
}
