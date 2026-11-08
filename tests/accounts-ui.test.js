import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {fileURLToPath} from 'node:url';
import {writeFile,unlink} from 'node:fs/promises';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';
import {localToday} from '../src/accounts.js';
test('account groups, dated balances, inclusion, stale edits and recoverable archiving work with mock records',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid/household-platform/'});
 globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.FormData=dom.window.FormData;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.accounts-render.mjs',import.meta.url);const built=await build({entryPoints:[fileURLToPath(new URL('../src/pages/AccountsPage.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],write:false});await writeFile(output,built.outputFiles[0].text);
 const {AccountsPage}=await import(output.href);const {createRoot}=await import('react-dom/client');
 const old=new Date(localToday()+'T00:00:00Z');old.setUTCDate(old.getUTCDate()-40);
 const rows=[['bank','checking',null,'CAD'],['savings','savings',0,'CAD'],['card','credit',12000,'CAD'],['loan','loan',null,'CAD'],['invest','investment',50000,'USD'],['home','asset',80000000,'CAD'],['foreign','checking',5000,'USD']].map(([id,kind,minor,currency])=>({id,name:'Mock '+id,kind,currency,revision:1,include_in_net_worth:true,archived_at:null,balance_snapshot:minor===null?null:{id:'snapshot-'+id,amount_minor:minor,currency,as_of:id==='home'?old.toISOString().slice(0,10):localToday(),is_estimate:kind==='asset'}}));
 const history=[];const calls=[];let viewed=null;
 const clone=()=>structuredClone(rows);
 async function secureCall(op,payload){calls.push({op,payload});
  if(op==='create_account'){const t={id:'new',revision:1,archived_at:null,balance_snapshot:null,...payload};rows.push(t);return structuredClone(t);}
  const t=rows.find(a=>a.id===payload.id);assert.ok(t);
  if(payload.revision!==t.revision)throw Error('Account changed; reload before saving');
  if(op==='update_account'){t.name=payload.name;t.include_in_net_worth=payload.include_in_net_worth;}
  else if(op==='save_account_balance'){history.push({...payload});t.balance_snapshot={id:'mock-snapshot-'+history.length,amount_minor:payload.amount_minor,currency:t.currency,as_of:payload.as_of,is_estimate:t.kind==='asset'};}
  else if(op==='archive_account')t.archived_at='2026-11-08';
  else if(op==='restore_account')t.archived_at=null;
  else throw Error('Unexpected '+op);
  t.revision++;return structuredClone(t);
 }
 function Harness(){const [accounts,setAccounts]=React.useState(clone);return React.createElement(AccountsPage,{accounts,secureCall,refresh:async()=>{const fresh=clone();setAccounts(fresh);return fresh;},money:(v,c)=>new Intl.NumberFormat('en-CA',{style:'currency',currency:c}).format(v/100),onViewTransactions:id=>viewed=id});}
 const container=document.getElementById('root'),root=createRoot(container);
 async function click(text,scope=container){await act(async()=>{const b=[...scope.querySelectorAll('button')].find(b=>b.textContent===text);assert.ok(b,text);assert.equal(b.disabled,false,text);b.click();await new Promise(r=>setTimeout(r,0));});}
 async function manage(name){await act(async()=>container.querySelector('[aria-label="Manage account '+name+'"]').click());}
 async function type(label,value){await act(async()=>{const input=container.querySelector('[aria-label="'+label+'"]');Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});}
 const group=id=>container.querySelector('[aria-labelledby="group-'+id+'"]');
 try{
  await act(async()=>root.render(React.createElement(Harness)));
  assert.equal(container.querySelectorAll('.account-group').length,6);assert.match(group('checking').textContent,/Not provided/);assert.doesNotMatch(group('checking').querySelector('.account-subtotals').textContent,/CAD/);assert.match(group('savings').textContent,/\$0\.00/);assert.match(group('credit').textContent,/Amount owed/);assert.match(group('assets').textContent,/Estimated Market Value/);assert.match(group('assets').textContent,/Needs updating/);assert.match(group('investments').textContent,/USD/);
  await manage('Mock bank');assert.equal(container.querySelector('[aria-label="Balance amount"]').value,'');
  await type('Balance amount','125.50');await type('Account name','Mock renamed');await click('Save account settings');assert.equal(container.querySelector('[aria-label="Balance amount"]').value,'125.50');assert.equal(rows[0].balance_snapshot,null);
  await type('Balance note','Mock statement');await click('Save dated balance');assert.equal(rows[0].balance_snapshot.amount_minor,12550);assert.equal(history[0].note,'Mock statement');assert.equal(container.querySelector('dialog [role=alert]'),null);
  await act(async()=>container.querySelector('[aria-label="Include account in net worth"]').click());await click('Save account settings');assert.equal(rows[0].include_in_net_worth,false);
  await click('Archive account');assert.equal(rows[0].archived_at,null);await click('Confirm archive account');assert.ok(rows[0].archived_at);assert.equal(rows[0].balance_snapshot.amount_minor,12550);assert.match(container.querySelector('.archived-accounts').textContent,/Mock renamed/);
  assert.equal(container.querySelector('[aria-label="Balance amount"]'),null);await click('Restore account');assert.equal(rows[0].archived_at,null);assert.equal(rows[0].include_in_net_worth,false);await click('Close account');
  await manage('Mock card');await type('Balance amount','-5.00');await click('Save dated balance');assert.equal(rows[2].balance_snapshot.amount_minor,-500);await click('Close account');assert.match(group('credit').textContent,/Credit balance/);
  await manage('Mock renamed');rows[0].revision++;await type('Account name','Stale mock');await click('Save account settings');assert.match(container.querySelector('dialog [role=alert]').textContent,/Account changed/);assert.equal(rows[0].name,'Mock renamed');await click('Reload account');await click('Reload and discard');assert.equal(container.querySelector('[aria-label="Account name"]').value,'Mock renamed');await click('Close account');
  const create=container.querySelector('.account-create form');create.querySelector('[name="name"]').value='Mock new investment';create.querySelector('[name="kind"]').value='investment';create.querySelector('[name="include"]').checked=false;
  await act(async()=>{create.dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));});assert.equal(rows.at(-1).kind,'investment');assert.equal(rows.at(-1).include_in_net_worth,false);assert.equal(rows.at(-1).balance_snapshot,null);
  await click('View transactions',group('checking').querySelector('.account-card'));assert.equal(viewed,'bank');
 }finally{await act(async()=>root.unmount());await unlink(output);dom.window.close();}
});
