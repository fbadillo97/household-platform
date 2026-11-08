import test from 'node:test';
import assert from 'node:assert/strict';
import {summarizeRows,filterRows,tagNames} from '../src/finance.js';
const rows=[{id:'1',account_id:'a',date:'2026-10-01',description:'Mock shop',category_id:'food',amount_minor:-125,source_data:{tags:[{id:'tag',name:'Renovation'}]}},{id:'2',account_id:'a',date:'2026-10-02',description:'Mock pay',category_id:'salary',amount_minor:2000},{id:'3',account_id:'b',date:'2026-09-01',description:'Mock transfer',category_id:'transfer',amount_minor:-300}];
test('cash movement uses exact cents and includes transfers without treating them as expenses',()=>{
 assert.deepEqual(summarizeRows(rows),{count:3,inflow:2000,outflow:425,net:1575});
 assert.throws(()=>summarizeRows([{amount_minor:1.2}]),/Invalid stored amount/);
});
test('account/month/category/tag filters keep unrelated rows out of the view',()=>{
 const categories=[{id:'food',name:'Groceries'}];
 assert.equal(filterRows(rows,{accountId:'a',month:'2026-10'},categories).length,2);
 assert.deepEqual(filterRows(rows,{query:'renovation'},categories).map(t=>t.id),['1']);
 assert.deepEqual(filterRows(rows,{query:'groceries'},categories).map(t=>t.id),['1']);
 assert.deepEqual(tagNames(rows[1]),[]);
});
