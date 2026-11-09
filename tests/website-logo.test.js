import test from 'node:test';import assert from 'node:assert/strict';
import {websiteUrl,publicAddress,iconCandidates,discoverLogo,readPublic}from '../supabase/functions/payee-website-logo/core.mjs';
import {normalizeWebsite}from '../src/visuals/website.js';
import {resolveVisual}from '../src/visuals/model.js';
import {EventEmitter}from 'node:events';
test('website normalization rejects protocols, credentials, IP encodings and unsafe networks',()=>{
 assert.equal(normalizeWebsite('example.com'),'https://example.com/');assert.equal(websiteUrl('https://example.com/path#secret').href,'https://example.com/path');
 for(const url of ['http://example.com','https://user:pass@example.com','https://127.0.0.1','https://0x7f000001','https://2130706433','https://[::1]','https://example.com:444','https://host.local'])assert.throws(()=>websiteUrl(url));
 for(const ip of ['127.0.0.1','10.0.0.1','169.254.169.254','192.168.1.1','172.16.0.1','100.64.0.1','0.0.0.0','224.0.0.1','::1','::ffff:127.0.0.1','fc00::1','fe80::1','2002:7f00::1','2001:db8::1','2001:0000:0000:0000:0000:0000:7f00:0001','2001:0db8::1','3fff::1'])assert.equal(publicAddress(ip),false,ip);
 for(const ip of ['1.1.1.1','8.8.8.8','2606:4700:4700::1111','2001:4860:4860::8888'])assert.equal(publicAddress(ip),true,ip);
});
test('discovery uses published icon links and bounded fallback without executing HTML',async()=>{
 const base='https://example.com/path';assert.deepEqual(iconCandidates('<link href="/icon.png?a=1&amp;b=2" rel="shortcut icon"><link rel="icon" href="file:///bad"><link rel="icon" href="/logo.svg">',base),['https://example.com/icon.png?a=1&b=2','https://example.com/favicon.ico']);
 const read=async url=>url===base?{url,headers:{'content-type':'text/html'},body:new TextEncoder().encode('<link rel="icon" href="/icon.png">')}:{url,headers:{},body:new Uint8Array([137,80,78,71,13,10,26,10])};
 const result=await discoverLogo(base,{read});assert.equal(result.mime,'image/png');assert.equal(result.source_url,'https://example.com/icon.png');
 await assert.rejects(discoverLogo(base,{read:async url=>url===base?await read(url):{url,headers:{},body:new TextEncoder().encode('<svg></svg>')}}),/No usable/);
});
test('outbound sockets pin a validated public DNS answer and reject private DNS/redirects',async()=>{
 await assert.rejects(readPublic('https://example.com',{resolver:async()=>[{address:'127.0.0.1',family:4}]}),/network address/);
 let pinned=false;
 const request=(options,callback)=>{const req=new EventEmitter();req.setTimeout=()=>{};req.destroy=()=>{};req.end=()=>{options.lookup(options.hostname,{all:false},(_error,address)=>{assert.equal(address,'1.1.1.1');pinned=true;});const res=new EventEmitter();res.statusCode=200;res.headers={'content-type':'image/png'};res.resume=()=>{};res.destroy=()=>{};callback(res);queueMicrotask(()=>{res.emit('data',Buffer.from('ok'));res.emit('end');});};return req;};
 const r=await readPublic('https://example.com',{resolver:async()=>[{address:'1.1.1.1',family:4}],request});assert.equal(pinned,true);assert.equal(r.body.toString(),'ok');
 const redirect=(_options,cb)=>{const req=new EventEmitter();req.setTimeout=()=>{};req.end=()=>{const res=new EventEmitter();res.statusCode=302;res.headers={location:'https://127.0.0.1/private'};res.destroy=()=>{};cb(res);};return req;};
 await assert.rejects(readPublic('https://example.com',{resolver:async()=>[{address:'1.1.1.1',family:4}],request:redirect}),/HTTPS website/);
 await assert.rejects(readPublic('https://example.com',{resolver:async()=>[{address:'1.1.1.1',family:4}],request,limit:1}),/too large/);
});
test('website image respects explicit brand and fallback-only overrides',()=>{
 const entity={id:'p',name:'Mock',website_logo_base64:'mock'};
 assert.equal(resolveVisual({brands:[],preferences:[]},'payee',entity).websiteLogo,'mock');
 for(const mode of ['none','brand'])assert.equal(resolveVisual({brands:[],preferences:[{entity_type:'payee',entity_id:'p',brand_mode:mode}]},'payee',entity).websiteLogo,null);
});
