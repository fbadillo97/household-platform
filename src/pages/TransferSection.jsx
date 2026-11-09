import {Icon} from '../visuals/Icon.jsx';
import React,{useState} from 'react';
import {flowLabel} from '../finance.js';
export function TransferSection({item,accounts,money,secureCall,action,onUpdated,busy,dirty}){
 const [matches,setMatches]=useState(null),[days,setDays]=useState('7'),[query,setQuery]=useState(''),[pending,setPending]=useState(null);
 const unavailable=busy||dirty||!!item.deleted_at;
 const name=id=>accounts.find(a=>a.id===id)?.name||'Unknown account';
 const value=t=>money(t.amount_minor,accounts.find(a=>a.id===t.account_id)?.currency||'CAD');
 async function find(){await action(async()=>{const result=await secureCall('list_transfer_candidates',{id:item.id,days:Number(days),query});setMatches(result);});}
 async function confirm(){await action(async()=>{
  const payload={id:item.id,revision:item.revision};
  if(pending.kind==='link')Object.assign(payload,{peer_id:pending.peer.id,peer_revision:pending.peer.revision,flow_type:pending.type});
  if(pending.kind==='unlink')Object.assign(payload,{peer_id:item.transfer_peer.id,peer_revision:item.transfer_peer.revision});
  const updated=await secureCall(pending.kind==='link'?'link_transfer':'unlink_transfer',payload);
  await onUpdated(updated);
 });}
 return <section className="transfer-section" aria-labelledby="transfer-title"><h3 id="transfer-title">Match other account</h3>
 {dirty&&<small>Save or discard your detail changes before changing transfer handling.</small>}
 {item.transfer_peer?<div className="linked-transfer"><strong>Linked to {name(item.transfer_peer.account_id)}</strong><p>{item.transfer_peer.date} · {item.transfer_peer.description} · {value(item.transfer_peer)}</p><button className="secondary" disabled={unavailable} onClick={()=>setPending({kind:'unlink'})}>Undo linked transfer</button></div>:<>
 {!item.deleted_at&&item.amount_minor!==0&&<details className="transfer-matches"><summary>Find matching transaction</summary><p>Look for the equal and opposite amount in another account.</p><fieldset disabled={unavailable}><label>Posting date window<select aria-label="Transfer date window" value={days} onChange={e=>{setDays(e.target.value);setMatches(null);}}><option value="7">Within 7 days</option><option value="31">Within 31 days</option></select></label><label>Match description or account<input aria-label="Search transfer matches" maxLength="500" value={query} onChange={e=>{setQuery(e.target.value);setMatches(null);}}/></label><button className="secondary" onClick={find}>Find matching entries</button></fieldset>
 {matches&&<><p role="status">{matches.total?`${matches.total} possible match${matches.total===1?'':'es'}. Nothing is linked automatically.`:'No matching entry found. The other side may be outside your imported period or in an account you have not imported.'}</p>{matches.total>50&&<small>Showing the nearest 50. Narrow the description or account search.</small>}<ul className="transfer-candidates">{matches.rows.map(t=><li key={t.id}><div><strong>{t.description}</strong><small>{t.date} · {name(t.account_id)} · {value(t)}</small>{t.flow_type&&t.flow_type!=='regular'&&<small>Already marked {flowLabel(t.flow_type).toLowerCase()}, without a link.</small>}</div><button className="secondary" disabled={unavailable} onClick={()=>setPending({kind:'link',peer:t,type:t.suggested_type||'transfer'})}>Review match</button></li>)}</ul></>}
 </details>}
 </>}
 {pending&&<div className="detail-confirm" role="alertdialog" aria-modal="false" aria-label="Confirm transfer change">
 {pending.kind==='link'?<><p>Link these two entries as a {flowLabel(pending.type).toLowerCase()}?</p><ul><li>{item.date} · {item.description} · {name(item.account_id)} · {value(item)}</li><li>{pending.peer.date} · {pending.peer.description} · {name(pending.peer.account_id)} · {value(pending.peer)}</li></ul><p>Original bank records remain unchanged.</p></>:<p>{'Undo this link? Each transaction will use its own category again.'}</p>}
 <button autoFocus disabled={unavailable} onClick={confirm}>{pending.kind==='link'?'Confirm link':'Confirm undo link'}</button><button className="secondary" disabled={busy} onClick={()=>setPending(null)}>Cancel transfer change</button>
 </div>}
 </section>;
}
