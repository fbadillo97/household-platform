import React,{useState,useEffect,useRef} from 'react';
import {BULK_ACTIONS,bulkValue,bulkDescription,bulkPreview,defaultBulkValue} from '../bulk.js';
function BulkConfirmation({selection,action,value,categories,accounts,secureCall,onDone,onCancel,onBusyChange,onRefresh}){
 const dialog=useRef(null),alive=useRef(true),[submitting,setSubmitting]=useState(false),[error,setError]=useState('');
 useEffect(()=>{alive.current=true;const previous=document.activeElement;if(dialog.current.showModal)dialog.current.showModal();else dialog.current.setAttribute('open','');return()=>{alive.current=false;if(previous?.isConnected)previous.focus();};},[]);
 async function apply(){setSubmitting(true);setError('');onBusyChange(true);
  try{
   const result=await secureCall('bulk_update_transactions',{items:selection.map(t=>({id:t.id,revision:t.revision})),action,value});
   if(alive.current)await onDone(result);
  }catch(e){if(alive.current&&e.message!=='Stale session')setError(e.message);}
  finally{if(alive.current)setSubmitting(false);onBusyChange(false);}
 }
 return <dialog ref={dialog} className="bulk-dialog" aria-labelledby="bulk-confirm-title" onCancel={e=>{e.preventDefault();if(!submitting)onCancel();}}>
 <h2 id="bulk-confirm-title">Confirm bulk change</h2><p><strong>{bulkDescription(action,value,categories)}</strong></p><p>{selection.length} selected transaction{selection.length===1?'':'s'} from this page.</p>
 {action==='trash'?<p>They will leave your totals. Notes and receipts are kept, and you can restore them from Trash.</p>:action==='restore'?<p>These entries will return to the active ledger. Regular entries will count in totals again.</p>:<p>Only this field changes. Values already matching your choice will stay unchanged.</p>}
 <ul className="bulk-preview">{selection.map(t=><li key={t.id}><strong>{t.description}</strong><small>{t.date} · {accounts.find(a=>a.id===t.account_id)?.name}</small><span>{bulkPreview(t,action,value,categories)}</span></li>)}</ul>
 {error&&<p role="alert" className="error">{error}</p>}
 {error&&<button className="secondary" disabled={submitting} onClick={onRefresh}>Refresh and select again</button>}
 <div className="bulk-confirm-buttons"><button autoFocus className={action==='trash'?'danger':undefined} disabled={submitting} onClick={apply}>{submitting?'Applying…':action==='trash'?'Confirm move to Trash':action==='restore'?'Confirm restore':'Confirm bulk update'}</button><button className="secondary" disabled={submitting} onClick={onCancel}>Cancel bulk change</button></div>
 </dialog>;
}
export function BulkActions({selection,categories,accounts,trashOnly,disabled,secureCall,onDone,onBusyChange,onClear,onDeselectLinked,onRefresh}){
 const [action,setAction]=useState(trashOnly?'restore':'category'),[input,setInput]=useState(''),[pending,setPending]=useState(null),[error,setError]=useState('');
 const linked=selection.filter(t=>t.transfer_peer_id).length;
 const signature=JSON.stringify(selection.map(t=>[t.id,t.revision]));
 useEffect(()=>{setPending(null);setError('');},[signature]);
 function choose(value){setAction(value);setInput(defaultBulkValue(value));setPending(null);setError('');}
 function review(event){event.preventDefault();setError('');try{if(action==='trash'&&linked)throw Error('Deselect linked transfers or undo their links first.');setPending({action,value:bulkValue(action,input)});}catch(e){setError(e.message);}}
 return <section className="bulk-actions" aria-label="Bulk transaction actions"><div className="bulk-selection"><strong role="status">{selection.length} selected</strong><span>Current page only · up to 50</span><button className="text-button" disabled={disabled} onClick={onClear}>Clear selection</button></div>
 <form onSubmit={review}><fieldset disabled={disabled}>
 <label>Action<select aria-label="Bulk action" value={action} onChange={e=>choose(e.target.value)}>{Object.entries(BULK_ACTIONS).filter(([key])=>trashOnly?key==='restore':key!=='restore').map(([key,label])=><option key={key} value={key}>{label}</option>)}</select></label>
 {action==='category'&&<label>Category<select required aria-label="Bulk category" value={input} onChange={e=>setInput(e.target.value)}><option value="" disabled>Choose a category…</option><option value="__unassigned">Unassigned (clear category)</option>{categories.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>}
 {action==='review'&&<label>Review status<select aria-label="Bulk review status" value={input} onChange={e=>setInput(e.target.value)}><option value="reviewed">Reviewed</option><option value="unreviewed">Unreviewed</option></select></label>}
 {action==='attention'&&<label>Needs attention<select aria-label="Bulk attention status" value={input} onChange={e=>setInput(e.target.value)}><option value="true">On</option><option value="false">Off</option></select></label>}
 {['add_tag','remove_tag'].includes(action)&&<label>Tag<input required maxLength="60" aria-label="Bulk tag" value={input} onChange={e=>setInput(e.target.value)}/></label>}
 <button disabled={action==='trash'&&linked>0}>Review bulk change</button></fieldset></form>
 {action==='trash'&&linked>0&&<p role="status">{linked} linked transfer{linked===1?' must':'s must'} be unlinked before Trash. <button className="text-button" disabled={disabled} onClick={onDeselectLinked}>Deselect linked transfers</button></p>}
 {error&&<p role="alert" className="error">{error}</p>}
 {pending&&<BulkConfirmation selection={selection} categories={categories} accounts={accounts} action={pending.action} value={pending.value} secureCall={secureCall} onDone={onDone} onCancel={()=>setPending(null)} onBusyChange={onBusyChange} onRefresh={onRefresh}/>}
 </section>;
}
