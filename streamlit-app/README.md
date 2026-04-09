# Cortex Code Hands-on Lab v3 - Building a Financial Analytics POC

## Overview

This hands-on lab teaches you how to use Cortex Code to build a compelling **Financial Analytics POC** for your organization's key stakeholders. You'll play the role of a **BI Analyst** at Pinnacle Financial Services who has been tasked with demonstrating how Snowflake's AI capabilities can transform financial reporting.

1. **Build the POC** - Create a working demo with Cortex Analyst & Snowflake Intelligence
2. **Master Cortex Code Skills** - Use built-in skills and create custom ones for your team
3. **Prepare Stakeholder Documentation** - Generate architecture docs and guides for leadership

**Duration:** 2.5-3 hours  
**Prerequisites:** Cortex Code installed, active Snowflake connection  
**Use Case:** Financial Analytics - Revenue, Expenses, and Financial Reporting

---

## Lab Scenario: You're a BI Analyst at Pinnacle Financial Services

You work as a **BI Analyst** on Pinnacle Financial's data team. Your CFO, Margaret Chen, has asked you to build a proof-of-concept demonstrating how AI-powered analytics could help executives get faster answers to financial questions.

### Your Company

| Field | Details |
|-------|---------|
| **Company** | Pinnacle Financial Services |
| **Industry** | Financial Services / Asset Management |
| **Size** | $2B AUM, 150 employees, 50K client accounts |
| **Current State** | Fragmented reporting (Excel, legacy BI), manual reconciliation |
| **Desired Outcome** | Unified financial analytics with AI-powered insights |
| **Key Stakeholders** | Margaret Chen (CFO), David Park (VP Ops), Sarah Martinez (Compliance) |
| **Your Goal** | Build a POC that impresses leadership and gets approved for production |

### What Leadership Wants to See

1. **Revenue Analytics** - Track AUM growth, fee revenue, client profitability
2. **Expense Management** - Monitor operating costs, vendor spend, budget variance
3. **Financial Reporting** - Automated P&L, balance sheets, regulatory reports
4. **AI Insights** - Natural language queries for executives ("What drove revenue growth last quarter?")

---

## Lab Structure

| Exercise | Focus Area | Duration | What You'll Build |
|----------|------------|----------|-------------------|
| [Exercise 1](exercises/exercise-1-rapid-demo.md) | Build the POC | 60 min | Demo database, Semantic View, Snowflake Intelligence |
| [Exercise 2](exercises/exercise-2-skills.md) | Master Cortex Code Skills | 60 min | Use bundled skills, create team-specific skills |
| [Exercise 3](exercises/exercise-3-documentation.md) | Stakeholder Documentation | 45 min | Architecture diagrams, integration guides for leadership |

---

## Getting Started

### Prerequisites

Before the lab, ensure you have the following:

1. **Cortex Code installed** — Follow the [Cortex Code Getting Started Guide](https://docs.snowflake.com/LIMITEDACCESS/cortex-code/cortex-code-cli) to install and configure the CLI.
2. **Snowflake credentials** — Your lab admin will provide:
   - Account URL
   - Username (e.g., `COCO_HOL_USER_7`)
   - Password
3. **A Snowflake connection configured in Cortex Code** — Run `/add-connection` inside Cortex Code or use `cortex connections add` to set up a connection to the lab account. Use these defaults:
   - **Role:** `COCO_HOL_RL`
   - **Warehouse:** `COCO_HOL_WH`

### Step 1: Move Lab Assets to an Accessible Location

Move this folder from your Downloads directory to a location Cortex Code can access, such as your Documents folder or a dedicated projects directory:

```bash
# Example: Move to Documents
mv ~/Downloads/cortex-code-hol-v3 ~/Documents/

# Or create a projects folder
mkdir -p ~/projects
mv ~/Downloads/cortex-code-hol-v3 ~/projects/
```

Then navigate to the folder in your terminal before launching Cortex Code.

### Step 2: Set Up Your Environment

```bash
# Navigate to the lab folder
cd ~/Documents/cortex-code-hol-v3  # or wherever you moved it

# Launch Cortex Code
cortex
```

In Cortex Code, verify your Snowflake connection:
```
List my available Snowflake connections
```

If you need to add a connection, use `/add-connection`. See the [Cortex Code Getting Started Guide](https://docs.snowflake.com/LIMITEDACCESS/cortex-code/cortex-code-cli) for connection configuration details.

### Step 2: Verify Available Skills

```
list skills
```

You should see `semantic-view-optimization` in the bundled skills.

### Step 3: Load Your Company Context

```
Read the company background from assets/customer-brief.md
```

---

## Assets Included

```
cortex-code-hol-v3/
├── README.md                           # This file
├── exercises/
│   ├── exercise-1-rapid-demo.md        # Build the POC with Cortex Analyst + Snowflake Intelligence
│   ├── exercise-2-skills.md            # Master skills usage and creation
│   └── exercise-3-documentation.md     # Generate stakeholder documentation
└── assets/
    ├── customer-brief.md               # Your company background
    └── discovery-notes.md              # Notes from requirements meeting with leadership
```

**Note:** Exercise 1 has you generate the POC database from scratch using Cortex Code based on your company's context - simulating a real scenario where you're building from internal requirements.

---

## Key Concepts

### Cortex Analyst
AI-powered natural language to SQL. Users ask questions in plain English, Cortex Analyst generates and runs SQL.

### Semantic Views
A layer that describes your data model to Cortex Analyst - tables, relationships, metrics, and business definitions.

### Snowflake Intelligence
Conversational AI assistant built on Cortex Analyst, providing a chat interface for data exploration.

### Skills
Reusable workflows packaged as markdown files that teach Cortex Code how to complete specific tasks.

---

## Tips for Success

1. **Use the right skill** - Check if a bundled skill exists before doing manual work
2. **Include context** - Reference your company's specific needs in prompts
3. **Iterate** - First outputs are starting points; refine with follow-ups
4. **Save everything** - Write outputs to files for your stakeholder presentations
5. **Capture patterns** - Turn repeated workflows into skills for your team
