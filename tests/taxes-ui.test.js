import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {writeFile,unlink} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {JSDOM} from 'jsdom';
import React,{act} from 'react';
import {mockTaxApi} from './taxes/mock.js';
test('tax workspace drills into missing receipts, saves checklist, preserves failed drafts and previews bulk flags',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid'});globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.tax-render.mjs',import.meta.url);const built=await build({entryPoints:[fileURLToPath(new URL('../src/taxes/TaxesPage.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],loader:{'.css':'empty'},write:false});await writeFile(output,built.outputFiles[0].text);
 const {TaxesPage}=await import(output.href),{createRoot}=await import('react-dom/client'),api=mockTaxApi();const root=createRoot(document.getElementById('root')),container=document.getElementById('root');
 async function click(text,exact=true){await act(async()=>{const button=[...container.querySelectorAll('button')].find(b=>exact?b.textContent===text:b.textContent.includes(text));assert.ok(button,'Missing button: '+text);assert.equal(button.disabled,false,'Disabled button: '+text);button.click();await new Promise(r=>setTimeout(r,10));});}
 async function input(label,value){await act(async()=>{const element=[...(container.querySelector('dialog')||container).querySelectorAll('label')].find(l=>l.textContent.startsWith(label))?.querySelector('input,textarea,select');assert.ok(element,'Missing input '+label);const proto=element.tagName==='TEXTAREA'?dom.window.HTMLTextAreaElement.prototype:element.tagName==='SELECT'?dom.window.HTMLSelectElement.prototype:dom.window.HTMLInputElement.prototype;Object.getOwnPropertyDescriptor(proto,'value').set.call(element,value);element.dispatchEvent(new dom.window.Event(element.tagName==='SELECT'?'change':'input',{bubbles:true}));});}
 try{
  await act(async()=>{root.render(React.createElement(TaxesPage,{secureCall:api.call,initialYear:2026}));await new Promise(r=>setTimeout(r,20));});
  assert.match(container.textContent,/Checklist collected1 \/ 3/);assert.match(container.textContent,/Mock person A · FBAR/);
  await click('Missing receipts',false);assert.match(container.textContent,/Mock medical purchase/);assert.doesNotMatch(container.textContent,/Mock charity/);
  await click('Overview');await click('Still to collect',false);assert.match(container.textContent,/Mock donation receipts/);assert.match(container.textContent,/Mock prior return/);assert.doesNotMatch(container.textContent,/Mock employment slip/);
  await click('Add checklist item');await input('Item','Mock investment slip');assert.equal(container.querySelector('dialog form').checkValidity(),true,JSON.stringify([...container.querySelectorAll('dialog input,dialog select')].map(e=>({value:e.value,name:e.outerHTML,valid:e.checkValidity()}))));await click('Save changes');assert.ok(api.calls.some(c=>c.operation==='tax_save_item'),JSON.stringify(api.calls));assert.equal(api.state.items.at(-1).title,'Mock investment slip');assert.equal(container.querySelector('dialog'),null);
  await click('Mock investment slip');await input('Notes','Preserve this failed draft');api.fail();await click('Save changes');assert.match(container.textContent,/Mock conflict/);assert.equal(container.querySelector('textarea').value,'Preserve this failed draft');await click('Close');assert.ok(container.querySelector('[role=alertdialog]'));await click('Keep editing');await click('Save changes');assert.equal(api.state.items.at(-1).notes,'Preserve this failed draft');
  await click('Expenses & receipts');await click('Flag transactions');await act(async()=>{await new Promise(r=>setTimeout(r,260));});assert.match(container.textContent,/Mock deductible candidate/);
  await act(async()=>{const check=container.querySelector('input[aria-label="Select Mock deductible candidate"]');check.click();});await input('Tax purpose','Mock donation review');await click('Review 1 flags');assert.equal(api.calls.some(c=>c.operation==='tax_flag_expenses'),false);await click('Confirm flags');assert.equal(api.state.expenses.at(-1).purpose,'Mock donation review');
  await click('Mock medical purchase');await click('Archive');assert.doesNotMatch(container.textContent,/Mock medical purchase/);
 }finally{await act(async()=>root.unmount());dom.window.close();await unlink(output);delete globalThis.window;delete globalThis.document;delete globalThis.HTMLElement;delete globalThis.IS_REACT_ACT_ENVIRONMENT;}
});

test('late tax-year responses cannot overwrite the selected year and loading errors remain actionable',async()=>{
 const dom=new JSDOM('<!doctype html><div id="root"></div>',{url:'https://example.invalid'});globalThis.window=dom.window;globalThis.document=dom.window.document;globalThis.HTMLElement=dom.window.HTMLElement;globalThis.IS_REACT_ACT_ENVIRONMENT=true;
 const output=new URL('./.tax-race-render.mjs',import.meta.url),built=await build({entryPoints:[fileURLToPath(new URL('../src/taxes/TaxesPage.jsx',import.meta.url))],bundle:true,platform:'node',format:'esm',external:['react'],loader:{'.css':'empty'},write:false});await writeFile(output,built.outputFiles[0].text);
 const {TaxesPage}=await import(output.href),{createRoot}=await import('react-dom/client'),api=mockTaxApi(),root=createRoot(document.getElementById('root'));let resolveOld,first=true;
 const call=async(op,payload)=>{if(first){first=false;return new Promise(resolve=>{resolveOld=resolve;});}return api.call(op,payload);};
 try{await act(async()=>{root.render(React.createElement(TaxesPage,{secureCall:call,initialYear:2026}));await new Promise(r=>setTimeout(r,10));});
  // Supersede a pending refresh, then navigate to another year before it resolves.
  await act(async()=>{root.render(React.createElement(TaxesPage,{secureCall:call,refreshVersion:1,initialYear:2026}));await new Promise(r=>setTimeout(r,10));});
  await act(async()=>{const input=document.querySelector('input[type=number]');Object.getOwnPropertyDescriptor(dom.window.HTMLInputElement.prototype,'value').set.call(input,'2025');input.dispatchEvent(new dom.window.Event('input',{bubbles:true}));});
  api.fail();await act(async()=>{document.querySelector('form').dispatchEvent(new dom.window.Event('submit',{bubbles:true,cancelable:true}));await new Promise(r=>setTimeout(r,10));});assert.match(document.body.textContent,/Mock conflict/);assert.ok(document.querySelector('[role=alert]'));await act(async()=>{[...document.querySelectorAll('button')].find(b=>b.textContent==='Retry').click();await new Promise(r=>setTimeout(r,10));});assert.match(document.body.textContent,/Start your 2025 tax workspace/);await act(async()=>{resolveOld(await api.call('tax_get_workspace',{year:2026}));await new Promise(r=>setTimeout(r,10));});assert.match(document.body.textContent,/Start your 2025 tax workspace/);assert.doesNotMatch(document.body.textContent,/Mock employment slip/);
 }finally{await act(async()=>root.unmount());dom.window.close();await unlink(output);delete globalThis.window;delete globalThis.document;delete globalThis.HTMLElement;delete globalThis.IS_REACT_ACT_ENVIRONMENT;}
});
