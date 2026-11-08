import test from 'node:test';
import assert from 'node:assert/strict';
import {parseBalance,balanceIsOld,balanceSubtotals,ACCOUNT_GROUPS} from '../src/accounts.js';
test('balances use exact cents, retain missing versus zero, and total currencies separately',()=>{
 assert.equal(parseBalance('123.45'),12345);assert.equal(parseBalance('-0.01'),-1);assert.equal(parseBalance('0'),0);
 for(const value of ['','1.001','1,000','NaN','1000000000001'])assert.throws(()=>parseBalance(value));
 assert.deepEqual(balanceSubtotals([{currency:'CAD'},{currency:'CAD',balance_snapshot:{amount_minor:0}},{currency:'USD',balance_snapshot:{amount_minor:12345}}]),{CAD:0,USD:12345});
 assert.equal(balanceIsOld('2026-10-01','2026-10-31'),false);assert.equal(balanceIsOld('2026-10-01','2026-11-01'),true);
 assert.equal(ACCOUNT_GROUPS.find(([id])=>id==='loans')[2].includes('mortgage'),true);
});
