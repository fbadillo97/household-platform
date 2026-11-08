import React,{useEffect,useRef,useState} from 'react';
import {Panel,SectionHeading,InlineNotice,EmptyState} from '../components/ui.jsx';
import {PAYEE_KINDS,payeeAliases} from '../payees.js';

export function PayeeEditor({payee,secureCall,refresh,onClose,onSaved}){
 const dialog=useRef(null),alive=useRef(true);
 const initial={name:payee?.name||'',kind:payee?.kind||'other',aliases:(payee?.aliases||[]).join('\n'),archived:!!payee?.archived_at};
 const [draft,setDraft]=useState(initial),[busy,setBusy]=useState(false),[error,setError]=useState(''),[discard,setDiscard]=useState(false);
 const dirty=JSON.stringify(draft)!==JSON.stringify(initial);
 useEffect(()=>{alive.current=true;const previous=document.activeElement;dialog.current.showModal?.();if(!dialog.current.open)dialog.current.setAttribute('open','');return()=>{alive.current=false;previous?.focus();};},[]);
 function close(){if(busy)return;if(dirty)setDiscard(true);else onClose();}
 function field(key,value){setDraft(d=>({...d,[key]:value}));}
 async function save(event){event.preventDefault();setError('');setBusy(true);try{
  const payload={...draft,name:draft.name.trim(),aliases:payeeAliases(draft.aliases)};
  if(payee)Object.assign(payload,{id:payee.id,revision:payee.revision});
  const saved=await secureCall(payee?'update_payee':'create_payee',payload);
  await refresh();if(alive.current)onSaved(saved.id);
 }catch(e){if(alive.current&&e.message!=='Stale session')setError(e.message);}finally{if(alive.current)setBusy(false);}}
 return <dialog ref={dialog} className="transaction-dialog payee-dialog" aria-labelledby="payee-title" onCancel={e=>{e.preventDefault();close();}}>
 <div className="detail-heading"><h2 id="payee-title">{payee?'Edit payee':'Add payee'}</h2><button className="secondary" aria-label="Close payee" disabled={busy} onClick={close}>Close</button></div>
 {error&&<InlineNotice>{error} {payee&&<button className="text-button" disabled={busy} onClick={()=>{if(dirty)setDiscard(true);else onClose();}}>Close payee editor</button>}</InlineNotice>}
 <form onSubmit={save}><fieldset disabled={busy} className="detail-fields"><label>Name<input required maxLength="120" value={draft.name} onChange={e=>field('name',e.target.value)} autoFocus/></label>
 <label>Kind<select value={draft.kind} onChange={e=>field('kind',e.target.value)}>{PAYEE_KINDS.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
 <label>Imported description aliases<textarea rows="5" value={draft.aliases} onChange={e=>field('aliases',e.target.value)} aria-describedby="alias-help"/></label><small id="alias-help">One exact imported description per line. Case and extra spaces are ignored. Recognizes future imports; existing records are suggested for review. Each alias belongs to one payee.</small>
 {payee&&<label className="checkbox-label"><input type="checkbox" checked={draft.archived} onChange={e=>field('archived',e.target.checked)}/> Archived</label>}
 {draft.archived&&<small>Existing assignments stay intact. Archived payees are unavailable for new assignments and recognition.</small>}
 <button disabled={busy||!draft.name.trim()||!!payee&&!dirty}>{busy?'Saving…':payee?'Save payee':'Create payee'}</button></fieldset></form>
 {discard&&<div className="detail-confirm" role="alertdialog" aria-label="Discard payee changes"><p>Discard unsaved payee changes?</p><button autoFocus disabled={busy} onClick={onClose}>Discard payee changes</button><button className="secondary" onClick={()=>setDiscard(false)}>Keep editing payee</button></div>}
 </dialog>;
}
export function PayeesPage({payees,secureCall,refresh,onViewTransactions}){
 const [query,setQuery]=useState(''),[archived,setArchived]=useState(false),[editing,setEditing]=useState(null);
 const q=query.trim().toLowerCase();
 const rows=payees.filter(p=>!!p.archived_at===archived&&[p.name,...p.aliases].join(' ').toLowerCase().includes(q));
 return <Panel><SectionHeading title="Payee directory" detail="Businesses, institutions and people you pay or receive money from." actions={<button onClick={()=>setEditing({})}>Add payee</button>}/>
 <div className="payee-tools"><label>Find a payee<input type="search" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Name or imported description"/></label><label className="checkbox-label"><input type="checkbox" checked={archived} onChange={e=>setArchived(e.target.checked)}/> Show archived payees</label></div>
 <p className="section-description">{rows.length} {archived?'archived':'active'} payees</p>
 <div className="scroll"><table className="payee-table"><caption className="sr-only">Payees and recognition aliases</caption><thead><tr><th scope="col">Payee</th><th scope="col">Kind</th><th scope="col">Recognition</th><th scope="col">Actions</th></tr></thead><tbody>{rows.map(p=><tr key={p.id}><td>{p.name}</td><td>{PAYEE_KINDS.find(([key])=>key===p.kind)?.[1]||'Other'}</td><td>{p.aliases.length?`${p.aliases.length} exact aliases`:'Manual assignment'}</td><td><button className="secondary" aria-label={'Edit payee '+p.name} onClick={()=>setEditing(p)}>Edit</button> <button className="text-button" aria-label={'View transactions for '+p.name} onClick={()=>onViewTransactions(p.id)}>Transactions</button></td></tr>)}</tbody></table></div>
 {!rows.length&&<EmptyState title={query?'No matching payees':archived?'No archived payees':'Add your first payee'} detail="Payees group who the money goes to or comes from. Categories still determine its purpose and accounting."/>}
 {editing&&<PayeeEditor key={editing.id||'new'} payee={editing.id?editing:null} secureCall={secureCall} refresh={refresh} onClose={()=>setEditing(null)} onSaved={()=>setEditing(null)}/>}
 </Panel>;
}
