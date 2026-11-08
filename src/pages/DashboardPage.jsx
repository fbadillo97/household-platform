import React from 'react';
import {NetWorthOverview} from './NetWorthOverview.jsx';
import {isTransfer} from '../finance.js';
export function DashboardPage({accounts,rows,snapshots,totals,currency,currencies,money,summaryMoney,outflowCategories,filters,onViewTransactions,onReviewTransfers,onViewAccounts}){
 const transfers=rows.filter(isTransfer),unlinked=transfers.filter(t=>!t.transfer_peer_id);
 return <>
 <NetWorthOverview accounts={accounts} money={money} onViewAccounts={onViewAccounts}/>
 <section className="panel"><div className="section-head"><div><h2>Transaction activity</h2><p>{accounts.length} accounts · {rows.length} transactions in this view</p></div><button onClick={onViewTransactions}>View transactions</button></div>{filters}<small>Money in/out and category totals exclude confirmed transfers and credit card payments. Unclassified entries still count. These figures are activity, not account balances. Overview uses the latest 500 loaded transactions.</small></section>
 <div className="cards money-cards"><article><span>Money in</span><strong>{summaryMoney(totals.inflow)}</strong></article><article><span>Money out</span><strong>{summaryMoney(totals.outflow)}</strong></article><article><span>Net activity</span><strong>{summaryMoney(totals.net)}</strong><small>{currency} · Excludes confirmed transfers</small></article></div>
 {transfers.length>0&&<section className="panel transfer-overview"><h2>Transfers and card payments</h2><p>{transfers.length} entries excluded from totals · {unlinked.length} without a linked counterpart</p><small>A linked payment has two entries. Entries in other accounts or months may be outside this view.</small>{unlinked.length>0&&<button className="secondary" onClick={onReviewTransfers}>Review unlinked transfers</button>}</section>}
 {outflowCategories.length>0&&currencies.length<=1&&<section className="panel"><h2>Largest outflow categories</h2><p>Top six categories · excludes confirmed transfers and card payments.</p><div className="category-list">{outflowCategories.map(([name,value])=><div key={name}><span>{name}</span><strong>{money(value)}</strong></div>)}</div></section>}
 {snapshots.length>0&&<section className="panel coverage"><h2>Import coverage</h2>{snapshots.map(s=><details key={s.id}><summary>{s.source==='monarch'?'Monarch snapshot':s.source} · {s.account_name} · {s.period_start} to {s.period_end}</summary><p>{s.committed_at?`${s.inserted_count} added · ${s.skipped_count} already present`:'Staged, not imported'} · {s.expected_count} source records</p><ul>{(s.coverage_notes||[]).map((note,i)=><li key={i}>{note}</li>)}</ul></details>)}</section>}
 {!rows.length&&<section className="panel"><h2>No activity in this period</h2><p>Choose another month or open Transactions to import records.</p><button onClick={onViewTransactions}>Open Transactions</button></section>}
 </>;
}
