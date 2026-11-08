import React,{useState} from 'react';
const behaviors=[['regular','Income / expense (normal)'],['transfer','Transfer between own accounts'],['credit_card_payment','Credit card payment']];
export function SettingsPage({categories,busy,create,secureCall,refresh,children}){
 const [saving,setSaving]=useState(''),[error,setError]=useState('');
 const sorted=[...categories].sort((a,b)=>a.name.localeCompare(b.name,'en',{sensitivity:'base',numeric:true})||a.id.localeCompare(b.id));
 async function change(category,value){
  setSaving(category.id);setError('');
  try{await secureCall('update_category_behavior',{id:category.id,accounting_behavior:value});await refresh();}
  catch(e){setError(e.message||'Unable to save accounting behavior.');}
  finally{setSaving('');}
 }
 return <>{children}<section className="panel categories-panel"><div className="section-head"><h2>Categories</h2><span className="category-count">{categories.length} total</span></div><p>Choose a category when editing a transaction. Accounting behavior is inherited automatically; no separate transaction type is needed. Changing a rule also updates unlinked transactions using that category.</p>{error&&<p role="alert" className="error">{error}</p>}<div className="categories-layout"><div className="category-table-scroll"><table className="category-table"><caption className="sr-only">Categories and default accounting behavior</caption><thead><tr><th scope="col">Category name</th><th scope="col">Accounting behavior</th></tr></thead><tbody>{sorted.length?sorted.map(c=><tr key={c.id}><td>{c.name}</td><td><select aria-label={'Accounting behavior for '+c.name} value={c.accounting_behavior||'regular'} disabled={busy||!!saving} onChange={e=>change(c,e.target.value)}>{behaviors.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select></td></tr>):<tr><td colSpan="2" className="category-empty">No categories yet. Add your first category.</td></tr>}</tbody></table></div><aside className="category-create"><h3>Add a category</h3><form onSubmit={e=>create(e,'category')}><label>Category name<input name="name" required maxLength="120" placeholder="e.g. Groceries"/></label><button disabled={busy||!!saving}>Add category</button></form><small>New categories start as normal income/expenses. Set their accounting behavior after creating them.</small></aside></div></section></>;
}
