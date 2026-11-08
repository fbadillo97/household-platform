import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {writeFile,unlink} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';
import {receiptMetadata,MAX_RECEIPT_BYTES} from '../src/receipts.js';

test('receipt validation identifies contents and rejects unsupported files',async()=>{
 const file={name:'mock.pdf',size:12,arrayBuffer:async()=>new TextEncoder().encode('%PDF-1.7 mock').buffer};
 const metadata=await receiptMetadata(file);assert.equal(metadata.mime_type,'application/pdf');assert.match(metadata.sha256,/^[a-f0-9]{64}$/);
 await assert.rejects(receiptMetadata({...file,size:MAX_RECEIPT_BYTES+1}),/10 MB/);
 await assert.rejects(receiptMetadata({...file,name:'bad/name.pdf'}),/filename/);
 await assert.rejects(receiptMetadata({...file,arrayBuffer:async()=>new TextEncoder().encode('<html>mock').buffer}),/Choose a PDF/);
});

test('detail panel saves notes and flags, confirms unsaved changes, attaches private receipts and restores Trash',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.detail-render.mjs',import.meta.url);
 const built=await build({entryPoints:[fileURLToPath(new URL('../src/pages/TransactionDetail.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],write:false});await writeFile(output,built.outputFiles[0].text);
 const {TransactionDetail}=await import(output.href);const {createRoot}=await import('react-dom/client');
 const account={id:'mock-account',name:'Mock checking',currency:'CAD'};
 let item={id:'mock-tx',revision:1,date:'2026-10-01',amount_minor:-125,description:'Mock purchase',original_description:'Mock purchase',account_id:account.id,original_account_id:account.id,category_id:null,notes:'',review_status:'unreviewed',needs_attention:false,original_tags:['Mock imported tag'],tags_override:null,receipts:[]};
 let closes=0,failUpload=true,failRemove=true,failCategory=false;const calls=[];const storage=[];
 const clone=()=>structuredClone(item);
 async function secureCall(op,payload){calls.push({op,payload});
  if(op==='get_transaction_detail')return clone();
  if(op==='update_ledger_transaction'){if(failCategory){failCategory=false;throw Error('Mock category conflict; reload before saving');}assert.equal(payload.revision,item.revision);item={...item,...payload,revision:item.revision+1};return {id:item.id,revision:item.revision};}
  if(op==='prepare_receipt'){if(!item.receipts.length)item.receipts.push({...payload,id:'mock-receipt',object_path:'mock/path',state:'pending',revision:1});return {...item.receipts[0],already_exists:item.receipts[0].state==='ready'};}
  if(op==='finish_receipt_upload'){item.receipts[0].state='ready';item.receipts[0].revision++;return {...item.receipts[0]};}
  if(op==='finish_receipt_removal'){item.receipts=[];return {};}
  if(op==='trash_transaction'){assert.equal(payload.revision,item.revision);item.deleted_at='2026-11-01';item.revision++;return clone();}
  if(op==='restore_transaction'){assert.equal(payload.revision,item.revision);item.deleted_at=null;item.revision++;return clone();}
  throw Error('Unexpected operation '+op);
 }
 async function secureReceipt(op,...args){storage.push({op,args});if(op==='upload'&&failUpload){failUpload=false;throw Error('Mock interrupted upload');}if(op==='remove'&&failRemove){failRemove=false;throw Error('Mock interrupted removal');}if(op==='download')return new Blob(['%PDF-1.7 mock']);return {};}
 const container=document.getElementById('root'),root=createRoot(container);
 async function render(key='a'){await act(async()=>{root.render(React.createElement(TransactionDetail,{key,id:item.id,accounts:[account],categories:[{id:'food',name:'Mock food'}],money:v=>String(v),secureCall,secureReceipt,refresh:async()=>{},onClose:()=>closes++}));await new Promise(r=>setTimeout(r,0));});}
 async function click(text){await act(async()=>{const button=[...container.querySelectorAll('button')].find(b=>b.textContent===text);assert.ok(button,text);button.click();await new Promise(r=>setTimeout(r,0));});}
 async function type(selector,value){await act(async()=>{const input=container.querySelector(selector),prototype=input.tagName==='TEXTAREA'?dom.window.HTMLTextAreaElement.prototype:dom.window.HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(prototype,'value').set.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});}
 async function upload(){await act(async()=>{const input=container.querySelector('input[type=file]');Object.defineProperty(input,'files',{configurable:true,value:[{name:'mock.pdf',size:12,arrayBuffer:async()=>new TextEncoder().encode('%PDF-1.7 mock').buffer}]});input.dispatchEvent(new dom.window.Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,30));});}
 try{
  await render();assert.equal(container.querySelector('dialog').open,true);assert.equal(container.querySelector('.original-record').open,false);
  async function category(value){await act(async()=>{const select=container.querySelectorAll('.ledger-editor select')[1];select.value=value;select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,0));});}
  await category('food');assert.equal(item.category_id,'food');assert.deepEqual(calls.find(c=>c.op==='update_ledger_transaction').payload,{id:item.id,revision:1,category_id:'food'});
  assert.equal(container.querySelector('[role=status]'),null);
  failCategory=true;await category('');assert.equal(item.category_id,'food');assert.match(container.querySelector('[role=alert]').textContent,/category conflict/);assert.equal(container.querySelectorAll('.ledger-editor select')[1].value,'');
  await click('Reload details');await click('Reload and discard changes');assert.equal(container.querySelectorAll('.ledger-editor select')[1].value,'food');
  await type('textarea','Mock private note <script>literal</script>');await click('Close');assert.equal(closes,0);assert.match(container.querySelector('[role=alertdialog]').textContent,/Discard unsaved/);await click('Keep editing');
  const updates=calls.filter(c=>c.op==='update_ledger_transaction').length;await category('');assert.equal(calls.filter(c=>c.op==='update_ledger_transaction').length,updates);assert.equal(item.category_id,'food');
  await act(async()=>{container.querySelectorAll('input[type=checkbox]')[0].click();container.querySelectorAll('input[type=checkbox]')[1].click();});
  await type('[aria-label="New tag"]','Local mock tag');await click('Add tag');
  await act(async()=>{container.querySelector('form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));});
  assert.equal(item.notes,'Mock private note <script>literal</script>');assert.equal(item.review_status,'reviewed');assert.equal(item.needs_attention,true);assert.deepEqual(item.tags_override,['Mock imported tag','Local mock tag']);assert.equal(container.querySelector('script'),null);
  await upload();assert.match(container.querySelector('[role=alert]').textContent,/interrupted upload/);assert.equal(calls.some(c=>c.op==='finish_receipt_upload'),false);
  await type('textarea','Unsaved mock change');await click('Reload details');assert.equal(container.querySelector('textarea').value,'Unsaved mock change');await click('Reload and discard changes');assert.equal(container.querySelector('textarea').value,item.notes);
  await upload();assert.equal(item.receipts.length,1);assert.equal(item.receipts[0].state,'ready');assert.equal(storage[0].args[0],'mock/path');assert.equal(storage[0].args[2],'application/pdf');
  await upload();assert.equal(storage.filter(s=>s.op==='upload').length,2);assert.match(container.textContent,/already attached/);
  await click('Remove');await click('Confirm remove receipt');assert.equal(item.receipts.length,1);assert.equal(calls.some(c=>c.op==='finish_receipt_removal'),false);
  await click('Confirm remove receipt');assert.equal(item.receipts.length,0);assert.equal(calls.at(-2).op,'finish_receipt_removal');
  await click('Move to Trash');assert.equal(closes,0);await click('Confirm move to Trash');assert.equal(closes,1);assert.ok(item.deleted_at);
  await render('trashed');assert.ok(container.querySelector('fieldset').disabled);assert.equal(container.querySelector('input[type=file]'),null);await click('Restore transaction');assert.equal(item.deleted_at,null);assert.equal(item.notes,'Mock private note <script>literal</script>');assert.equal(closes,2);
 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
