import React,{useState,useEffect,lazy,Suspense} from 'react';
import {summarizeRows,filterRows,EMPTY_COLUMN_FILTERS,isTransfer} from './finance.js';
import {localToday} from './accounts.js';
import {transactionPeriodRange} from './transaction-periods.js';
import {formatMoney} from './money.js';
import {VisualProvider} from './visuals/VisualProvider.jsx';
import {Icon,PAGE_ICONS} from './visuals/Icon.jsx';
import {PAGES,pageFromHash} from './navigation.js';
import {DashboardPage} from './pages/DashboardPage.jsx';
import {TransactionsPage} from './pages/TransactionsPage.jsx';
import {AccountsPage} from './pages/AccountsPage.jsx';
import {SettingsPage} from './pages/SettingsPage.jsx';
import {PayeesPage} from './pages/PayeesPage.jsx';
import {CsvImport} from './pages/CsvImport.jsx';
import {TransactionDetail} from './pages/TransactionDetail.jsx';
const ReportsPage=lazy(()=>import('./reports/ReportsPage.jsx').then(m=>({default:m.ReportsPage})));
const TaxesPage=lazy(()=>import('./taxes/TaxesPage.jsx').then(m=>({default:m.TaxesPage})));
const BudgetPage=lazy(()=>import('./budget/BudgetPage.jsx').then(m=>({default:m.BudgetPage})));
const BudgetActivity=lazy(()=>import('./budget/BudgetActivity.jsx').then(m=>({default:m.BudgetActivity})));
function ActivityFilters({accounts,accountFilter,setAccountFilter,month,setMonth,query,setQuery,hideAccount=false,hideMonth=false}){
 return <div className={'filters'+(setQuery&&!hideAccount?'':' filters-overview')}>{!hideAccount&&<label>Account<select value={accountFilter} onChange={e=>setAccountFilter(e.target.value)}><option value="">All accounts</option>{accounts.map(a=><option key={a.id} value={a.id}>{a.name}</option>)}</select></label>}{!hideMonth&&<label>Month<input type="month" value={month} onChange={e=>setMonth(e.target.value)}/></label>}{setQuery&&<label>Search<input type="search" placeholder="Description, payee, category or tag" value={query} onChange={e=>setQuery(e.target.value)}/></label>}</div>;
}
function FinanceWorkspace({secureCall,secureReceipt,secureDocument,settingsContent,initialToday}){
 const today=initialToday||localToday();
 const [error,setError]=useState(''),[busy,setBusy]=useState(false),[notice,setNotice]=useState('');
 const [accounts,setAccounts]=useState([]),[categories,setCategories]=useState([]),[transactions,setTransactions]=useState([]),[snapshots,setSnapshots]=useState([]),[payees,setPayees]=useState([]);
 const [transactionView,setTransactionView]=useState(()=>{const range=transactionPeriodRange('month',today);return {datePreset:'month',columns:{...EMPTY_COLUMN_FILTERS,dateFrom:range.from,dateTo:range.to},sort:'date',direction:'desc',offset:0};});
 const [refreshVersion,setRefreshVersion]=useState(0);
 const [account,setAccount]=useState(''),[batch,setBatch]=useState(null),[selected,setSelected]=useState([]);
 const [page,setPage]=useState(()=>pageFromHash(window.location.hash));
 const [settingsSection,setSettingsSection]=useState(()=>window.location.hash==='#settings/automations'?'automations':'general');
 const [accountScope,setAccountScope]=useState(null);
 const [planningDetail,setPlanningDetail]=useState(null),[budgetActivity,setBudgetActivity]=useState(null);
 const [accountFilter,setAccountFilter]=useState(''),[month,setMonth]=useState(()=>today.slice(0,7)),[transactionMonth,setTransactionMonth]=useState(''),[query,setQuery]=useState('');
 async function refresh(){
  const [a,c,t,s,p]=await Promise.all(['list_accounts','list_categories','list_ledger_transactions','list_source_snapshots','list_payees'].map(operation=>secureCall(operation,operation==='list_ledger_transactions'?{limit:500}:{})));
  setAccounts(a);setCategories(c);setTransactions(t.rows);setSnapshots(s);setPayees(p);setRefreshVersion(v=>v+1);
  setAccount(old=>old||a[0]?.id||'');return a;
 }
 async function run(task){setBusy(true);setError('');try{await task();}catch(e){if(e.message!=='Stale session')setError(e.message);}finally{setBusy(false);}}
 useEffect(()=>{run(refresh);},[]);
 async function create(event,type){
  event.preventDefault();const form=event.currentTarget;const payload=Object.fromEntries(new FormData(form));
  await run(async()=>{await secureCall('create_'+type,payload);form.reset();await refresh();setNotice('Saved.');});
 }

 useEffect(()=>{
  const sync=()=>{setPage(pageFromHash(window.location.hash));setSettingsSection(window.location.hash==='#settings/automations'?'automations':'general');};
  window.addEventListener('hashchange',sync);window.addEventListener('popstate',sync);
  return()=>{window.removeEventListener('hashchange',sync);window.removeEventListener('popstate',sync);};
 },[]);
 useEffect(()=>{document.title=PAGES[page].title+' · Household';},[page]);
 function navigate(next){if(window.location.hash!=='#'+next)window.history.pushState(null,'','#'+next);setPage(pageFromHash('#'+next));setSettingsSection(next==='settings/automations'?'automations':'general');}
 const overviewRows=filterRows(transactions,{accountId:accountFilter,month},categories);

 const totals=summarizeRows(overviewRows);
 const currencies=[...new Set(overviewRows.map(t=>accounts.find(a=>a.id===t.account_id)?.currency).filter(Boolean))];
 const currency=currencies.length===1?currencies[0]:accounts.find(a=>a.id===accountFilter)?.currency||'CAD';
 const money=(minor,code=currency)=>formatMoney(minor,code);
 const summaryMoney=value=>currencies.length>1?'Choose one currency':money(value);
 const outflowCategories=Object.entries(overviewRows.filter(t=>!isTransfer(t)&&t.amount_minor<0).reduce((sum,t)=>{const name=categories.find(c=>c.id===t.category_id)?.name||'Unassigned';sum[name]=(sum[name]||0)-t.amount_minor;return sum;},{})).sort((a,b)=>b[1]-a[1]).slice(0,6);
 function changeAccount(value){setAccountFilter(value);setTransactionView(v=>({...v,offset:0}));}
 function changeMonth(value){setMonth(value);setTransactionMonth(value);setTransactionView(v=>({...v,datePreset:value?'specific_month':'all',columns:{...v.columns,dateFrom:'',dateTo:''},offset:0}));}
 function changeTransactionMonth(value){setTransactionMonth(value);setTransactionView(v=>({...v,datePreset:value?'specific_month':'all',columns:{...v.columns,dateFrom:'',dateTo:''},offset:0}));}
 function changeQuery(value){setQuery(value);setTransactionView(v=>({...v,offset:0}));}
 const filterProps={accounts,accountFilter,setAccountFilter:changeAccount,month,setMonth:changeMonth};
 return <div className="platform-layout">
 <aside className="platform-sidebar" aria-label="Household platform sections"><div className="sidebar-identity"><span className="sidebar-mark" aria-hidden="true">H</span><span><strong>Household</strong><small>Platform</small></span></div><div className="sidebar-section-label">FINANCE</div>
 <nav className="app-nav" aria-label="Main navigation">{Object.entries(PAGES).map(([id,info])=><a key={id} href={'#'+id} aria-current={page===id?'page':undefined} onClick={e=>{e.preventDefault();if(id==='accounts')setAccountScope(null);navigate(id);}}><Icon name={PAGE_ICONS[id]}/>{info.title}</a>)}</nav><div className="sidebar-footer">Household Platform <span>v0.4</span></div></aside><div className="platform-workspace">
 <div className="section-head page-heading"><div><p className="eyebrow">HOUSEHOLD FINANCE</p><h1>{PAGES[page].title}</h1><p className="intro">{PAGES[page].description}</p></div><button disabled={busy} onClick={()=>run(refresh)}><Icon name="refresh"/>Refresh</button></div>
 {error&&<p className="error" role="alert">{error}</p>}{notice&&<p role="status">{notice}</p>}
 {page==='dashboard'&&<DashboardPage accounts={accounts} rows={overviewRows} snapshots={snapshots} totals={totals} currency={currency} currencies={currencies} money={money} summaryMoney={summaryMoney} outflowCategories={outflowCategories} filters={<ActivityFilters {...filterProps}/>} onViewTransactions={()=>{setQuery('');changeTransactionMonth(month);navigate('transactions');}} secureCall={secureCall} onViewAccounts={scope=>{setAccountScope(scope);navigate('accounts');}} onViewCategory={name=>{setQuery('');setTransactionMonth(month);setTransactionView({columns:{...EMPTY_COLUMN_FILTERS,category:categories.find(c=>c.name===name)?.id||'__unassigned'},sort:'date',direction:'desc',offset:0,trashOnly:false,review:'',flow:''});navigate('transactions');}} onReviewTransfers={()=>{setQuery('');setTransactionMonth(month);setTransactionView(v=>({...v,datePreset:month?'specific_month':'all',columns:{...v.columns,dateFrom:'',dateTo:''},flow:'unlinked_transfer',trashOnly:false,offset:0}));navigate('transactions');}}/>}
 {page==='accounts'&&<AccountsPage scope={accountScope} onClearScope={()=>setAccountScope(null)} accounts={accounts} secureCall={secureCall} refresh={refresh} money={money} onViewTransactions={id=>{setAccountFilter(id);setMonth('');setTransactionMonth('');setQuery('');setTransactionView({columns:{...EMPTY_COLUMN_FILTERS},sort:'date',direction:'desc',offset:0,trashOnly:false,review:'',flow:''});navigate('transactions');}}/>}
 {page==='transactions'&&<TransactionsPage payees={payees} accounts={accounts} categories={categories} money={money} busy={busy} run={run} secureCall={secureCall} secureReceipt={secureReceipt} refresh={refresh} accountFilter={accountFilter} setAccountFilter={changeAccount} month={transactionMonth} setMonth={changeTransactionMonth} query={query} setQuery={changeQuery} view={transactionView} setView={setTransactionView} refreshVersion={refreshVersion} filters={<ActivityFilters {...filterProps} query={query} setQuery={changeQuery} hideAccount hideMonth/>}><CsvImport accounts={accounts} account={account} setAccount={setAccount} batch={batch} setBatch={setBatch} selected={selected} setSelected={setSelected} busy={busy} run={run} secureCall={secureCall} setNotice={setNotice} refresh={refresh} money={money}/></TransactionsPage>}
 {page==='payees'&&<PayeesPage payees={payees} secureCall={secureCall} refresh={refresh} onViewTransactions={id=>{setAccountFilter('');setMonth('');setTransactionMonth('');setQuery('');setTransactionView({columns:{...EMPTY_COLUMN_FILTERS,payee:id},sort:'date',direction:'desc',offset:0,trashOnly:false,review:'',flow:''});navigate('transactions');}}/>}
 <Suspense fallback={<p role="status">Loading household workspace…</p>}>
 {page==='reports'&&<ReportsPage secureCall={secureCall} onOpenTransaction={setPlanningDetail} onReviewRefunds={()=>navigate('budget')} refreshVersion={refreshVersion}/>}
 {page==='taxes'&&<TaxesPage secureCall={secureCall} documentStorage={secureDocument} refreshVersion={refreshVersion} onOpenTransaction={setPlanningDetail}/>}
 {page==='budget'&&<BudgetPage secureCall={secureCall} refreshVersion={refreshVersion} onViewTransactions={setBudgetActivity}/>}
 {budgetActivity&&<BudgetActivity scope={budgetActivity} secureCall={secureCall} refreshVersion={refreshVersion} onClose={()=>setBudgetActivity(null)} onOpenTransaction={setPlanningDetail}/>}
 </Suspense>
 {planningDetail&&<TransactionDetail key={planningDetail} id={planningDetail} accounts={accounts} categories={categories} payees={payees} money={money} secureCall={secureCall} secureReceipt={secureReceipt} refresh={refresh} onClose={()=>setPlanningDetail(null)}/>}
 {page==='settings'&&<SettingsPage section={settingsSection} onSectionChange={section=>navigate(section==='automations'?'settings/automations':'settings')} onViewTransactions={({source='',event=''})=>{setAccountFilter('');setMonth('');setTransactionMonth('');setQuery('');setTransactionView({columns:{...EMPTY_COLUMN_FILTERS,automationSource:source,automationEvent:event},sort:'date',direction:'desc',offset:0,trashOnly:false,review:'',flow:''});navigate('transactions');}} payees={payees} accounts={accounts} categories={categories} busy={busy} create={create} secureCall={secureCall} refresh={refresh}>{settingsContent}</SettingsPage>}
 </div></div>;
}

export function Finance(props){return <VisualProvider secureCall={props.secureCall}><FinanceWorkspace {...props}/></VisualProvider>;}
