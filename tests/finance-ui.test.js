import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';

test('pages isolate overview/records/settings and preserve filters and staged imports',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;
 globalThis.FormData=dom.window.FormData;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.finance-render.mjs',import.meta.url);
 const bundle=await build({entryPoints:[fileURLToPath(new URL('../src/Finance.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],write:false});
 await writeFile(output,bundle.outputFiles[0].text);
 const {createRoot}=await import('react-dom/client');
 const {Finance}=await import(output.href);
 const accounts=[{id:'mock-account',name:'Mock Checking',kind:'checking',currency:'CAD',source_metadata:{currency_assumed:true}}];
 const transactions=[{id:'mock-tx-1',account_id:'mock-account',date:'2026-10-01',description:'Mock shop',amount_minor:-125,category_id:'food',property_id:null,revision:1,source:'monarch',external_id:'mock-source-1',source_data:{tags:[{id:'mock-tag',name:'Renovation'}],notes_provided:true,notes:'Mock private note'}},{id:'mock-tx-2',account_id:'mock-account',date:'2026-10-02',description:'Mock pay',amount_minor:2000,category_id:null,property_id:null,revision:1}];
 const calls=[];
 const secureCall=async(operation,payload)=>{
  calls.push({operation,payload});
  if(operation==='stage_import')return {id:'mock-batch',account_id:'mock-account',committed:false,rows:[{id:'mock-stage-row',line:2,error:null,duplicate:false,payload:{date:'2026-10-03',description:'Mock staged item',amount_minor:-100}}]};
  if(operation==='create_account'){accounts.push({id:'mock-second',...payload});return accounts.at(-1);}
  const data={list_accounts:accounts,list_properties:[],list_categories:[{id:'food',name:'Mock groceries'}],list_transactions:transactions,list_source_snapshots:[{id:'mock-snapshot',source:'monarch',account_name:'Mock Checking',period_start:'2026-10-01',period_end:'2026-10-31',committed_at:'2026-11-01',expected_count:2,inserted_count:2,skipped_count:0,coverage_notes:['Excluded mock institution']} ]};
  if(!(operation in data))throw Error('Unexpected operation: '+operation);
  return data[operation];
 };
 const container=document.getElementById('root');const root=createRoot(container);
 try{
  await act(async()=>{root.render(React.createElement(Finance,{secureCall,settingsContent:React.createElement('section',null,React.createElement('h2',null,'Account security'))}));await new Promise(r=>setTimeout(r,0));});
  const heading=()=>container.querySelector('h1').textContent;
  async function openPage(name){await act(async()=>{const link=[...container.querySelectorAll('nav a')].find(a=>a.textContent===name);link.dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true,cancelable:true}));});}
  assert.equal(heading(),'Dashboard');
  assert.match(container.textContent,/Mock Checking/);assert.match(container.textContent,/Excluded mock institution/);
  assert.equal(container.querySelector('table'),null);
  assert.equal(container.querySelector('input[type="search"]'),null);
  assert.doesNotMatch(container.textContent,/Account security/);
  await openPage('Transactions');
  assert.equal(heading(),'Transactions');assert.equal(container.querySelectorAll('tbody tr').length,2);
  assert.equal(container.querySelector('nav a[aria-current="page"]').textContent,'Transactions');
  assert.doesNotMatch(container.textContent,/Import coverage|Account security/);
  const input=container.querySelector('input[type="search"]');
  await act(async()=>{Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,'Renovation');input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
  assert.equal(container.querySelectorAll('tbody tr').length,1);assert.match(container.querySelector('tbody').textContent,/Mock shop/);
  const accountFilter=container.querySelector('.filters select');
  await act(async()=>{accountFilter.value='mock-account';accountFilter.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});
  await openPage('Dashboard');
  assert.equal(container.querySelector('table'),null);
  assert.equal(container.querySelector('.filters select').value,'mock-account');
  assert.match(container.querySelector('.money-cards').textContent,/18\.75/); // transaction search must not affect overview totals
  await openPage('Transactions');
  assert.equal(container.querySelector('input[type="search"]').value,'Renovation');
  assert.equal(container.querySelector('input[type="month"]').value,'2026-10');
  assert.equal(container.querySelectorAll('tbody tr').length,1);
  await openPage('Dashboard');
  await act(async()=>{[...container.querySelectorAll('button')].find(b=>b.textContent==='View transactions').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true}));});
  assert.equal(heading(),'Transactions');assert.equal(container.querySelector('input[type="search"]').value,'');
  assert.equal(container.querySelectorAll('tbody tr').length,2);
  assert.equal(calls.filter(c=>c.operation==='list_transactions').length,1); // navigation must not reload private data or reset shared state
  const fileInput=container.querySelector('input[type="file"]');
  await act(async()=>{Object.defineProperty(fileInput,'files',{configurable:true,value:[{size:65,text:async()=> 'date,description,amount\n2026-10-03,Mock staged item,-1.00'}]});fileInput.dispatchEvent(new dom.window.Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,0));});
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);
  await openPage('Dashboard');await openPage('Transactions');
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);
  await openPage('Settings');assert.equal(heading(),'Settings');
  assert.match(container.textContent,/Account security/);assert.equal(container.querySelector('table'),null);
  const form=[...container.querySelectorAll('form')].find(f=>f.querySelector('button')?.textContent==='Add account');
  form.querySelector('input[name="name"]').value='Another mock account';
  await act(async()=>{form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,0));});
  assert.deepEqual(calls.find(c=>c.operation==='create_account').payload,{name:'Another mock account',kind:'checking',currency:'CAD'});
  assert.match(container.textContent,/Another mock account/);
  assert.equal(container.querySelector('[role="alert"]'),null);
  await act(async()=>{window.history.replaceState(null,'','#dashboard');window.dispatchEvent(new dom.window.PopStateEvent('popstate'));});
  assert.equal(heading(),'Dashboard');
  await act(async()=>{window.history.replaceState(null,'','#transactions');window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));});
  assert.equal(heading(),'Transactions');
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);

 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
