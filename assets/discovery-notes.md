# Requirements Gathering Meeting Notes

**Date:** January 10, 2026  
**Attendees:** Margaret Chen (CFO), David Park (VP Ops), Sarah Martinez (Compliance)  
**Facilitator:** You (BI Analyst)

---

## Meeting Purpose

You scheduled this meeting to gather requirements for the financial analytics POC. Leadership has heard about Snowflake's AI capabilities and wants to see what's possible.

---

## Current State Discussion

**Q: Walk me through your month-end close process.**

> David: "It starts with pulling data from Geneva for portfolio values, then matching against NetSuite for fees billed. We export everything to Excel where the team manually reconciles. Any discrepancies go back and forth via email. The final P&L gets assembled in Power BI, but honestly most executives just ask us to email them a PDF."

**Q: How long does a typical ad-hoc request take?**

> Margaret: "If I ask 'What was our revenue from institutional clients last quarter?', it takes 2-3 days. My team has to query multiple systems, validate the data, format it nicely. I should be able to ask that question and get an answer in seconds."

**Q: What's your biggest concern about new technology?**

> David: "Data accuracy. Financial data has to be perfect. If we show the wrong number to a client or regulator, that's a serious problem. Any AI or automation needs to be explainable and auditable."

---

## Technical Deep Dive

**Q: Can you describe our data architecture?**

> David: "Geneva is our source of truth for positions and NAV. NetSuite handles accounting. Salesforce has client data. The problem is nothing talks to each other automatically. We built some SSIS packages years ago but they break constantly."

**Q: What's our compliance reporting cadence?**

> Sarah: "Quarterly for most things - ADV amendments, 13F filings, performance reporting to clients. But preparing each report is a fire drill. We start pulling data 3 weeks before the deadline and it's all hands on deck."

**Q: Any concerns about moving to the cloud?**

> David: "Our team knows SQL well, but Python or modern data tools - not really. Whatever you build needs to be maintainable by our current staff."

---

## Use Case Prioritization

You asked stakeholders to rank priorities (1 = highest):

| Use Case | Margaret | David | Sarah | Avg |
|----------|----------|-------|-------|-----|
| Executive self-service queries | 1 | 3 | 4 | 2.7 |
| Automated P&L reporting | 2 | 1 | 3 | 2.0 |
| Expense variance tracking | 3 | 2 | 5 | 3.3 |
| Compliance automation | 5 | 4 | 1 | 3.3 |
| Client profitability | 4 | 5 | 2 | 3.7 |

**Consensus: Start POC with P&L automation + natural language queries**

---

## Success Criteria for the POC

Margaret defined what she needs to see:

1. **Speed:** Answer "What was Q4 revenue by product?" in under 10 seconds
2. **Accuracy:** Numbers must tie to source systems (David will validate)
3. **Simplicity:** Non-technical users can ask questions without SQL
4. **Trust:** Show the SQL behind answers (David needs auditability)

---

## Technical Questions from David

1. "How does natural language querying actually work?"
   - *You explained Cortex Analyst and semantic models*

2. "Can we control what data different users can see?"
   - *Yes - row-level security, dynamic masking*

3. "What if the AI generates wrong SQL?"
   - *Show SQL before execution, approval workflows possible*

4. "How would we get data from Geneva and NetSuite into Snowflake?"
   - *Discussed connectors, Snowpipe, partner ETL tools - but for POC, you'll generate sample data*

---

## Concerns Raised

| Concern | Your Response | Status |
|---------|---------------|--------|
| "AI can't be trusted for financial data" | Cortex Analyst shows SQL, full audit trail | Need to demonstrate |
| "Our team doesn't know Snowflake" | SQL-based, semantic layer abstracts complexity | Need to show simplicity |
| "We can't connect to production systems for POC" | Will generate realistic sample data | Acceptable for POC |
| "What about our Power BI investment?" | Snowflake works with Power BI, this adds capabilities | Addressed |

---

## Action Items for You

- [x] Schedule this requirements meeting
- [ ] Build demo database with realistic sample data
- [ ] Create semantic view for Cortex Analyst
- [ ] Set up Snowflake Intelligence for executives
- [ ] Prepare presentation for leadership
- [ ] Document architecture for David's technical review

---

## Quotes to Address in Your POC

> "I want to ask my data questions like I'm texting my analyst." - Margaret

> "Show me the SQL. I need to trust but verify." - David

> "If this can cut our compliance prep time in half, I'm in." - Sarah

---

## Next Steps

Build a POC that demonstrates:
1. Natural language queries answering Margaret's questions in seconds
2. Full SQL visibility for David's auditability requirement
3. A foundation that could expand to compliance reporting for Sarah
