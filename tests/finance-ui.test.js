import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';

test('ledger navigation, sorting, column filters, overrides and staged imports work together',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;
 globalThis.FormData=dom.window.FormData;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.finance-render.mjs',import.meta.url);
 const bundle=await build({entryPoints:[fileURLToPath(new URL('../src/Finance.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],loader:{'.css':'empty'},write:false});
 await writeFile(output,bundle.outputFiles[0].text);
 const {createRoot}=await import('react-dom/client');
 const {Finance}=await import(output.href);
 const accounts=[{id:'mock-account',name:'Mock Checking',kind:'checking',currency:'CAD',source_metadata:{currency_assumed:true}},{id:'mock-savings',name:'Mock Savings',kind:'savings',currency:'CAD'}];
 const transactions=[{id:'mock-tx-1',account_id:'mock-account',date:'2026-10-01',description:'Mock shop',amount_minor:-125,category_id:'food',property_id:null,revision:1,source:'monarch',external_id:'mock-source-1',source_data:{tags:[{id:'mock-tag',name:'Renovation'}],notes_provided:true,notes:'Mock private note'}},{id:'mock-tx-2',account_id:'mock-account',date:'2026-10-02',description:'Mock pay',amount_minor:2000,category_id:null,property_id:null,revision:1}];
 const calls=[];
 const secureCall=async(operation,payload)=>{
  calls.push({operation,payload});
  if(operation==='list_ledger_transactions'){
   let rows=transactions.map(t=>({...t,original_description:t.description,original_account_id:t.account_id,description:t.description_override??t.description,account_id:t.account_override_id??t.account_id,has_description_override:!!t.description_override,has_account_override:!!t.account_override_id}));
   if(payload.account_id)rows=rows.filter(t=>t.account_id===payload.account_id);
   if(payload.query)rows=rows.filter(t=>[t.description,...(t.source_data?.tags||[]).map(x=>x.name)].join(' ').toLowerCase().includes(payload.query.toLowerCase()));
   if(payload.min_minor!=null)rows=rows.filter(t=>t.amount_minor>=payload.min_minor);
   if(payload.max_minor!=null)rows=rows.filter(t=>t.amount_minor<=payload.max_minor);
   if(payload.description)rows=rows.filter(t=>t.description.includes(payload.description));
   if(payload.sort==='amount')rows.sort((a,b)=>(a.amount_minor-b.amount_minor)*(payload.direction==='asc'?1:-1));
   return {rows,total:rows.length};
  }
  if(operation==='get_transaction_detail'){
   const t=transactions.find(t=>t.id===payload.id);return {...t,original_description:t.description,original_account_id:t.account_id,original_tags:['Renovation'],receipts:[],description:t.description_override??t.description,account_id:t.account_override_id??t.account_id};
  }
  if(operation==='update_ledger_transaction'){
   const row=transactions.find(t=>t.id===payload.id);assert.equal(row.revision,payload.revision);
   Object.assign(row,{description_override:payload.description_override,account_override_id:payload.account_override_id,category_id:payload.category_id,revision:row.revision+1});return {id:row.id,revision:row.revision};
  }
  if(operation==='stage_import')return {id:'mock-batch',account_id:'mock-account',committed:false,rows:[{id:'mock-stage-row',line:2,error:null,duplicate:false,payload:{date:'2026-10-03',description:'Mock staged item',amount_minor:-100}}]};
  if(operation==='create_account'){accounts.push({id:'mock-second',...payload});return accounts.at(-1);}
  const data={list_payees:[],list_accounts:accounts,list_properties:[],list_categories:[{id:'food',name:'Mock groceries'}],list_transactions:transactions,list_source_snapshots:[{id:'mock-snapshot',source:'monarch',account_name:'Mock Checking',period_start:'2026-05-01',period_end:'2026-10-31',committed_at:'2026-11-01',expected_count:2,inserted_count:2,skipped_count:0,coverage_notes:['Excluded mock institution']} ]};
  if(!(operation in data))throw Error('Unexpected operation: '+operation);
  return data[operation];
 };
 const container=document.getElementById('root');const root=createRoot(container);
 try{
  await act(async()=>{root.render(React.createElement(Finance,{initialToday:'2026-10-31',secureCall,settingsContent:React.createElement('section',null,React.createElement('h2',null,'Account security'))}));await new Promise(r=>setTimeout(r,0));});
  const heading=()=>container.querySelector('h1').textContent;
  async function flushLedger(){await act(async()=>{await new Promise(r=>setTimeout(r,220));});}
  async function openPage(name){await act(async()=>{const link=[...container.querySelectorAll('nav a')].find(a=>a.textContent===name);link.dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true,cancelable:true}));});await flushLedger();}
  async function typeValue(input,value){await act(async()=>{Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});}
  assert.equal(heading(),'Dashboard');
  assert.match(container.textContent,/Mock Checking/);assert.doesNotMatch(container.textContent,/Import coverage|Excluded mock institution/);
  assert.equal(container.querySelector('table'),null);
  assert.equal(container.querySelector('input[type="search"]'),null);
  assert.doesNotMatch(container.textContent,/Account security/);
  await openPage('Transactions');
  assert.equal(heading(),'Transactions');assert.equal(container.querySelectorAll('tbody tr').length,2);
  assert.equal(container.querySelector('nav a[aria-current="page"]').textContent,'Transactions');
  assert.doesNotMatch(container.textContent,/Import coverage|Account security|Source details|Property/);
  const filterPanel=container.querySelector('details.transaction-filters');
  assert.equal(filterPanel.open,false);
  assert.equal(container.querySelector('.ledger-table thead tr').children.length,9);
  assert.equal(container.querySelector('.ledger-table .column-filters'),null);
  await act(async()=>{filterPanel.open=true;});
  const input=container.querySelector('input[type="search"]');
  await act(async()=>{Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,'Renovation');input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
  await flushLedger();
  assert.equal(container.querySelectorAll('tbody tr').length,1);assert.match(container.querySelector('tbody').textContent,/Mock shop/);
  await act(async()=>{filterPanel.open=false;});
  assert.match(filterPanel.querySelector('summary').textContent,/2 active/);
  assert.equal(container.querySelectorAll('.ledger-table tbody>tr').length,1);
  await act(async()=>{filterPanel.open=true;});
  const accountFilter=container.querySelector('[aria-label="Filter account"]');
  await act(async()=>{accountFilter.value='mock-account';accountFilter.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});
  await openPage('Dashboard');
  assert.equal(container.querySelector('table'),null);
  assert.equal(container.querySelector('.filters select').value,'mock-account');
  assert.match(container.querySelector('.money-cards').textContent,/18\.75/); // transaction search must not affect overview totals
  await openPage('Transactions');
  assert.equal(container.querySelector('input[type="search"]').value,'Renovation');
  assert.equal(container.querySelector('.transaction-period select').value,'month');assert.equal(calls.filter(c=>c.operation==='list_ledger_transactions'&&c.payload.limit===50).at(-1).payload.date_from,'2026-10-01');
  assert.equal(container.querySelectorAll('tbody tr').length,1);
  await openPage('Dashboard');
  await act(async()=>{[...container.querySelectorAll('button')].find(b=>b.textContent==='View transactions').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true}));});
  await flushLedger();
  assert.equal(heading(),'Transactions');assert.equal(container.querySelector('input[type="search"]').value,'');
  assert.equal(container.querySelectorAll('tbody tr').length,2);
  await act(async()=>container.querySelector('[aria-label="Sort by Amount"]').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true})));
  await flushLedger();assert.equal(container.querySelector('[aria-label="Sort by Amount"]').closest('th').getAttribute('aria-sort'),'ascending');
  assert.equal(calls.filter(c=>c.operation==='list_ledger_transactions').at(-1).payload.sort,'amount');
  await act(async()=>{container.querySelector('details.transaction-filters').open=true;});
  await typeValue(container.querySelector('[aria-label="Filter maximum amount"]'),'0');await flushLedger();
  assert.equal(container.querySelectorAll('.ledger-table tbody>tr').length,1);
  await act(async()=>[...container.querySelectorAll('button')].find(b=>b.textContent==='Clear all filters').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true})));
  await flushLedger();assert.equal(container.querySelectorAll('.ledger-table tbody>tr').length,2);
  assert.match(container.querySelector('details.transaction-filters summary').textContent,/None active/);
  assert.equal(container.querySelector('.transaction-period select').value,'all');assert.equal(container.querySelector('input[type="month"]'),null);
  await act(async()=>container.querySelector('[aria-label="Edit transaction Mock shop"]').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true})));
  await typeValue(container.querySelector('.ledger-editor input'),'Edited groceries');
  await act(async()=>{const select=container.querySelector('.ledger-editor select');select.value='mock-savings';select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});
  await act(async()=>{container.querySelector('.ledger-editor form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,0));});await flushLedger();
  assert.match(container.querySelector('.ledger-table tbody').textContent,/Edited groceries/);
  assert.equal(transactions[0].description,'Mock shop');assert.equal(transactions[0].account_id,'mock-account');
  assert.equal(calls.find(c=>c.operation==='update_ledger_transaction').payload.account_override_id,'mock-savings');
  await act(async()=>container.querySelector('[aria-label="Close transaction"]').click());
  await act(async()=>container.querySelector('[aria-label="Edit transaction Edited groceries"]').dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true})));
  for(const label of ['Reset description','Reset account'])await act(async()=>[...container.querySelectorAll('.ledger-editor button')].find(b=>b.textContent===label).dispatchEvent(new dom.window.MouseEvent('click',{bubbles:true})));
  await act(async()=>{container.querySelector('.ledger-editor form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,0));});await flushLedger();
  assert.equal(transactions[0].description_override,null);assert.equal(transactions[0].account_override_id,null);
  assert.equal(container.querySelector('.transaction-period select').value,'all');assert.equal(container.querySelector('input[type="month"]'),null); // refresh after saving must not restore a cleared period
  await act(async()=>container.querySelector('[aria-label="Close transaction"]').click());
  const fileInput=container.querySelector('input[type="file"]');
  await act(async()=>{Object.defineProperty(fileInput,'files',{configurable:true,value:[{size:65,text:async()=> 'date,description,amount\n2026-10-03,Mock staged item,-1.00'}]});fileInput.dispatchEvent(new dom.window.Event('change',{bubbles:true}));await new Promise(r=>setTimeout(r,0));});
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);
  await openPage('Dashboard');await openPage('Transactions');
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);
  await openPage('Settings');assert.equal(heading(),'Settings');
  assert.match(container.textContent,/Account security/);assert.doesNotMatch(container.textContent,/Properties/);assert.equal(container.querySelector('.category-table tbody td').textContent,'Mock groceries');
  await openPage('Accounts');assert.equal(heading(),'Accounts');
  const form=container.querySelector('.account-create form');
  form.querySelector('input[name="name"]').value='Another mock account';
  await act(async()=>{form.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,0));});
  assert.deepEqual(calls.find(c=>c.operation==='create_account').payload,{name:'Another mock account',kind:'checking',currency:'CAD',include_in_net_worth:true});
  assert.match(container.textContent,/Another mock account/);
  assert.equal(container.querySelector('[role="alert"]'),null);
  await act(async()=>{window.history.replaceState(null,'','#dashboard');window.dispatchEvent(new dom.window.PopStateEvent('popstate'));});
  assert.equal(heading(),'Dashboard');
  await act(async()=>{window.history.replaceState(null,'','#transactions');window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));});
  assert.equal(heading(),'Transactions');
  assert.equal(container.querySelector('[aria-label="Select CSV line 2"]').checked,true);

 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
