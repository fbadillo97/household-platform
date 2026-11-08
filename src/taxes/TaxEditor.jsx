import React,{useEffect,useRef,useState} from 'react';
import {WORKSTREAMS,ITEM_STATUS,FILING_STATUS,returnLabel} from './model.js';
import {TaxDocuments} from './TaxDocuments.jsx';
const makeDraft=(kind,item,data)=>kind==='item'?{return_id:item?.return_id||data.returns[0]?.id||'',title:item?.title||'',status:item?.status||'missing',due_date:item?.due_date||'',notes:item?.notes||''}:kind==='expense'?{return_id:item?.return_id||data.returns[0]?.id||'',purpose:item?.purpose||'',notes:item?.notes||'',receipt_required:item?.receipt_required!==false,reviewed:!!item?.reviewed}:kind==='return'?{status:item.status,due_date:item.due_date||'',notes:item.notes||''}:{name:'',person_id:data.people[0]?.id||'',workstreams:['canada'],copy_from_year:''};
export function TaxEditor({kind,item,data,secureCall,documentStorage,onSaved,onClose,reload,onOpenTransaction}){
 const ref=useRef(null),alive=useRef(true),[draft,setDraft]=useState(()=>makeDraft(kind,item,data)),[busy,setBusy]=useState(false),[error,setError]=useState(''),[confirm,setConfirm]=useState(false);
 const initial=useRef(JSON.stringify(draft)),dirty=JSON.stringify(draft)!==initial.current;
 useEffect(()=>{alive.current=true;const previous=document.activeElement;if(ref.current.showModal)ref.current.showModal();else ref.current.setAttribute('open','');return()=>{alive.current=false;if(previous?.isConnected)previous.focus();};},[]);
 const field=(key,value)=>setDraft(d=>({...d,[key]:value}));
 function close(){if(busy)return;if(dirty)setConfirm(true);else onClose();}
 async function action(work){setBusy(true);setError('');try{await work();}catch(e){if(alive.current&&e.message!=='Stale session')setError(e.message);}finally{if(alive.current)setBusy(false);}}
 async function save(event){event.preventDefault();await action(async()=>{
  const payload={...draft,year:data.year,...(item?{id:item.id,revision:item.revision}:{})};if(payload.due_date==='')payload.due_date=null;if(payload.copy_from_year==='')delete payload.copy_from_year;else if(payload.copy_from_year)payload.copy_from_year=Number(payload.copy_from_year);
  await secureCall(kind==='setup'?'tax_create_workspace':'tax_save_'+kind,payload);if(alive.current){initial.current=JSON.stringify(draft);await onSaved();}
 });}
 const title=kind==='setup'?'Set up tax year':kind==='return'?'Filing details':kind==='expense'?'Expense for tax review':item?'Checklist item':'Add checklist item';
 return <dialog ref={ref} className="transaction-dialog" aria-labelledby="tax-editor-title" onCancel={e=>{e.preventDefault();close();}}><div className="tax-detail-heading"><h2 id="tax-editor-title">{title}</h2><button type="button" className="secondary" disabled={busy} onClick={close}>Close</button></div>
 {error&&<p className="error" role="alert">{error}</p>}
 {kind==='expense'&&<p>{item.description} · {item.date}{item.transaction_deleted_at?' · In transaction Trash':''}</p>}
 <form className="tax-detail-form" onSubmit={save}><fieldset disabled={busy||!!item?.archived_at}>
 {kind==='setup'?<>
 <label>Person<select value={draft.person_id} onChange={e=>field('person_id',e.target.value)}><option value="">Add a person</option>{data.people.map(p=><option key={p.id} value={p.id}>{p.name}</option>)}</select></label>
 {!draft.person_id&&<label>Name<input required maxLength={100} value={draft.name} onChange={e=>field('name',e.target.value)}/></label>}
 <div className="tax-actions">{Object.entries(WORKSTREAMS).map(([id,label])=><label key={id} className="tax-check"><input type="checkbox" checked={draft.workstreams.includes(id)} onChange={e=>field('workstreams',e.target.checked?[...draft.workstreams,id]:draft.workstreams.filter(w=>w!==id))}/>{label}</label>)}</div>
 <details><summary>Reuse a previous checklist</summary><label>Copy from tax year<input type="number" min="1900" max={data.year-1} value={draft.copy_from_year} onChange={e=>field('copy_from_year',e.target.value)}/></label><p className="tax-muted">Copies checklist titles for this person and the selected workstreams. Statuses reset; documents, dates and notes stay in the original year.</p></details>
 </>:<>
 {kind!=='return'&&<label>Person & workstream<select required value={draft.return_id} onChange={e=>field('return_id',e.target.value)}>{data.returns.map(r=><option key={r.id} value={r.id}>{returnLabel(r,data.people)}</option>)}</select></label>}
 {kind==='item'&&<label>Item<input required maxLength={200} value={draft.title} onChange={e=>field('title',e.target.value)}/></label>}
 {kind==='expense'?<><label>Tax purpose<input required maxLength={200} placeholder="For example: donation for review" value={draft.purpose} onChange={e=>field('purpose',e.target.value)}/></label><label className="tax-check"><input type="checkbox" checked={draft.receipt_required} onChange={e=>field('receipt_required',e.target.checked)}/>Receipt required</label><label className="tax-check"><input type="checkbox" checked={draft.reviewed} onChange={e=>field('reviewed',e.target.checked)}/>Reviewed for tax preparation</label></>:<><label>Status<select value={draft.status} onChange={e=>field('status',e.target.value)}>{Object.entries(kind==='return'?FILING_STATUS:ITEM_STATUS).map(([id,label])=><option key={id} value={id}>{label}</option>)}</select></label><label>Due date (optional)<input type="date" value={draft.due_date} onChange={e=>field('due_date',e.target.value)}/></label></>}
 <label>Notes<textarea maxLength={10000} value={draft.notes} onChange={e=>field('notes',e.target.value)}/></label>
 </>}
 <button disabled={busy||(kind==='setup'&&!draft.workstreams.length)}>{busy?'Saving…':kind==='setup'?'Create workspace':'Save changes'}</button>
 </fieldset></form>
 {item&&['item','expense'].includes(kind)&&<><TaxDocuments kind={kind} id={item.id} data={data} secureCall={secureCall} documentStorage={documentStorage} reload={reload} disabled={busy||dirty} readOnly={!!item.archived_at}/>
 {kind==='expense'&&onOpenTransaction&&<button className="text-button" disabled={busy||dirty} onClick={()=>onOpenTransaction(item.transaction_id)}>Open original transaction & receipts</button>}
 <button className="text-button" disabled={busy||dirty} onClick={()=>action(async()=>{await secureCall('tax_archive_'+kind,{id:item.id,revision:item.revision,archived:!item.archived_at});if(alive.current)await onSaved();})}>{item.archived_at?'Restore':'Archive'}</button></>}
 {confirm&&<div className="detail-confirm" role="alertdialog" aria-label="Discard tax changes"><p>Discard unsaved changes?</p><button onClick={onClose}>Discard changes</button><button className="secondary" onClick={()=>setConfirm(false)}>Keep editing</button></div>}
 </dialog>;
}
