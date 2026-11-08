import React,{useState,useEffect,useRef} from 'react';
import {summarizeRows,filterRows,EMPTY_COLUMN_FILTERS,isTransfer} from './finance.js';
import {PAGES,pageFromHash} from './navigation.js';
import {DashboardPage} from './pages/DashboardPage.jsx';
import {TransactionsPage} from './pages/TransactionsPage.jsx';
import {SettingsPage} from './pages/SettingsPage.jsx';
import {CsvImport} from './pages/CsvImport.jsx';
function ActivityFilters({accounts,accountFilter,setAccountFilter,month,setMonth,query,setQuery,hideAccount=false}){
 return <div className={'filters'+(setQuery&&!hideAccount?'':' filters-overview')}>{!hideAccount&&<label>Account<select value={accountFilter} onChange={e=>setAccountFilter(e.target.value)}><option value="">All accounts</option>{accounts.map(a=><option key={a.id} value={a.id}>{a.name}</option>)}</select></label>}<label>Month<input type="month" value={month} onChange={e=>setMonth(e.target.value)}/></label>{setQuery&&<label>Search<input type="search" placeholder="Merchant, category or tag" value={query} onChange={e=>setQuery(e.target.value)}/></label>}</div>;
}
export function Finance({secureCall,secureReceipt,settingsContent}){
 const [error,setError]=useState(''),[busy,setBusy]=useState(false),[notice,setNotice]=useState('');
 const [accounts,setAccounts]=useState([]),[categories,setCategories]=useState([]),[transactions,setTransactions]=useState([]),[snapshots,setSnapshots]=useState([]);
 const [transactionView,setTransactionView]=useState({columns:{...EMPTY_COLUMN_FILTERS},sort:'date',direction:'desc',offset:0});
 const [refreshVersion,setRefreshVersion]=useState(0);
 const initialPeriodSet=useRef(false);
 const [account,setAccount]=useState(''),[batch,setBatch]=useState(null),[selected,setSelected]=useState([]);
 const [page,setPage]=useState(()=>pageFromHash(window.location.hash));
 const [accountFilter,setAccountFilter]=useState(''),[month,setMonth]=useState(''),[query,setQuery]=useState('');
 async function refresh(){
  const [a,c,t,s]=await Promise.all(['list_accounts','list_categories','list_ledger_transactions','list_source_snapshots'].map(operation=>secureCall(operation,operation==='list_ledger_transactions'?{limit:500}:{})));
  setAccounts(a);setCategories(c);setTransactions(t.rows);setSnapshots(s);setRefreshVersion(v=>v+1);
  setAccount(old=>old||a[0]?.id||'');if(!initialPeriodSet.current){setMonth(old=>old||s[0]?.period_start?.slice(0,7)||'');initialPeriodSet.current=true;}
 }
 async function run(task){setBusy(true);setError('');try{await task();}catch(e){if(e.message!=='Stale session')setError(e.message);}finally{setBusy(false);}}
 useEffect(()=>{run(refresh);},[]);
 async function create(event,type){
  event.preventDefault();const form=event.currentTarget;const payload=Object.fromEntries(new FormData(form));
  await run(async()=>{await secureCall('create_'+type,payload);form.reset();await refresh();setNotice('Saved.');});
 }

 useEffect(()=>{
  const sync=()=>setPage(pageFromHash(window.location.hash));
  window.addEventListener('hashchange',sync);window.addEventListener('popstate',sync);
  return()=>{window.removeEventListener('hashchange',sync);window.removeEventListener('popstate',sync);};
 },[]);
 useEffect(()=>{document.title=PAGES[page].title+' · Household';},[page]);
 function navigate(next){if(window.location.hash!=='#'+next)window.history.pushState(null,'','#'+next);setPage(next);}
 const overviewRows=filterRows(transactions,{accountId:accountFilter,month},categories);

 const totals=summarizeRows(overviewRows);
 const currencies=[...new Set(overviewRows.map(t=>accounts.find(a=>a.id===t.account_id)?.currency).filter(Boolean))];
 const currency=currencies.length===1?currencies[0]:accounts.find(a=>a.id===accountFilter)?.currency||'CAD';
 const money=(minor,code=currency)=>new Intl.NumberFormat('en-CA',{style:'currency',currency:code}).format(minor/100);
 const summaryMoney=value=>currencies.length>1?'Choose one currency':money(value);
 const outflowCategories=Object.entries(overviewRows.filter(t=>!isTransfer(t)&&t.amount_minor<0).reduce((sum,t)=>{const name=categories.find(c=>c.id===t.category_id)?.name||'Unassigned';sum[name]=(sum[name]||0)-t.amount_minor;return sum;},{})).sort((a,b)=>b[1]-a[1]).slice(0,6);
 function changeAccount(value){setAccountFilter(value);setTransactionView(v=>({...v,offset:0}));}
 function changeMonth(value){setMonth(value);setTransactionView(v=>({...v,offset:0}));}
 function changeQuery(value){setQuery(value);setTransactionView(v=>({...v,offset:0}));}
 const filterProps={accounts,accountFilter,setAccountFilter:changeAccount,month,setMonth:changeMonth};
 return <>
 <nav className="app-nav" aria-label="Main navigation">{Object.entries(PAGES).map(([id,info])=><a key={id} href={'#'+id} aria-current={page===id?'page':undefined} onClick={e=>{e.preventDefault();navigate(id);}}>{info.title}</a>)}</nav>
 <div className="section-head page-heading"><div><p className="eyebrow">HOUSEHOLD FINANCE</p><h1>{PAGES[page].title}</h1><p className="intro">{PAGES[page].description}</p></div><button disabled={busy} onClick={()=>run(refresh)}>Refresh</button></div>
 {error&&<p className="error" role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
 {page==='dashboard'&&<DashboardPage accounts={accounts} rows={overviewRows} snapshots={snapshots} totals={totals} currency={currency} currencies={currencies} money={money} summaryMoney={summaryMoney} outflowCategories={outflowCategories} filters={<ActivityFilters {...filterProps}/>} onViewTransactions={()=>{setQuery('');navigate('transactions');}} onReviewTransfers={()=>{setQuery('');setTransactionView(v=>({...v,flow:'unlinked_transfer',trashOnly:false,offset:0}));navigate('transactions');}}/>}
 {page==='transactions'&&<TransactionsPage accounts={accounts} categories={categories} money={money} busy={busy} run={run} secureCall={secureCall} secureReceipt={secureReceipt} refresh={refresh} accountFilter={accountFilter} setAccountFilter={changeAccount} month={month} setMonth={changeMonth} query={query} setQuery={changeQuery} view={transactionView} setView={setTransactionView} refreshVersion={refreshVersion} filters={<ActivityFilters {...filterProps} query={query} setQuery={changeQuery} hideAccount/>}><CsvImport accounts={accounts} account={account} setAccount={setAccount} batch={batch} setBatch={setBatch} selected={selected} setSelected={setSelected} busy={busy} run={run} secureCall={secureCall} setNotice={setNotice} refresh={refresh} money={money}/></TransactionsPage>}
 {page==='settings'&&<SettingsPage accounts={accounts} categories={categories} busy={busy} create={create}>{settingsContent}</SettingsPage>}
 </>;
}
