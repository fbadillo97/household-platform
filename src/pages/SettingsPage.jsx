import React from 'react';
export function SettingsPage({accounts,properties,categories,busy,create,children}){
 return <>{children}
 <section className="panel"><h2>Accounts, properties and categories</h2><div className="grid">
 <section><h2>Accounts</h2>{accounts.map(a=><p key={a.id}>{a.name}<small>{a.kind} · {a.currency}{a.source_metadata?.currency_assumed?' (assumed; verify currency)':''}</small></p>)}<form onSubmit={e=>create(e,'account')}><label>Name<input name="name" required maxLength="120"/></label><label>Type<select name="kind"><option value="checking">Chequing</option><option>savings</option><option>credit</option><option>mortgage</option><option>other</option></select></label><label>Currency<input name="currency" defaultValue="CAD" pattern="[A-Z]{3}" required/></label><button disabled={busy}>Add account</button></form></section>
 <section><h2>Properties</h2>{properties.map(p=><p key={p.id}>{p.name}<small>{p.kind}</small></p>)}<form onSubmit={e=>create(e,'property')}><label>Name<input name="name" required maxLength="120"/></label><label>Use<select name="kind"><option value="home">Home</option><option value="rental">Rental</option><option value="other">Other</option></select></label><button disabled={busy}>Add property</button></form><h3>Categories</h3><p>{categories.map(c=>c.name).join(' · ')||'No categories yet'}</p><form onSubmit={e=>create(e,'category')}><label>Category name<input name="name" required maxLength="120"/></label><button disabled={busy}>Add category</button></form></section></div></section>
</>;
}
