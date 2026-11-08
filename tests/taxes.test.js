import test from 'node:test';
import assert from 'node:assert/strict';
import {mockTaxWorkspace} from './taxes/mock.js';
import {taxOverview,receiptStatus,scopedWorkspace,carryForwardPreview,filterTaxRecords,pageOf,taxYear} from '../src/taxes/model.js';
test('tax progress excludes N/A and archives, separates filing and does not treat missing as zero completion',()=>{
 const data=mockTaxWorkspace();const summary=taxOverview(data,'2027-02-01');assert.equal(summary.applicable,3);assert.equal(summary.collected,1);assert.equal(summary.missing,2);assert.equal(summary.missingReceipts,1);assert.equal(summary.flaggedExpenses,2);assert.equal(data.returns[0].status,'collecting');assert.equal(summary.dates.some(d=>d.id==='ca-b'),false);
 data.items[0].archived_at='2026-01-01';data.expenses[0].transaction_deleted_at='2026-01-01';assert.equal(taxOverview(data,'2027-02-01').collected,0);assert.equal(taxOverview(data,'2027-02-01').missingReceipts,0);
 const empty=taxOverview({...data,items:[],expenses:[]},'2026-01-01');assert.equal(empty.applicable,0);assert.equal(empty.collected,0);
});
test('receipt readiness follows live linked documents and existing receipts, never pending uploads',()=>{
 const data=mockTaxWorkspace(),expense=data.expenses[0];assert.equal(receiptStatus(expense,data),'needed');data.links.push({target_kind:'expense',target_id:expense.id,document_id:'document-1'});assert.equal(receiptStatus(expense,data),'attached');data.documents[0].state='pending';assert.equal(receiptStatus(expense,data),'needed');expense.receipt_required=false;assert.equal(receiptStatus(expense,data),'not_required');assert.equal(receiptStatus(data.expenses[1],data),'attached');
});
test('person and jurisdiction filters intersect without duplicating shared documents',()=>{
 const data=mockTaxWorkspace(),scoped=scopedWorkspace(data,{person:'person-a',workstream:'canada'});assert.equal(scoped.returns.length,1);assert.equal(scoped.items.length,2);assert.equal(scoped.expenses.length,2);assert.equal(scoped.documents.length,1);assert.equal(scopedWorkspace(data,{person:'person-b',workstream:'us'}).returns.length,0);
});
test('annual reuse resets evidence, completion, deadlines and notes and excludes archived tasks',()=>{
 const data=mockTaxWorkspace();data.items[0].notes='Prior year private note';data.items[1].archived_at='2026-01-01';const copy=carryForwardPreview(data);assert.equal(copy.items.length,3);assert.ok(copy.items.every(i=>i.status==='missing'&&i.due_date===null&&i.notes===''));assert.ok(copy.returns.every(r=>r.status==='collecting'));assert.equal('documents' in copy,false);assert.equal('links' in copy,false);
});
test('collection drill-down includes in-progress tasks and search/pagination retain exact bounds',()=>{
 const data=mockTaxWorkspace();assert.equal(filterTaxRecords(data.items,{status:'to_collect'}).length,2);assert.equal(filterTaxRecords(data.expenses,{query:'MEDICAL'}).length,1);const rows=Array.from({length:101},(_,id)=>({id}));assert.equal(pageOf(rows,500).page,2);assert.equal(pageOf(rows,500).rows.length,1);assert.equal(pageOf([],7).page,0);assert.equal(taxYear('2026'),2026);for(const bad of ['26','2026.1','2026x',1800,2101])assert.throws(()=>taxYear(bad));
});
