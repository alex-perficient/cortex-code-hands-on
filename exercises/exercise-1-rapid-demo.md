# Exercise 1: Build the POC

## Objective

Build a compelling financial analytics POC featuring **Cortex Analyst** and **Snowflake Intelligence** that you can present to your leadership team.

**Time:** 60 minutes  
**Deliverables:** 
- Working demo database with realistic financial data
- Semantic view for Cortex Analyst
- Snowflake Intelligence chat experience ready for your presentation

---

## Before You Begin — Your User Number

You have been assigned a **user number** (1–50) corresponding to your login (e.g., `COCO_HOL_USER_7` → your number is **7**).

Throughout this exercise, replace `<N>` with your number whenever you see it:

| Object | Naming Convention | Example (User 7) |
|--------|-------------------|-------------------|
| Database | `PINNACLE_FINANCIAL_DEMO_<N>` | `PINNACLE_FINANCIAL_DEMO_7` |
| Cortex Agent | `PINNACLE_FINANCIAL_ANALYST_<N>` | `PINNACLE_FINANCIAL_ANALYST_7` |

This keeps 50 attendees from colliding in the same account.

> **Tip:** Your role (`COCO_HOL_RL`) and warehouse (`COCO_HOL_WH`) are already set as defaults — no need to run `USE ROLE` or `USE WAREHOUSE`.

---

## Background

You're a BI Analyst at Pinnacle Financial Services. After your requirements gathering meeting with leadership, you need to build a proof-of-concept that demonstrates:
1. Natural language queries for your CFO ("What was our Q4 revenue?")
2. Self-service analytics without SQL knowledge
3. Auditable, trustworthy AI-generated insights

**The approach:** Since you can't connect to production systems for the POC, you'll create a realistic demo environment based on what you know about your company's data.

Your CFO, Margaret Chen, said:
> "I want to ask my data questions like I'm texting my analyst."

---

## Task 1: Review Your Requirements (10 min)

### Step 1: Review the company background

```
Read the company background from assets/customer-brief.md and summarize:
1. Company profile (size, AUM, employees)
2. Current technical environment
3. Key pain points
4. Primary stakeholders and their concerns
```

### Step 2: Review requirements meeting notes

```
Read assets/discovery-notes.md and identify:
1. Specific quotes from stakeholders we should address in the POC
2. Success criteria Margaret defined
3. David's technical concerns about AI
4. The consensus on what to demo first
```

---

## Task 2: Generate POC Database (20 min)

**This is where Cortex Code shines - generating realistic demo data based on your company context.**

### Step 1: Design the data model

Ask Cortex Code to design a schema based on your company's needs:

```
Based on the Pinnacle Financial company background and requirements meeting 
notes, design a Snowflake database schema for our financial analytics POC. 
Proceed autonomously.

Consider:
- We're an asset management firm with $2B AUM
- Revenue comes from management fees, performance fees, advisory fees
- We have 50,000 client accounts across Individual, Institutional, and Family Office segments
- Expenses include compensation, technology, professional services, occupancy
- Leadership needs P&L reporting and budget variance tracking

Create dimension and fact tables appropriate for:
1. Revenue analytics by client, product, and time
2. Expense tracking with budget variance
3. Client profitability analysis

Show me the proposed schema.
```

### Step 2: Create the database and tables

```
Create the PINNACLE_FINANCIAL_DEMO_<N> database (replace <N> with my user 
number) with the schema you designed. Use the ANALYTICS schema for the 
business tables. Proceed autonomously - assume yes to any write or grant 
operations.

Execute the DDL statements to create:
1. All dimension tables (clients, products, expense categories, dates)
2. All fact tables (revenue, expenses)
3. Show me confirmation that each table was created
```

### Step 3: Generate realistic sample data

```
Generate realistic sample data for our Pinnacle Financial POC. Proceed 
autonomously without asking for confirmation.

For dimension tables:
- 10-15 clients with realistic names across Individual, Institutional, and Family Office types
- 6-8 investment products (Equity, Fixed Income, Alternative, Multi-Asset)
- 12-15 expense categories matching our current structure
- Use our office locations: New York, Boston, San Francisco

For fact tables:
- 400-600 revenue transactions from July 2025 - January 2026
- 250-350 expense transactions for the same period
- Revenue should total roughly $10-15M for the period (we do $25M/year)
- Include some budget variance (some categories over, some under)

The data should support these demo questions:
- "What was our total revenue last quarter?"
- "Which clients generated the most revenue?"
- "What expense categories are over budget?"
```

### Step 4: Validate the data

```
Run validation queries to confirm:
1. Row counts for all tables
2. Date range of transactions
3. Total revenue and expense amounts
4. Sample of client and product names

Show me a summary of what was created.
```

