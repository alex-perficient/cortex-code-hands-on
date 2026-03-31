/** FUNCIONAL
create or replace table PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_DATE as
SELECT 
    ROW_NUMBER() OVER (ORDER BY seq_date) AS DATE_KEY,
    seq_date AS CALENDAR_DATE,
    DAYOFWEEK(seq_date) AS DAY_OF_WEEK,
    DAYNAME(seq_date) AS DAY_NAME,
    DAY(seq_date) AS DAY_OF_MONTH,
    DAYOFYEAR(seq_date) AS DAY_OF_YEAR,
    WEEKOFYEAR(seq_date) AS WEEK_OF_YEAR,
    MONTH(seq_date) AS MONTH_NUMBER,
    MONTHNAME(seq_date) AS MONTH_NAME,
    QUARTER(seq_date) AS QUARTER_NUMBER,
    'Q' || QUARTER(seq_date) AS QUARTER_NAME,
    YEAR(seq_date) AS YEAR_NUMBER,
    QUARTER(seq_date) AS FISCAL_QUARTER,
    YEAR(seq_date) AS FISCAL_YEAR,
    seq_date = LAST_DAY(seq_date) AS IS_MONTH_END,
    seq_date = LAST_DAY(seq_date) AND MONTH(seq_date) IN (3,6,9,12) AS IS_QUARTER_END,
    seq_date = LAST_DAY(seq_date) AND MONTH(seq_date) = 12 AS IS_YEAR_END,
    DAYOFWEEK(seq_date) NOT IN (0, 6) AS IS_BUSINESS_DAY
FROM (
    -- Corrección aplicada aquí:
    SELECT DATEADD(day, SEQ4(), '2025-07-01'::DATE) AS seq_date
    FROM TABLE(GENERATOR(ROWCOUNT => 215))
)
WHERE seq_date <= '2026-01-31';


SELECT 'DIM_DATE' AS TBL, COUNT(*) AS ROW_COUNT FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_DATE
UNION ALL SELECT 'DIM_CLIENT', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_CLIENT
UNION ALL SELECT 'DIM_PRODUCT', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_PRODUCT
UNION ALL SELECT 'DIM_EXPENSE_CATEGORY', COUNT(*) FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_EXPENSE_CATEGORY;


SELECT 'FACT_REVENUE' AS TBL, COUNT(*) AS ROW_COUNT, ROUND(SUM(REVENUE_AMOUNT),2) AS TOTAL
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_REVENUE
UNION ALL
SELECT 'FACT_EXPENSE', COUNT(*), ROUND(SUM(EXPENSE_AMOUNT),2)
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.FACT_EXPENSE;



-- Restaurar la tabla a como estaba hace 1 hora (ajustar el tiempo)
//CREATE OR REPLACE TABLE PINNACLE_FINANCIAL_DEMO_127.ANALYTICS.DIM_COST_CENTER
 // CLONE PINNACLE_FINANCIAL_DEMO_127.ANALYTICS.DIM_COST_CENTER
 // AT(OFFSET => -3600);  -- 3600 segundos = 1 hora

CREATE OR REPLACE AGENT PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.PINNACLE_FINANCIAL_ANALYST_33
  COMMENT = 'Pinnacle Financial Services AI Analyst 33 - Financial analytics agent for executives and finance team'
  PROFILE = '{"display_name": "PINNACLE_FINANCIAL_ANALYST_33", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    budget:
      seconds: 60
      tokens: 16000

  instructions:
    system: >
      You are PINNACLE_FINANCIAL_ANALYST_33, an AI assistant for Pinnacle Financial Services,
      a $2B AUM asset management firm. You help executives and the finance team answer
      questions about revenue, expenses, client profitability, and financial performance.
      You have access to financial data from July 2025 through January 2026.
    response: >
      Always present financial figures formatted with dollar signs and commas (e.g., $1,234,567).
      Round to 2 decimal places. Be concise and professional. When showing results, highlight
      key insights. If asked about data outside the July 2025 - January 2026 range, let the
      user know the POC data covers that period only.
    orchestration: >
      Use the Financial_Analytics tool for all questions about revenue, expenses, clients,
      products, budgets, and financial performance.
    sample_questions:
      - question: "What was our total revenue last quarter?"
        answer: "I'll query our financial database to get the Q4 2025 revenue totals for you."
      - question: "Which clients generated the most revenue?"
        answer: "Let me pull the top clients ranked by total revenue across all fee types."
      - question: "What are our expenses by category?"
        answer: "I'll break down total expenses by group."
      - question: "Show me revenue by product type"
        answer: "I'll analyze revenue across Management Fees, Performance Fees, and Advisory Fees."
      - question: "What is our net income?"
        answer: "I'll calculate total revenue minus total expenses."
      - question: "How does revenue compare across our office locations?"
        answer: "Let me break down client revenue by New York, Boston, and San Francisco."

  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: Financial_Analytics_33
        description: >
          Queries Pinnacle Financial Services structured financial data including revenue
          transactions, expense records, client information, and investment products.
          Use this tool for any question about revenue, fees, expenses, costs, clients,
          products, AUM, profitability, or financial performance.
          Data covers July 2025 through January 2026.
    - tool_spec:
        type: data_to_chart
        name: data_to_chart
        description: "Generates charts and visualizations from query results."

  tool_resources:
    Financial_Analytics:
      semantic_view: PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.PINNACLE_FINANCIAL_SV
  $$;






  CREATE OR REPLACE AGENT PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.PINNACLE_FINANCIAL_ANALYST_33 COMMENT = 'Pinnacle Financial Services AI Analyst 33' PROFILE = '{"display_name": "PINNACLE_FINANCIAL_ANALYST_33", "color": "blue"}' FROM SPECIFICATION $$ models: {orchestration: auto} orchestration: {budget: {seconds: 60, tokens: 16000}} instructions: {system: "You are PINNACLE_FINANCIAL_ANALYST_33, an AI assistant for Pinnacle Financial Services, a $2B AUM asset management firm. You help executives and the finance team answer questions about revenue, expenses, client profitability, and financial performance. Data covers July 2025 through January 2026.", response: "Always present financial figures with dollar signs and commas. Round to 2 decimal places. Be concise and professional.", orchestration: "Use the Financial_Analytics tool for all questions about revenue, expenses, clients, products, budgets, and financial performance.", sample_questions: [{question: "What was our total revenue last quarter?", answer: "I will query Q4 2025 revenue totals."}, {question: "Which clients generated the most revenue?", answer: "Let me pull the top clients ranked by total revenue."}, {question: "What are our expenses by category?", answer: "I will break down total expenses by group."}, {question: "Show me revenue by product type", answer: "I will analyze revenue across fee types."}, {question: "What is our net income?", answer: "I will calculate total revenue minus total expenses."}, {question: "How does revenue compare across office locations?", answer: "Let me break down revenue by New York, Boston, and San Francisco."}]} tools: [{tool_spec: {type: cortex_analyst_text_to_sql, name: Financial_Analytics, description: "Queries Pinnacle Financial Services structured financial data including revenue transactions, expense records, client information, and investment products. Use for any question about revenue, fees, expenses, costs, clients, products, AUM, profitability, or financial performance. Data covers July 2025 through January 2026."}}, {tool_spec: {type: data_to_chart, name: data_to_chart, description: "Generates charts and visualizations from query results."}}] tool_resources: {Financial_Analytics: {semantic_view: "PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.PINNACLE_FINANCIAL_SV"}} $$

  **/


  SELECT CLIENT_NAME, CLIENT_SEGMENT, AUM_TIER, OFFICE_LOCATION
FROM PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.DIM_CLIENT
ORDER BY CLIENT_KEY;


SHOW SEMANTIC VIEWS IN SCHEMA PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS;



SELECT *
FROM SEMANTIC_VIEW(
    PINNACLE_FINANCIAL_DEMO_33.FINANCE_ANALYTICS.PINNACLE_FINANCIAL_SV
    METRICS total_revenue
    WHERE dates.quarter_name = 'Q4' AND dates.year_number = 2025;
)