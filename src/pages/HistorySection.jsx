import React,{useState,lazy,Suspense} from 'react';
const BalanceHistory=lazy(()=>import('./BalanceHistory.jsx'));
export function HistorySection({title='Balance history',...props}){
 const [open,setOpen]=useState(false);
 return <details className="panel history-section" onToggle={e=>setOpen(e.currentTarget.open)}><summary>{title}</summary>{open&&<Suspense fallback={<p role="status">Loading history controls…</p>}><BalanceHistory {...props}/></Suspense>}</details>;
}
