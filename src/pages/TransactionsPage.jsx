import React from 'react';
import {tagNames} from '../finance.js';
export function TransactionsPage({rows,accounts,properties,categories,money,busy,run,secureCall,refresh,filters,children}){
 const visible=rows;
 return <><section className="panel"><h2>Find transactions</h2>{filters}<p><strong>{rows.length}</strong> matching transactions. Search descriptions, categories or tags, then assign a property or category below.</p></section>
 <section className="panel"><h2>Transactions</h2><div className="scroll"><table><thead><tr><th>Date</th><th>Description / Account</th><th>Amount</th><th>Property</th><th>Category</th><th>Source details</th></tr></thead><tbody>{visible.map(t=>{
  const acct=accounts.find(a=>a.id===t.account_id);const tags=tagNames(t);const source=t.source_data;
  return <tr key={t.id}><td>{t.date}</td><td>{t.description}<small>{acct?.name}</small>{tags.length>0&&<div className="tags">{tags.map((tag,i)=><span key={i}>{tag}</span>)}</div>}{source?.hide_from_reports&&<small>Hidden in Monarch reports</small>}</td><td className={t.amount_minor<0?'outflow':'inflow'}>{money(t.amount_minor,acct?.currency||'CAD')}</td>
  {[['property_id',properties],['category_id',categories]].map(([key,items])=><td key={key}><select aria-label={key+' for '+t.description} disabled={busy} value={t[key]||''} onChange={e=>{const value=e.target.value||null;run(async()=>{await secureCall('assign_transaction',{id:t.id,revision:t.revision,property_id:t.property_id,category_id:t.category_id,[key]:value});await refresh();});}}><option value="">Unassigned</option>{items.map(i=><option key={i.id} value={i.id}>{i.name}</option>)}</select></td>)}
  <td>{t.source==='monarch'?<details><summary>Monarch</summary><small>Transaction {t.external_id}</small>{source?.cleansed_description&&<p>{source.cleansed_description}</p>}<p>{source?.notes_provided?source.notes||'No note':'Notes not supplied by connector'}</p>{source?.category_group&&<small>Source group: {source.category_group}</small>}{source?.is_recurring&&<small>Marked recurring in Monarch</small>}{source?.is_split&&<p>Split transaction; original detail retained for review.</p>}</details>:'CSV'}</td></tr>;
 })}</tbody></table>{!visible.length&&<p>No matching transactions. Add an account and import a file, or change the filters.</p>}</div><small>Showing matches within the latest 500 loaded transactions. Currency totals are never mixed.</small></section>
{children}</>;
}
