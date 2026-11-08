import React from 'react';
export function SettingsPage({categories,busy,create,children}){
 return <>{children}<section className="panel"><h2>Categories</h2><p>{categories.map(c=>c.name).join(' · ')||'No categories yet'}</p><form onSubmit={e=>create(e,'category')}><label>Category name<input name="name" required maxLength="120"/></label><button disabled={busy}>Add category</button></form></section></>;
}
