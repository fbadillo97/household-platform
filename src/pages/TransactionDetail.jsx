import React,{useState,useEffect,useRef} from 'react';
import {TransferSection} from './TransferSection.jsx';
import {receiptMetadata} from '../receipts.js';
import {InlineNotice} from '../components/ui.jsx';
const draftFor=t=>({description:t.description,account_id:t.account_id,category_id:t.category_id||'',notes:t.notes||'',review_status:t.review_status||'unreviewed',needs_attention:!!t.needs_attention,tags_override:t.tags_override??null});
export function TransactionDetail({id,accounts,categories,money,secureCall,secureReceipt,refresh,onClose}){
 const dialog=useRef(null),alive=useRef(true),previewUrl=useRef(null);
 const [item,setItem]=useState(null),[draft,setDraft]=useState(null),[baseline,setBaseline]=useState(''),[busy,setBusy]=useState(false),[error,setError]=useState(''),[notice,setNotice]=useState(''),[tag,setTag]=useState(''),[confirm,setConfirm]=useState(null),[preview,setPreview]=useState(null);
 const dirty=draft&&JSON.stringify(draft)!==baseline;
 function releasePreview(){if(previewUrl.current)URL.revokeObjectURL(previewUrl.current);previewUrl.current=null;setPreview(null);}
 function accept(t,reset=true){setItem(t);if(reset){const d=draftFor(t);setDraft(d);setBaseline(JSON.stringify(d));}}
 useEffect(()=>{
  alive.current=true;const previous=document.activeElement;
  if(dialog.current.showModal)dialog.current.showModal();else dialog.current.setAttribute('open','');
  secureCall('get_transaction_detail',{id}).then(t=>{if(alive.current)accept(t);}).catch(e=>{if(alive.current&&e.message!=='Stale session')setError(e.message);});
  return()=>{alive.current=false;if(previewUrl.current)URL.revokeObjectURL(previewUrl.current);previous?.focus();};
 },[id]);
 async function action(work){setBusy(true);setError('');setNotice('');try{await work();}catch(e){if(alive.current&&e.message!=='Stale session')setError(e.message);}finally{if(alive.current)setBusy(false);}}
 async function reload(reset=false){const t=await secureCall('get_transaction_detail',{id});if(alive.current)accept(t,reset);return t;}
 function close(){if(busy)return;if(dirty)setConfirm({kind:'discard'});else onClose();}
 function field(name,value){setDraft(d=>({...d,[name]:value}));}
 async function changeCategory(value){
  const previous=JSON.parse(baseline||'{}');
  const otherFieldsDirty=Object.keys(draft||{}).some(key=>key!=='category_id'&&JSON.stringify(draft[key])!==JSON.stringify(previous[key]));
  field('category_id',value);
  // Auto-save a lone category change; other draft fields still require explicit Save.
  if(otherFieldsDirty||busy||item.deleted_at)return;
  await action(async()=>{
   await secureCall('update_ledger_transaction',{id,revision:item.revision,category_id:value||null});
   await reload(true);await refresh();
  });
 }

 async function save(event){event.preventDefault();await action(async()=>{
  await secureCall('update_ledger_transaction',{...draft,id,revision:item.revision,description_override:draft.description.trim()===item.original_description?null:draft.description.trim(),account_override_id:draft.account_id===item.original_account_id?null:draft.account_id,category_id:draft.category_id||null});
  await reload(true);await refresh();if(alive.current)setNotice('Changes saved.');
 });}
 async function trash(restore=false){await action(async()=>{await secureCall(restore?'restore_transaction':'trash_transaction',{id,revision:item.revision});await refresh();if(alive.current)onClose();});}
 async function upload(file){if(!file)return;await action(async()=>{
  const metadata=await receiptMetadata(file);if(!alive.current)return;const receipt=await secureCall('prepare_receipt',{transaction_id:id,...metadata});
  if(!alive.current)return;
  if(!receipt.already_exists){
   try{await secureReceipt('upload',receipt.object_path,file,metadata.mime_type);}catch(e){if(String(e.statusCode||e.status)!=='409')throw e;}
   await secureCall('finish_receipt_upload',{id:receipt.id,revision:receipt.revision});
  }
  await reload();await refresh();if(alive.current)setNotice(receipt.already_exists?'This receipt is already attached.':'Receipt attached.');
 });}
 async function remove(receipt){await action(async()=>{await secureReceipt('remove',receipt.object_path);await secureCall('finish_receipt_removal',{id:receipt.id,revision:receipt.revision});if(preview?.id===receipt.id)releasePreview();await reload();await refresh();if(alive.current)setConfirm(null);});}
 async function openReceipt(receipt){await action(async()=>{const blob=await secureReceipt('download',receipt.object_path);if(!alive.current)return;releasePreview();const url=URL.createObjectURL(new Blob([blob],{type:receipt.mime_type}));previewUrl.current=url;setPreview({...receipt,url});});}
 const acct=accounts.find(a=>a.id===(item?.original_account_id??item?.account_id));
 const tags=draft?.tags_override??item?.original_tags??[];
 function addTag(){const label=tag.trim();if(!label)return;if(label.length>60||tags.length>=20||tags.some(t=>t.toLowerCase()===label.toLowerCase())){setError('Use up to 20 unique tags, each up to 60 characters.');return;}field('tags_override',[...tags,label]);setTag('');}
 return <dialog ref={dialog} className="transaction-dialog" aria-labelledby="transaction-title" onCancel={e=>{e.preventDefault();close();}}>
 <div className="detail-heading"><h2 id="transaction-title">Transaction details</h2><button className="secondary" aria-label="Close transaction" disabled={busy} onClick={close}>Close</button></div>
 {error&&<InlineNotice>{error} <button className="text-button" disabled={busy} onClick={()=>dirty?setConfirm({kind:'reload'}):action(()=>reload(true))}>Reload details</button></InlineNotice>}{notice&&<InlineNotice kind="info">{notice}</InlineNotice>}
 {!item&&!error&&<p role="status">Loading transaction…</p>}
 {item&&draft&&<><div className="detail-summary"><strong>{money(item.amount_minor,acct?.currency||'CAD')}</strong><span>{item.date}</span></div>
 {item.deleted_at&&<p className="trash-notice">In Trash. Notes and receipts are retained. <button disabled={busy} onClick={()=>trash(true)}>Restore transaction</button></p>}
 <div className="ledger-editor"><form onSubmit={save}><fieldset disabled={busy||!!item.deleted_at} className="detail-fields">
 <label>Description<input required maxLength="500" value={draft.description} onChange={e=>field('description',e.target.value)}/></label>
 <button type="button" className="text-button" onClick={()=>field('description',item.original_description)}>Reset description</button>
 <label>Account<select value={draft.account_id} onChange={e=>field('account_id',e.target.value)}>{accounts.filter(a=>a.currency===acct?.currency).map(a=><option key={a.id} value={a.id}>{a.name}</option>)}</select></label>
 <button type="button" className="text-button" onClick={()=>field('account_id',item.original_account_id)}>Reset account</button>
 <label>Category<select value={draft.category_id} onChange={e=>changeCategory(e.target.value)}><option value="">Unassigned</option>{categories.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></label>
 <label>Notes<textarea rows="4" maxLength="10000" value={draft.notes} onChange={e=>field('notes',e.target.value)} placeholder="Receipt context, reimbursements, things to follow up…"/></label>
 <div className="review-controls"><label><input type="checkbox" checked={draft.review_status==='reviewed'} onChange={e=>field('review_status',e.target.checked?'reviewed':'unreviewed')}/> Reviewed</label><label><input type="checkbox" checked={draft.needs_attention} onChange={e=>field('needs_attention',e.target.checked)}/> Needs attention</label></div>
 <label>Tags</label><div className="tags">{tags.map(t=><span key={t}>{t} <button type="button" aria-label={'Remove tag '+t} onClick={()=>field('tags_override',tags.filter(x=>x!==t))}>×</button></span>)}</div>
 <div className="tag-entry"><input aria-label="New tag" maxLength="60" value={tag} onChange={e=>setTag(e.target.value)} onKeyDown={e=>{if(e.key==='Enter'){e.preventDefault();addTag();}}}/><button type="button" className="secondary" onClick={addTag}>Add tag</button></div>
 <button type="button" className="text-button" onClick={()=>field('tags_override',null)}>Reset tags to imported</button>
 {!item.deleted_at&&<button disabled={!dirty||busy}>Save changes</button>}
 </fieldset></form></div>
 {(item.transfer_peer||['transfer','credit_card_payment'].includes(categories.find(c=>c.id===draft.category_id)?.accounting_behavior||item.flow_type))&&<TransferSection key={item.id+':'+item.revision} item={item} accounts={accounts} money={money} secureCall={secureCall} action={action} busy={busy} dirty={dirty} onUpdated={async updated=>{if(alive.current)accept(updated,true);await refresh();}}/>}
 <section className="receipt-section"><h3>Receipts</h3><small>PDF or image, up to 10 MB</small>
 {!item.deleted_at&&<label className="receipt-upload">Attach receipt<input type="file" accept="application/pdf,image/jpeg,image/png,image/webp" disabled={busy} onChange={e=>{const file=e.target.files[0];e.target.value='';upload(file);}}/></label>}
 <ul className="receipt-list">{(item.receipts||[]).map(r=><li key={r.id}><div><strong>{r.filename}</strong><small>{Math.ceil(r.byte_size/1024)} KB{r.state==='pending'?' · Upload incomplete — retry the same file or remove':''}</small></div><div>{r.state==='ready'&&<button className="secondary" disabled={busy} onClick={()=>openReceipt(r)}>View</button>}{!item.deleted_at&&<button className="text-button" disabled={busy} onClick={()=>setConfirm({kind:'receipt',receipt:r})}>Remove</button>}</div></li>)}</ul>
 {!item.receipts?.length&&<p>No receipts attached.</p>}
 {preview&&<div className="receipt-preview"><div><strong>{preview.filename}</strong> <a href={preview.url} download={preview.filename}>Download receipt</a> <button className="text-button" onClick={releasePreview}>Close preview</button></div>{preview.mime_type==='application/pdf'?<iframe title="Receipt PDF preview" src={preview.url} sandbox="allow-scripts allow-downloads"/>:<img src={preview.url} alt={'Receipt: '+preview.filename}/>}</div>}
 </section>
 <details className="original-record"><summary>Original imported record</summary><dl><dt>Description</dt><dd>{item.original_description}</dd><dt>Account</dt><dd>{acct?.name}</dd><dt>Date</dt><dd>{item.date}</dd><dt>Amount</dt><dd>{money(item.amount_minor,acct?.currency||'CAD')}</dd><dt>Tags</dt><dd>{(item.original_tags||[]).join(', ')||'None'}</dd>{item.source_data?.notes&&<><dt>Imported notes</dt><dd>{item.source_data.notes}</dd></>}<dt>Source</dt><dd>{item.source||'CSV'}{item.external_id?' · '+item.external_id:''}</dd></dl></details>
 
 {!item.deleted_at&&<button className="danger" disabled={busy} onClick={()=>setConfirm({kind:'trash'})}>Move to Trash</button>}
 </>}
 {confirm&&<div className="detail-confirm" role="alertdialog" aria-modal="false" aria-label="Confirm action"><p>{confirm.kind==='discard'?'Discard unsaved changes?':confirm.kind==='reload'?'Reload the latest details and discard unsaved changes?':confirm.kind==='trash'?'Move this transaction to Trash? It will leave your totals. You can restore it later. Unsaved changes will be discarded.':'Remove this receipt file? This cannot be undone.'}</p><button disabled={busy} autoFocus onClick={()=>confirm.kind==='discard'?onClose():confirm.kind==='reload'?action(async()=>{await reload(true);if(alive.current)setConfirm(null);}):confirm.kind==='trash'?trash():remove(confirm.receipt)}>{confirm.kind==='discard'?'Discard changes':confirm.kind==='reload'?'Reload and discard changes':confirm.kind==='trash'?'Confirm move to Trash':'Confirm remove receipt'}</button><button className="secondary" disabled={busy} onClick={()=>setConfirm(null)}>Keep editing</button></div>}
 </dialog>;
}
