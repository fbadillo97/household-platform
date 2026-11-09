import React,{useEffect,useRef,useState} from 'react';
import {IdentityLabel} from '../visuals/VisualProvider.jsx';
import {Icon} from '../visuals/Icon.jsx';
import {Panel,SectionHeading,InlineNotice,EmptyState} from '../components/ui.jsx';
import {PayeeTagChoices,usePayeeTags} from './PayeeTagsSection.jsx';
import {PAYEE_KINDS,payeeAliases,payeeDirectory} from '../payees.js';

export function PayeeEditor({payee,secureCall,refresh,onClose,onSaved,tags}){
 const available=usePayeeTags(secureCall);const tagOptions=tags||available.tags;
 const dialog=useRef(null),alive=useRef(true);
 const initial={name:payee?.name||'',kind:payee?.kind||'other',aliases:(payee?.aliases||[]).join('\n'),archived:!!payee?.archived_at,tag_ids:(payee?.tags||[]).map(t=>t.id)};
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
 <div className="detail-heading"><h2 id="payee-title">{payee?'Edit payee':'Add payee'}</h2><button className="secondary" aria-label="Close payee" disabled={busy} onClick={close}><Icon name="close"/>Close</button></div>
 {error&&<InlineNotice>{error} {payee&&<button className="text-button" disabled={busy} onClick={()=>{if(dirty)setDiscard(true);else onClose();}}>Close payee editor</button>}</InlineNotice>}
 <form onSubmit={save}><fieldset disabled={busy} className="detail-fields"><label>Name<input required maxLength="120" value={draft.name} onChange={e=>field('name',e.target.value)} autoFocus/></label>
 <label>Kind<select value={draft.kind} onChange={e=>field('kind',e.target.value)}>{PAYEE_KINDS.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></label>
 {available.error&&!tags&&<InlineNotice>{available.error}</InlineNotice>}<PayeeTagChoices tags={tagOptions} selected={draft.tag_ids} onChange={ids=>field('tag_ids',ids)}/>
 <label>Imported description aliases<textarea rows="5" value={draft.aliases} onChange={e=>field('aliases',e.target.value)} aria-describedby="alias-help"/></label><small id="alias-help">One exact imported description per line. Case and extra spaces are ignored. Recognizes future imports; existing records are suggested for review. Each alias belongs to one payee.</small>
 {payee&&<label className="checkbox-label"><input type="checkbox" checked={draft.archived} onChange={e=>field('archived',e.target.checked)}/> Archived</label>}
 {draft.archived&&<small>Existing assignments stay intact. Archived payees are unavailable for new assignments and recognition.</small>}
 <button disabled={busy||!draft.name.trim()||!!payee&&!dirty}>{busy?'Saving…':payee?'Save payee':'Create payee'}</button></fieldset></form>
 {discard&&<div className="detail-confirm" role="alertdialog" aria-label="Discard payee changes"><p>Discard unsaved payee changes?</p><button autoFocus disabled={busy} onClick={onClose}>Discard payee changes</button><button className="secondary" onClick={()=>setDiscard(false)}>Keep editing payee</button></div>}
 </dialog>;
}
export function PayeesPage({payees,secureCall,refresh,onViewTransactions,onManageTags}){
 const [query,setQuery]=useState(''),[archived,setArchived]=useState(false),[editing,setEditing]=useState(null),[kind,setKind]=useState(''),[tag,setTag]=useState(''),[sort,setSort]=useState('name'),[direction,setDirection]=useState('asc'),[offset,setOffset]=useState(0),[selected,setSelected]=useState([]),[bulkTag,setBulkTag]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState('');
 const {tags,error:tagError,reload:reloadTags}=usePayeeTags(secureCall);
 const rows=payeeDirectory(payees,{query,kind,tag,archived,sort,direction}),page=rows.slice(offset,offset+50);
 useEffect(()=>{setOffset(0);setSelected([]);},[query,kind,tag,archived,sort,direction]);
 useEffect(()=>{if(offset>0&&offset>=rows.length){setOffset(Math.max(0,Math.floor(Math.max(0,rows.length-1)/50)*50));setSelected([]);}},[rows.length,offset]);
 async function bulk(action){setBusy(true);setError('');try{await secureCall('bulk_payee_tag',{tag_id:bulkTag,action,payees:selected.map(id=>({id,revision:payees.find(p=>p.id===id).revision}))});setSelected([]);await refresh();}catch(e){setError(e.message);}finally{setBusy(false);}}
 return <Panel><SectionHeading title="Payee directory" detail="Businesses, institutions and people you pay or receive money from." actions={<><button className="secondary" onClick={onManageTags}>Manage tags</button> <button onClick={()=>setEditing({})}><Icon name="plus"/>Add payee</button></>}/>
 {(error||tagError)&&<InlineNotice>{error||tagError}{tagError&&<button className="text-button" onClick={reloadTags}>Reload tags</button>}</InlineNotice>}
 <div className="payee-tools"><label>Find a payee<input type="search" value={query} onChange={e=>setQuery(e.target.value)} placeholder="Name, alias or payee tag"/></label>
 <label>Payee type<select value={kind} onChange={e=>setKind(e.target.value)}><option value="">All types</option>{PAYEE_KINDS.map(([v,l])=><option value={v} key={v}>{l}</option>)}</select></label>
 <label>Payee tag<select value={tag} onChange={e=>setTag(e.target.value)}><option value="">All tags</option><option value="__untagged">Untagged</option>{tags.map(t=><option key={t.id} value={t.id}>{t.name}{t.archived_at?' (archived)':''}</option>)}</select></label>
 <label>Sort payees<select value={sort} onChange={e=>setSort(e.target.value)}><option value="name">Name</option><option value="kind">Type</option><option value="count">Transaction count</option><option value="last">Last transaction</option></select></label>
 <label>Sort direction<select value={direction} onChange={e=>setDirection(e.target.value)}><option value="asc">Ascending</option><option value="desc">Descending</option></select></label>
 <label className="checkbox-label"><input type="checkbox" checked={archived} onChange={e=>setArchived(e.target.checked)}/> Show archived payees</label><button className="text-button" onClick={()=>{setQuery('');setKind('');setTag('');setArchived(false);}}>Clear filters</button></div>
 {!!selected.length&&<div className="payee-tools" role="group" aria-label="Bulk payee tags"><strong>{selected.length} selected</strong><label>Tag to apply<select value={bulkTag} onChange={e=>setBulkTag(e.target.value)} disabled={busy}><option value="">Choose tag</option>{tags.map(t=><option key={t.id} value={t.id}>{t.name}{t.archived_at?' (archived)':''}</option>)}</select></label><button disabled={busy||!bulkTag||archived||!!tags.find(t=>t.id===bulkTag)?.archived_at} onClick={()=>bulk('add')}>Add tag to selected</button><button className="secondary" disabled={busy||!bulkTag} onClick={()=>bulk('remove')}>Remove tag from selected</button></div>}
 <p className="section-description">{rows.length} {archived?'archived':'active'} payees</p>
 <div className="scroll"><table className="payee-table"><caption className="sr-only">Payees and recognition aliases</caption><thead><tr><th><input type="checkbox" aria-label="Select payees on this page" disabled={busy||!page.length} checked={!!page.length&&page.every(p=>selected.includes(p.id))} onChange={e=>setSelected(e.target.checked?page.map(p=>p.id):[])}/></th><th scope="col">Payee</th><th scope="col">Kind</th><th scope="col">Tags</th><th scope="col">Transactions</th><th scope="col">Last transaction</th><th scope="col">Actions</th></tr></thead><tbody>{page.map(p=><tr key={p.id}><td><input type="checkbox" aria-label={'Select payee '+p.name} disabled={busy} checked={selected.includes(p.id)} onChange={e=>setSelected(e.target.checked?[...selected,p.id]:selected.filter(id=>id!==p.id))}/></td><td><IdentityLabel type="payee" entity={p}/></td><td>{PAYEE_KINDS.find(([key])=>key===p.kind)?.[1]||'Other'}</td><td>{(p.tags||[]).map(t=><span className="payee-tag-chip" key={t.id}>{t.name}{t.archived_at?' (archived)':''}</span>)}</td><td>{p.transaction_count??0}</td><td>{p.last_transaction||'—'}</td><td><button className="secondary" aria-label={'Edit payee '+p.name} onClick={()=>setEditing(p)}><Icon name="edit"/>Edit</button> <button className="text-button" aria-label={'View transactions for '+p.name} onClick={()=>onViewTransactions(p.id)}>Transactions</button></td></tr>)}</tbody></table></div>
 <div className="payee-tools"><button className="secondary" disabled={offset===0} onClick={()=>{setOffset(Math.max(0,offset-50));setSelected([]);}}>Previous payees</button><span>{rows.length?offset+1:0}–{Math.min(offset+50,rows.length)} of {rows.length}</span><button className="secondary" disabled={offset+50>=rows.length} onClick={()=>{setOffset(offset+50);setSelected([]);}}>Next payees</button></div>
 {!rows.length&&<EmptyState illustration="search" title="No matching payees" detail="Change filters or add a payee."/>}
 {editing&&<PayeeEditor key={editing.id||'new'} tags={tags} payee={editing.id?editing:null} secureCall={secureCall} refresh={refresh} onClose={()=>setEditing(null)} onSaved={()=>setEditing(null)}/>}
 </Panel>;
}
