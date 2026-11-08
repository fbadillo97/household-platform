export const ACCOUNT_TYPES={checking:'Checking',savings:'Savings',credit:'Credit card',loan:'Loan',mortgage:'Mortgage',investment:'Investment',asset:'Property or other asset'};
export const ACCOUNT_GROUPS=[['checking','Checking',['checking']],['savings','Savings',['savings']],['credit','Credit cards',['credit']],['loans','Loans',['loan','mortgage']],['investments','Investments',['investment']],['assets','Property & Other Assets',['asset','other']]];
export const isDebt=a=>['credit','loan','mortgage'].includes(a.kind);
export const balanceLabel=a=>isDebt(a)?'Amount owed':a.kind==='investment'?'Market Value':['asset','other'].includes(a.kind)?'Estimated Market Value':'Balance';
export function localToday(){const d=new Date();return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;}
export function balanceIsOld(asOf,today=localToday()){return (Date.parse(today+'T00:00:00Z')-Date.parse(asOf+'T00:00:00Z'))/86400000>30;}
export function parseBalance(value){
 const text=value.trim();if(!/^[+-]?\d+(\.\d{1,2})?$/.test(text))throw Error('Enter a balance with at most two decimal places.');
 const [whole,fraction='']=text.replace(/^[+-]/,'').split('.');const minor=Number(whole)*100+Number(fraction.padEnd(2,'0'));
 if(!Number.isSafeInteger(minor)||minor>100000000000000)throw Error('Balance is outside the supported range.');return text.startsWith('-')?-minor:minor;
}
export function balanceInput(minor){return (minor/100).toFixed(2);}
export function balanceSubtotals(accounts){
 const totals={};for(const a of accounts){const s=a.balance_snapshot;if(!s)continue;const amount=(totals[a.currency]??0)+s.amount_minor;totals[a.currency]=totals[a.currency]===null||!Number.isSafeInteger(amount)?null:amount;}return totals;
}
