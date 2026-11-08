import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';

test('confirmed transfer workflow updates dashboard, classifies a single side, links suggestions, filters and undoes both sides',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.transfers-render.mjs',import.meta.url);
 const bundle=await build({entryPoints:[fileURLToPath(new URL('../src/Finance.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],write:false});await writeFile(output,bundle.outputFiles[0].text);
 const {Finance}=await import(output.href);const {createRoot}=await import('react-dom/client');
 const accounts=[{id:'bank',name:'Mock bank',currency:'CAD',kind:'checking'},{id:'card',name:'Mock card',currency:'CAD',kind:'credit'}];
 const rows=[{id:'pay',account_id:'bank',date:'2026-10-01',description:'Mock salary',amount_minor:20000},{id:'purchase',account_id:'card',date:'2026-10-02',description:'Mock groceries',amount_minor:-5000},{id:'out',account_id:'bank',date:'2026-10-03',description:'Mock bill payment',amount_minor:-10000},{id:'in',account_id:'card',date:'2026-10-04',description:'Mock card payment',amount_minor:10000}].map(t=>({...t,revision:1,flow_type:'regular',transfer_peer_id:null}));
 const categories=[{id:'card-payment',name:'Credit Card Payment',accounting_behavior:'credit_card_payment'}];
 const calls=[];
 function detail(t){return {...structuredClone(t),original_description:t.description,original_account_id:t.account_id,original_tags:[],receipts:[],transfer_peer:structuredClone(rows.find(p=>p.id===t.transfer_peer_id)||null)};}
 async function secureCall(op,payload={}){calls.push({op,payload});
  if(op==='list_accounts')return accounts;
  if(op==='list_payees')return [];
  if(op==='list_categories')return categories;
  if(op==='list_source_snapshots')return [];
  if(op==='list_ledger_transactions'){let data=rows.filter(t=>payload.flow==='unlinked_transfer'?t.flow_type!=='regular'&&!t.transfer_peer_id:!payload.flow||t.flow_type===payload.flow);return {rows:structuredClone(data),total:data.length,trash_total:0};}
  const t=rows.find(t=>t.id===payload.id);
  if(op==='get_transaction_detail')return detail(t);
  if(op==='list_transfer_candidates')return {total:1,rows:[{...rows.find(r=>r.id==='in'),suggested_type:'credit_card_payment'}]};
  if(op==='update_ledger_transaction'){assert.equal(t.revision,payload.revision);t.category_id=payload.category_id;t.flow_type=categories.find(c=>c.id===t.category_id)?.accounting_behavior||'regular';t.revision++;return detail(t);}
  if(['link_transfer','unlink_transfer'].includes(op)){const p=rows.find(r=>r.id===payload.peer_id);assert.equal(t.revision,payload.revision);assert.equal(p.revision,payload.peer_revision);for(const [one,other] of [[t,p],[p,t]]){one.flow_type=op==='link_transfer'?payload.flow_type:(categories.find(c=>c.id===one.category_id)?.accounting_behavior||'regular');one.transfer_peer_id=op==='link_transfer'?other.id:null;one.revision++;}return detail(t);}
  throw Error('Unexpected '+op);
 }
 const container=document.getElementById('root'),root=createRoot(container);
 async function pause(){await act(async()=>{await new Promise(r=>setTimeout(r,220));});}
 async function click(text,scope=container){await act(async()=>{const b=[...scope.querySelectorAll('button')].find(b=>b.textContent===text);assert.ok(b,text);b.click();await new Promise(r=>setTimeout(r,0));});}
 async function page(text){await act(async()=>[...container.querySelectorAll('nav a')].find(a=>a.textContent===text).click());await pause();}
 async function change(select,value){await act(async()=>{select.value=value;select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});}
 async function open(){await act(async()=>container.querySelector('[aria-label="Edit transaction Mock bill payment"]').click());}
 try{
  await act(async()=>{root.render(React.createElement(Finance,{secureCall}));await new Promise(r=>setTimeout(r,0));});
  assert.match(container.querySelector('.money-cards article').textContent,/300\.00/);
  await page('Transactions');await open();
  assert.equal(container.querySelector('[aria-label="Transaction type"]'),null);
  assert.equal(container.querySelector('.transfer-section'),null);
  await change(container.querySelector('.ledger-editor select[value]')||container.querySelectorAll('.ledger-editor select')[1],'card-payment');
  await pause();assert.equal(rows[2].flow_type,'credit_card_payment');assert.equal(rows[2].transfer_peer_id,null);
  assert.equal(container.querySelector('.ledger-editor button:not([type=button])')?.disabled,true);
  await click('Close');await page('Dashboard');assert.match(container.querySelector('.money-cards article:nth-child(2)').textContent,/50\.00/);assert.match(container.querySelector('.transfer-overview').textContent,/1 without a linked counterpart/);
  await click('Review unlinked transfers');await pause();assert.equal(container.querySelectorAll('.ledger-table tbody tr').length,1);assert.equal(calls.filter(c=>c.op==='list_ledger_transactions').at(-1).payload.flow,'unlinked_transfer');
  await open();const matches=container.querySelector('.transfer-matches');await act(async()=>{matches.open=true;});await click('Find matching entries');assert.match(matches.textContent,/1 possible match/);assert.equal(rows[2].transfer_peer_id,null);
  await click('Review match');assert.match(container.querySelector('[aria-label="Confirm transfer change"]').textContent,/Mock card payment/);await click('Confirm link');await pause();assert.equal(rows[2].transfer_peer_id,'in');assert.equal(rows[3].transfer_peer_id,'out');
  assert.match(container.querySelector('.linked-transfer').textContent,/Mock card/);
  await click('Close');await page('Dashboard');assert.match(container.querySelector('.money-cards article:first-child').textContent,/200\.00/);assert.match(container.querySelector('.money-cards article:nth-child(2)').textContent,/50\.00/);
  await page('Transactions');await click('Clear all filters');await pause();await open();
  await click('Undo linked transfer');assert.equal(rows[2].flow_type,'credit_card_payment');await click('Confirm undo link');await pause();assert.equal(rows[2].flow_type,'credit_card_payment');assert.equal(rows[3].flow_type,'regular');assert.equal(rows[3].transfer_peer_id,null);
  // Unsaved details block transfer linking so notes cannot be silently discarded.
  await act(async()=>{const input=container.querySelector('textarea');Object.getOwnPropertyDescriptor(dom.window.HTMLTextAreaElement.prototype,'value').set.call(input,'Mock unsaved note');input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
  assert.equal(container.querySelector('.transfer-matches fieldset').disabled,true);
  await click('Close');await click('Discard changes');await page('Dashboard');assert.match(container.querySelector('.money-cards article:first-child').textContent,/300\.00/);
 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
