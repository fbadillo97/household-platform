// Standalone mock entry. Deliberately not referenced by index.html or the production build.
import React from 'react';import {createRoot} from 'react-dom/client';
import {BudgetPage} from '../../src/budget/BudgetPage.jsx';import {mockBudgetApi} from './mock.js';
import '../../src/style.css';import '../../src/design-system.css';
const api=mockBudgetApi();window.__budgetMock=api;
createRoot(document.getElementById('root')).render(<div className="shell"><header><div className="brand">H<span>Household</span></div><span className="tag">Preparation preview · mock household data</span></header><main><h1>Budget</h1><p className="intro">Shared household spending plan.</p><BudgetPage secureCall={api.call} onViewTransactions={payload=>{window.__budgetDrill=payload;}}/></main><footer>Mock data only · not connected to household accounts</footer></div>);