---

## Task 3: Create Semantic View for Cortex Analyst (15 min)

### Step 1: Understand semantic views

```
Explain what a Cortex Analyst semantic view is and why it's important 
for natural language queries. How is it different from a YAML semantic model?
Keep it brief - 3-4 sentences.
```

### Step 2: Generate the semantic view

```
Create a Cortex Analyst semantic view using SQL for the PINNACLE_FINANCIAL_DEMO_<N> 
database (replace <N> with my user number). Proceed autonomously. The semantic view should:

1. Include all dimension and fact tables we created
2. Define relationships between tables (foreign keys)
3. Add business-friendly descriptions and synonyms
4. Define key metrics: total_revenue, total_expenses, budget_variance
5. Use CREATE SEMANTIC VIEW SQL syntax

Execute the SQL.
```

### Step 3: Test Cortex Analyst queries

Test the semantic view with questions leadership will ask:

```
Using the semantic view we just created, test these questions:

1. "What was our total revenue last quarter?" (Margaret's top question)
2. "Which clients generated the most revenue?" 
3. "What expense categories are over budget?" (for David)
4. "Show me revenue by product type"

For each question, show me:
- The natural language question
- The SQL that Cortex Analyst generated
- The results
```

---

## Task 4: Configure Snowflake Intelligence (10 min)

### Step 1: Understand Snowflake Intelligence

```
What is Snowflake Intelligence and how does it differ from Cortex Analyst? 
How do they work together? Keep it to 3-4 sentences.
```

### Step 2: Create a Cortex Agent

```
Create a Cortex Agent for our Pinnacle Financial POC. Proceed autonomously 
and execute all SQL including grants. The agent should:

1. Be named "PINNACLE_FINANCIAL_ANALYST_<N>" (replace <N> with my user number)
2. Use the semantic view we created
3. Have instructions appropriate for financial services executives
4. Include sample questions based on our requirements meeting
5. Grant USAGE to appropriate roles so leadership can access it

Execute all SQL.
```

### Step 3: Enable the agent in Snowflake Intelligence

To make the agent visible in Snowflake Intelligence for your leadership presentation:

```
Make the PINNACLE_FINANCIAL_ANALYST_<N> agent available in Snowflake 
Intelligence. Proceed autonomously - assume yes to all grants.

1. Grant USAGE on the agent to PUBLIC (or a specific role)
2. Add the agent to the Snowflake Intelligence object
3. Verify it was added successfully

Execute all SQL.
```

### Step 4: Test the agent

```
Test the agent with executive-style questions that Margaret, David, and Sarah 
might ask:

1. "How's our revenue trending?"
2. "Compare our expense run rate to budget"
3. "Which advisor has the most profitable clients?"

These responses will be great for my presentation!
```

---

## Task 5: Prepare Your Presentation Script (5 min)

### Generate talking points

```
Based on my requirements meeting notes, create a 10-minute presentation 
script that:

1. Opens with Margaret's pain point (2-3 days for ad-hoc reports)
2. Shows natural language query answering her question in seconds
3. Addresses David's concern about showing SQL (auditability)
4. Ends with the value proposition for Pinnacle

Format as brief talking points with the exact queries to run.
Reference specific quotes from the requirements meeting.
```

---

## Validation Checklist

Before proceeding to Exercise 2, verify:

- [x] PINNACLE_FINANCIAL_DEMO_&lt;N&gt; database created with dimension and fact tables
- [x] Sample data loaded (fact tables have 300+ rows)
- [x] Data looks realistic (appropriate names, amounts, date ranges)
- [x] Semantic view created in the database
- [x] Cortex Analyst responds correctly to natural language queries
- [x] Generated SQL is correct and auditable
- [x] Cortex Agent created and responding
- [x] Agent enabled in Snowflake Intelligence (USAGE granted)
- [x] Presentation script addresses stakeholder concerns from requirements meeting

---

## Key Takeaways

1. **Context is everything** - Your company knowledge drives realistic demos
2. **Cortex Code generates data** - No need to manually create sample datasets
3. **Semantic views are the foundation** - They teach AI how to query your data correctly
4. **Test with real questions** - Use actual questions from your requirements meeting
5. **Show the SQL** - Builds trust with skeptical stakeholders like David

---

## Pro Tips

1. **Match your company's terminology** - Use the same words for segments, products, categories
2. **Include realistic imperfections** - Some budget variances, missing data points
3. **Semantic views are SQL objects** - No stage files to manage, easier to version control
4. **Test edge cases** - What happens with empty results or date boundaries?

---

## Next Steps

Proceed to [Exercise 2: Master Cortex Code Skills](exercise-2-skills.md) where you'll learn to leverage built-in skills and create custom ones for your team.
