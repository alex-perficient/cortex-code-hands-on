# Company Background: Pinnacle Financial Services

## About Your Company

**Pinnacle Financial Services** is a mid-sized asset management firm serving high-net-worth individuals and institutional clients. You manage $2B in assets under management (AUM) across multiple investment strategies.

### Key Business Metrics
- **Assets Under Management:** $2B
- **Client Accounts:** 50,000
- **Revenue (Annual):** $25M (management fees + performance fees)
- **Employees:** 150 (25 in finance/operations)
- **Office Locations:** New York (HQ), Boston, San Francisco

---

## Current Technical Environment

### Data Infrastructure
| Component | Technology | Notes |
|-----------|------------|-------|
| Core Systems | Advent Geneva | Portfolio accounting, NAV calculation |
| CRM | Salesforce Financial Services Cloud | Client relationships, AUM tracking |
| GL System | NetSuite | General ledger, AP/AR |
| Data Warehouse | SQL Server | On-premises, 8 years old |
| Reporting | Excel + Power BI | Manual reconciliation, 40+ spreadsheets |
| Compliance | Manual processes | Quarterly regulatory reporting |

### Pain Points You've Identified
1. **Reporting delays:** Month-end close takes 10 business days
2. **Data silos:** Client data in CRM doesn't match portfolio system
3. **Manual reconciliation:** 3 FTEs spend 50% of time on data cleanup
4. **No self-service:** Executives wait days for ad-hoc reports
5. **Compliance risk:** Manual regulatory report preparation prone to errors

---

## POC Requirements from Leadership

### Must Have (P0)
- [ ] Unified view of revenue by client, product, and channel
- [ ] Real-time expense tracking with budget variance alerts
- [ ] Automated P&L generation (daily, monthly, quarterly)
- [ ] Natural language query interface for executives
- [ ] SOC 2 compliant data handling

### Should Have (P1)
- [ ] Client profitability analysis
- [ ] Predictive revenue forecasting
- [ ] Automated regulatory report generation
- [ ] Self-service dashboards for finance team

### Nice to Have (P2)
- [ ] AI-powered anomaly detection for transactions
- [ ] What-if scenario modeling
- [ ] Mobile access for executives

---

## Key Stakeholders You'll Present To

### Executive Sponsor
**Margaret Chen, CFO**
- 20 years in financial services
- Focused on reducing month-end close from 10 days to 3
- Wants "Amazon-like" experience for financial data
- *Your primary champion for this POC*

### Technical Lead
**David Park, VP of Operations**
- Owns data infrastructure and reporting
- Concerned about data accuracy and AI trustworthiness
- Wants to reduce manual reconciliation
- *Will scrutinize technical details and want to see the SQL*

### Compliance Stakeholder
**Sarah Martinez, Head of Compliance**
- Responsible for SEC/regulatory reporting
- Needs audit trail for all financial data
- Wants automated compliance dashboards
- *Cares about governance and auditability*

### Your Team
**4 analysts** in finance operations
- Excel power users, basic SQL knowledge
- Want self-service without IT dependency
- Skeptical of "AI" accuracy for financial data

---

## POC Timeline

| Milestone | Target | Notes |
|-----------|--------|-------|
| Build POC | This week | What you're doing in this lab |
| Present to Leadership | Next week | Show the art of the possible |
| Gather Feedback | Week 3 | Iterate based on stakeholder input |
| Decision | Week 4 | Go/no-go on expanding to production |

---

## Why Snowflake + Cortex Code?

You've been evaluating options and see potential in:
- **Cortex Analyst** - Natural language queries for executives
- **Snowflake Intelligence** - Chat interface for data exploration
- **Semantic Views** - Business-friendly layer over complex data
- **Governance built-in** - SOC 2 compliance, audit trails

Your job is to prove this can work for Pinnacle.

---

## Sample Data Domains for POC

### Revenue Data
- Management fees (basis points on AUM)
- Performance fees (carried interest)
- Advisory fees
- Transaction fees

### Expense Data
- Compensation & benefits
- Technology & data vendors
- Professional services
- Occupancy costs
- Marketing & business development

### Financial Reporting
- Income Statement (P&L)
- Balance Sheet
- Cash Flow Statement
- Regulatory filings (ADV, 13F)
