export const WORKSTREAMS={canada:'Canada',us:'US',fbar:'FBAR'};
export const ITEM_STATUS={missing:'Missing',in_progress:'In progress',collected:'Collected',reviewed:'Reviewed',not_applicable:'Not applicable'};
export const FILING_STATUS={collecting:'Collecting',ready:'Ready to file',filed:'Filed'};
export const RECEIPT_STATUS={needed:'Receipt needed',attached:'Attached',not_required:'Not required'};
export const EMPTY_TAX_WORKSPACE={people:[],returns:[],items:[],expenses:[],documents:[],links:[]};
export const TAX_PAGE_SIZE=50;
export function taxYear(value){
 const text=String(value);if(!/^\d{4}$/.test(text)||Number(text)<1900||Number(text)>2100)throw Error('Choose a tax year between 1900 and 2100.');return Number(text);
}
export function returnLabel(record,people){return `${people.find(p=>p.id===record?.person_id)?.name||'Unknown person'} · ${WORKSTREAMS[record?.workstream]||'Unknown workstream'}`;}
export function scopedWorkspace(data,{person='',workstream=''}={}){
 const returns=data.returns.filter(r=>(!person||r.person_id===person)&&(!workstream||r.workstream===workstream));
 const ids=new Set(returns.map(r=>r.id));return {...data,returns,items:data.items.filter(i=>ids.has(i.return_id)),expenses:data.expenses.filter(e=>ids.has(e.return_id))};
}
export function linkedDocuments(data,kind,id){
 const ids=new Set(data.links.filter(l=>l.target_kind===kind&&l.target_id===id).map(l=>l.document_id));
 return data.documents.filter(d=>ids.has(d.id)&&d.state!=='removed');
}
export function receiptStatus(expense,data){
 if(expense.receipt_required===false)return 'not_required';
 return (expense.receipt_count||0)>0||linkedDocuments(data,'expense',expense.id).some(d=>d.state==='ready')?'attached':'needed';
}
export function taxOverview(data,today){
 const items=data.items.filter(i=>!i.archived_at),applicable=items.filter(i=>i.status!=='not_applicable');
 const collected=applicable.filter(i=>['collected','reviewed'].includes(i.status)).length;
 const expenses=data.expenses.filter(e=>!e.archived_at&&!e.transaction_deleted_at);
 const dates=[...data.returns.filter(r=>r.status!=='filed').map(r=>({id:r.id,kind:'return',title:returnLabel(r,data.people),due_date:r.due_date})),...applicable.filter(i=>i.status!=='reviewed').map(i=>({id:i.id,kind:'item',title:i.title,due_date:i.due_date}))].filter(r=>r.due_date).sort((a,b)=>a.due_date.localeCompare(b.due_date)||a.id.localeCompare(b.id));
 return {applicable:applicable.length,collected,missing:applicable.filter(i=>['missing','in_progress'].includes(i.status)).length,needsReview:applicable.filter(i=>i.status==='collected').length+expenses.filter(e=>!e.reviewed).length,missingReceipts:expenses.filter(e=>receiptStatus(e,data)==='needed').length,flaggedExpenses:expenses.length,dates:dates.map(d=>({...d,overdue:d.due_date<today}))};
}
export function filterTaxRecords(rows,{query='',status='',archived=false}={},statusFor=r=>r.status){
 const term=query.trim().toLocaleLowerCase();return rows.filter(r=>Boolean(r.archived_at)===archived&&(!status||(status==='to_collect'?['missing','in_progress'].includes(statusFor(r)):statusFor(r)===status))&&(!term||[r.title,r.description,r.purpose,r.notes,r.account_name,r.tags_text].filter(Boolean).join(' ').toLocaleLowerCase().includes(term)));
}
export function pageOf(rows,page=0){const last=Math.max(0,Math.ceil(rows.length/TAX_PAGE_SIZE)-1),index=Math.max(0,Math.min(page,last));return {rows:rows.slice(index*TAX_PAGE_SIZE,(index+1)*TAX_PAGE_SIZE),page:index,pages:last+1,total:rows.length};}
export function carryForwardPreview(data){
 // Only reusable checklist structure is copied. A document or prior status never proves collection for another year.
 return {returns:data.returns.map(r=>({person_id:r.person_id,workstream:r.workstream,status:'collecting',due_date:null,notes:''})),items:data.items.filter(i=>!i.archived_at).map(i=>({source_return_id:i.return_id,title:i.title,status:'missing',due_date:null,notes:''}))};
}
