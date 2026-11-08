import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';
import {localToday} from '../src/accounts.js';
test('dashboard shows partial saved-balance visuals, scopes account links, updates balances and keeps currency/activity independent',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.FormData=dom.window.FormData;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.worth-render.mjs',import.meta.url);const built=await build({entryPoints:[fileURLToPath(new URL('../src/Finance.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],write:false});await writeFile(output,built.outputFiles[0].text);
 const {Finance}=await import(output.href);const {createRoot}=await import('react-dom/client');const today=localToday(),old=new Date(today+'T00:00:00Z');old.setUTCDate(old.getUTCDate()-40);
 const rows=[['bank','checking',10000,'CAD'],['saving','savings',0,'CAD'],['card','credit',2000,'CAD'],['loan','loan',5000,'CAD'],['foreign','investment',30000,'USD'],['home','asset',300000,'CAD'],['missing','investment',null,'CAD']].map(([id,kind,amount,currency])=>({id,name:'Mock '+id,kind,currency,revision:1,include_in_net_worth:true,balance_snapshot:amount===null?null:{amount_minor:amount,currency,as_of:id==='home'?old.toISOString().slice(0,10):today}}));
 rows.push({...rows[0],id:'exclude',name:'Mock excluded',include_in_net_worth:false});rows.push({...rows[2],id:'closed',name:'Mock archived',archived_at:today});
 const calls=[];async function secureCall(op,payload={}){calls.push({op,payload});
  if(op==='list_accounts')return structuredClone(rows);
  if(['list_payees','list_categories','list_source_snapshots'].includes(op))return [];
  if(op==='list_ledger_transactions')return {rows:[{id:'mock-tx',account_id:'bank',date:'2026-10-01',description:'Mock activity',amount_minor:999999}],total:1};
  if(op==='save_account_balance'){const row=rows.find(a=>a.id===payload.id);assert.equal(payload.revision,row.revision);row.revision++;row.balance_snapshot={amount_minor:payload.amount_minor,currency:row.currency,as_of:payload.as_of};return structuredClone(row);}
  throw Error('Unexpected '+op);
 }
 const container=document.getElementById('root'),root=createRoot(container);
 async function click(text,scope=container){await act(async()=>{const button=[...scope.querySelectorAll('button')].find(b=>b.textContent===text);assert.ok(button,text);button.click();await new Promise(r=>setTimeout(r,0));});}
 async function page(name){await act(async()=>[...container.querySelectorAll('nav a')].find(a=>a.textContent===name).click());}
 async function type(input,value){await act(async()=>{Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});}
 const worth=()=>container.querySelector('.net-worth-overview');
 try{
  await act(async()=>{root.render(React.createElement(Finance,{secureCall}));await new Promise(r=>setTimeout(r,0));});
  assert.match(worth().querySelector('.worth-net').textContent,/3,030\.00/);assert.match(worth().querySelector('.worth-cash').textContent,/100\.00/);assert.match(worth().textContent,/Partial overview/);assert.match(worth().textContent,/over 30 days old/);assert.match(worth().textContent,/1 excluded · 1 archived/);assert.ok(worth().querySelector('.worth-bars'));assert.ok(worth().querySelector('.worth-donut'));assert.equal(worth().querySelectorAll('.worth-legend li').length,2);assert.equal(worth().querySelectorAll('[style]').length,0);
  await act(async()=>worth().querySelector('.worth-cash').click());assert.equal(container.querySelector('h1').textContent,'Accounts');assert.match(container.querySelector('.account-scope').textContent,/Cash available/);assert.equal(container.querySelectorAll('.account-group .account-card').length,2);await click('Show all accounts');assert.ok(container.querySelector('[aria-labelledby="group-investments"]'));assert.equal(container.querySelectorAll('.account-group .account-card').length,8);
  await page('Dashboard');await act(async()=>[...worth().querySelectorAll('.worth-legend button')].find(b=>b.textContent.includes('Property & Other Assets')).click());assert.equal(container.querySelectorAll('.account-group .account-card').length,1);assert.match(container.querySelector('.account-group').textContent,/Mock home/);
  await page('Dashboard');await act(async()=>[...worth().querySelectorAll('.worth-account-summary li button')].find(b=>b.textContent.includes('Mock bank')).click());assert.ok(container.querySelector('dialog'));await type(container.querySelector('[aria-label="Balance amount"]'),'150.00');await click('Save dated balance');await click('Close account');await page('Dashboard');assert.match(worth().querySelector('.worth-net').textContent,/3,080\.00/);assert.match(worth().querySelector('.worth-cash').textContent,/150\.00/);
  await type(container.querySelector('input[type=month]'),'1990-01');assert.match(container.querySelector('.money-cards').textContent,/0\.00/);assert.match(worth().querySelector('.worth-net').textContent,/3,080\.00/);
  await act(async()=>{const select=container.querySelector('[aria-label="Net worth currency"]');select.value='USD';select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});assert.match(worth().querySelector('.worth-net').textContent,/300\.00/);assert.match(worth().textContent,/No exchange conversion/);assert.equal(worth().querySelectorAll('.worth-legend li').length,1);assert.doesNotMatch(worth().querySelector('.worth-account-summary').textContent,/Mock home/);
  await act(async()=>{const select=container.querySelector('[aria-label="Net worth currency"]');select.value='CAD';select.dispatchEvent(new dom.window.Event('change',{bubbles:true}));});
  for(const row of rows)row.balance_snapshot=null;await click('Refresh');assert.match(worth().querySelector('.worth-net').textContent,/Not provided/);assert.equal(worth().querySelector('.worth-donut'),null);assert.equal(worth().querySelector('.worth-bars'),null);assert.match(worth().textContent,/Add balances to build your overview/);
  rows[0].balance_snapshot={amount_minor:0,currency:'CAD',as_of:today};await click('Refresh');assert.match(worth().querySelector('.worth-net').textContent,/0\.00/);assert.match(worth().textContent,/No positive equity/);assert.equal(worth().querySelector('.worth-donut'),null);
  assert.equal(worth().querySelector('.worth-bar-equity'),null);
  rows[0].balance_snapshot={amount_minor:100,currency:'CAD',as_of:today};rows[2].balance_snapshot={amount_minor:500,currency:'CAD',as_of:today};await click('Refresh');assert.match(worth().querySelector('.worth-bar-net').textContent,/-\$4\.00/);assert.equal(worth().querySelector('.worth-bar-equity'),null);assert.equal(worth().querySelector('.worth-bar-debt'),null);assert.match(worth().textContent,/Net worth is negative/);
  assert.equal(calls.filter(c=>c.op==='save_account_balance').length,1);
 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
