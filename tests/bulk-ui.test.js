import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';
import {tagNames,EMPTY_COLUMN_FILTERS} from '../src/finance.js';

test('page-scoped selection, bulk previews, preserved tags, stale retry, linked Trash guard and bulk Restore work together',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.bulk-render.mjs',import.meta.url);
 const bundle=await build({entryPoints:[fileURLToPath(new URL('../src/pages/TransactionsPage.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],loader:{'.css':'empty'},write:false});await writeFile(output,bundle.outputFiles[0].text);
 const {TransactionsPage}=await import(output.href);const {createRoot}=await import('react-dom/client');
 const rows=Array.from({length:55},(_,i)=>({id:'mock-'+i,revision:1,date:'2026-10-01',description:'Mock '+String(i).padStart(2,'0'),account_id:'mock-bank',amount_minor:-100,category_id:null,review_status:'unreviewed',needs_attention:false,notes:'Mock note '+i,receipt_count:i===2?1:0,source_data:{tags:[{name:i===3?'Existing':'Home'}]},flow_type:i===0?'transfer':'regular',transfer_peer_id:i===0?'mock-external-peer':null,deleted_at:null}));
 const calls=[];
 async function secureCall(op,payload){calls.push({op,payload});
  if(op==='list_ledger_transactions'){
   let data=rows.filter(t=>payload.trash_only?!!t.deleted_at:!t.deleted_at);
   if(payload.description)data=data.filter(t=>t.description.includes(payload.description));
   return {rows:structuredClone(data.slice(payload.offset,payload.offset+payload.limit)),total:data.length,trash_total:rows.filter(t=>t.deleted_at).length};
  }
  if(op==='bulk_update_transactions'){
   assert.ok(payload.items.length<=50);const targets=payload.items.map(v=>rows.find(t=>t.id===v.id));
   if(payload.items.some((v,i)=>v.revision!==targets[i].revision))throw Error('A selected transaction changed; refresh and select again. Nothing was changed');
   assert.ok(payload.action!=='trash'||targets.every(t=>!t.transfer_peer_id));
   let changed=0;for(const t of targets){let different=true;const value=payload.value;
    if(payload.action==='category'){different=t.category_id!==value;t.category_id=value;}
    else if(payload.action==='review'){different=t.review_status!==value;t.review_status=value;}
    else if(payload.action==='attention'){different=t.needs_attention!==value;t.needs_attention=value;}
    else if(payload.action==='add_tag'){const tags=tagNames(t);different=!tags.some(x=>x.toLowerCase()===value.toLowerCase());if(different)t.tags_override=[...tags,value];}
    else if(payload.action==='remove_tag'){const tags=tagNames(t);different=tags.some(x=>x.toLowerCase()===value.toLowerCase());if(different)t.tags_override=tags.filter(x=>x.toLowerCase()!==value.toLowerCase());}
    else if(payload.action==='trash')t.deleted_at='2026-11-08';
    else if(payload.action==='restore')t.deleted_at=null;
    if(different){changed++;t.revision++;}
   }return {selected_count:targets.length,updated_count:changed,action:payload.action};
  }throw Error('Unexpected '+op);
 }
 function Harness(){
  const [view,setView]=React.useState({columns:{...EMPTY_COLUMN_FILTERS},sort:'date',direction:'desc',offset:0}),[version,setVersion]=React.useState(0),[accountFilter,setAccountFilter]=React.useState(''),[month,setMonth]=React.useState(''),[query,setQuery]=React.useState('');
  return React.createElement(TransactionsPage,{accounts:[{id:'mock-bank',name:'Mock checking',currency:'CAD'}],categories:[{id:'food',name:'Mock food'}],money:v=>String(v),busy:false,run:async work=>work(),secureCall,refresh:async()=>setVersion(v=>v+1),refreshVersion:version,filters:null,view,setView,accountFilter,setAccountFilter,month,setMonth,query,setQuery});
 }
 const container=document.getElementById('root'),root=createRoot(container);
 async function pause(){await act(async()=>{await new Promise(r=>setTimeout(r,220));});}
 async function click(text){await act(async()=>{const b=[...container.querySelectorAll('button')].find(b=>b.textContent===text);assert.ok(b,text);assert.equal(b.disabled,false,text+' disabled');b.click();await new Promise(r=>setTimeout(r,0));});}
 async function checkbox(label){await act(async()=>{const input=container.querySelector('[aria-label="'+label+'"]');assert.ok(input,label);assert.equal(input.disabled,false);input.click();});}
 async function choose(label,value){await act(async()=>{const select=container.querySelector('[aria-label="'+label+'"]');select.value=value;select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});}
 async function type(label,value){await act(async()=>{const input=container.querySelector('[aria-label="'+label+'"]');Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});}
 async function selectTwo(){await checkbox('Select transaction Mock 02');await checkbox('Select transaction Mock 03');}
 async function apply(action,label,value){await choose('Bulk action',action);if(label){if(label==='Bulk tag')await type(label,value);else await choose(label,value);}await click('Review bulk change');await click(action==='trash'?'Confirm move to Trash':action==='restore'?'Confirm restore':'Confirm bulk update');await pause();}
 const bulkCalls=()=>calls.filter(c=>c.op==='bulk_update_transactions');
 try{
  await act(async()=>root.render(React.createElement(Harness)));await pause();
  assert.equal(container.querySelectorAll('.ledger-table tbody tr').length,50);
  await checkbox('Select transaction Mock 02');assert.equal(container.querySelector('[aria-label="Select all transactions on this page"]').indeterminate,true);assert.equal(calls.some(c=>c.op==='get_transaction_detail'),false);
  await checkbox('Select all transactions on this page');assert.match(container.querySelector('.bulk-selection').textContent,/50 selected/);
  await choose('Bulk category','food');await click('Review bulk change');assert.equal(bulkCalls().length,0);assert.equal(container.querySelectorAll('.bulk-preview li').length,50);assert.match(container.querySelector('dialog').textContent,/Set category to Mock food/);
  await click('Cancel bulk change');assert.equal(rows[0].category_id,null);await click('Review bulk change');await click('Confirm bulk update');await pause();
  assert.equal(bulkCalls()[0].payload.items.length,50);assert.equal(rows[49].category_id,'food');assert.equal(rows[50].category_id,null);assert.equal(container.querySelector('.bulk-actions'),null);
  await selectTwo();await apply('review','Bulk review status','reviewed');assert.equal(rows[2].review_status,'reviewed');assert.equal(rows[3].review_status,'reviewed');
  await selectTwo();await apply('attention','Bulk attention status','true');assert.equal(rows[2].needs_attention,true);
  await selectTwo();await choose('Bulk action','add_tag');await type('Bulk tag','Shared');await click('Review bulk change');assert.match(container.querySelector('.bulk-preview').textContent,/Home → Home, Shared/);await click('Confirm bulk update');await pause();
  assert.deepEqual(tagNames(rows[2]),['Home','Shared']);assert.deepEqual(tagNames(rows[3]),['Existing','Shared']);assert.deepEqual(rows[2].source_data.tags,[{name:'Home'}]);
  await selectTwo();await apply('remove_tag','Bulk tag','SHARED');assert.deepEqual(tagNames(rows[2]),['Home']);assert.deepEqual(tagNames(rows[3]),['Existing']);assert.equal(rows[2].notes,'Mock note 2');
  // A selected snapshot never silently refreshes its revision behind the confirmation.
  await selectTwo();rows[3].revision++;await choose('Bulk action','attention');await choose('Bulk attention status','false');await click('Review bulk change');await click('Confirm bulk update');
  assert.match(container.querySelector('dialog [role=alert]').textContent,/Nothing was changed/);assert.equal(rows[2].needs_attention,true);assert.match(container.querySelector('.bulk-selection').textContent,/2 selected/);await click('Refresh and select again');await pause();assert.equal(container.querySelector('.bulk-actions'),null);
  await checkbox('Select transaction Mock 02');await type('Filter description','Mock 02');await pause();assert.equal(container.querySelector('.bulk-actions'),null);assert.equal(container.querySelectorAll('.ledger-table tbody tr').length,1);
  await click('Clear all filters');await pause();await checkbox('Select transaction Mock 02');await click('Next');await pause();assert.equal(container.querySelectorAll('.ledger-table tbody tr').length,5);assert.equal(container.querySelector('.bulk-actions'),null);
  await checkbox('Select all transactions on this page');assert.match(container.querySelector('.bulk-selection').textContent,/5 selected/);await click('Previous');await pause();assert.equal(container.querySelector('.bulk-actions'),null);
  await checkbox('Select transaction Mock 02');await click('Trash (0)');await pause();assert.equal(container.querySelector('.bulk-actions'),null);await click('Active');await pause();
  await checkbox('Select all transactions on this page');await choose('Bulk action','trash');assert.match(container.querySelector('.bulk-actions').textContent,/1 linked transfer must be unlinked/);assert.equal([...container.querySelectorAll('button')].find(b=>b.textContent==='Review bulk change').disabled,true);await click('Deselect linked transfers');assert.match(container.querySelector('.bulk-selection').textContent,/49 selected/);await click('Clear selection');
  await selectTwo();await choose('Bulk action','trash');await click('Review bulk change');assert.equal(rows[2].deleted_at,null);await click('Confirm move to Trash');await pause();assert.ok(rows[2].deleted_at);assert.equal(rows[2].receipt_count,1);assert.equal(rows[2].notes,'Mock note 2');
  await click('Trash (2)');await pause();assert.equal(container.querySelectorAll('.ledger-table tbody tr').length,2);await checkbox('Select all transactions on this page');assert.equal(container.querySelector('[aria-label="Bulk action"]').options.length,1);await apply('restore');assert.equal(rows[2].deleted_at,null);assert.equal(rows[3].deleted_at,null);assert.equal(container.querySelector('.bulk-actions'),null);
 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
