# Exercise 2: Master Cortex Code Skills

## Objective

Learn to use built-in Cortex Code skills and create custom skills that encode your team's best practices for future POCs and projects.

**Time:** 60 minutes  
**Deliverables:**
- Experience with multiple built-in skills
- A custom skill for financial analytics POC preparation

---

## Background

Skills are reusable workflows that teach Cortex Code how to complete specific tasks consistently. They're like runbooks that execute automatically.

**Why Skills Matter for Your Team:**
- Encode best practices once, use everywhere
- Ensure consistency across team members
- Reduce time on repetitive workflows
- Share expertise without shadowing colleagues

---

## Skill Storage Locations

Skills can be stored in three locations, each with different scope and precedence:

| Type | Location | Scope | Use Case |
|------|----------|-------|----------|
| **Bundled** | `~/.local/share/cortex/*/bundled_skills/` | All projects (read-only) | Ships with Cortex Code |
| **Global** | `~/.cortex/skills/` | All projects | Your reusable personal/team skills |
| **Project-local** | `.cortex/skills/` in project root | Single project only | Project-specific workflows |

**Precedence:** Project-local > Global > Bundled

This means you can override a bundled skill by creating one with the same name in your global or project directory.

**Quick commands:**
```bash
# View bundled skills (read-only)
ls ~/.local/share/cortex/*/bundled_skills/

# View your global custom skills
ls ~/.cortex/skills/

# View project-local skills
ls .cortex/skills/
```

---

## Task 1: Explore Built-in Skills (15 min)

### Step 1: List available skills

```
List all available skills and briefly describe what each does.
```

### Step 2: Understand skill structure

```
Explain the structure of a Cortex Code skill:
- What files does it contain?
- What is the SKILL.md format?
- How do skills get triggered?

Keep it concise - bullet points preferred.
```

### Step 3: Review the semantic-view-optimization skill

We used this in Exercise 1. Let's understand it better:

```
Show me the structure of the semantic-view-optimization skill.
What are its main workflow steps?
What sub-skills does it contain?
```

---

## Task 2: Use a Bundled Skill (20 min)

### Use the agent-optimization skill

Let's improve the Snowflake Intelligence agent from Exercise 1:

```
Use the agent-optimization skill to audit and improve the Pinnacle Financial 
Analyst we created in Exercise 1. Proceed autonomously.

Check for:
1. Are the guardrails appropriate for financial data?
2. Is the semantic model complete?
3. Are there edge cases we're missing?
4. What questions might fail?

Fix any gaps identified in the semantic view audit. Add any missing metrics 
(like profitability calculations) and update the semantic view with appropriate 
data coverage documentation.
```

---

## Task 3: Create a Custom Skill (25 min)

Now you'll create your own skill that encodes a repeatable POC preparation workflow for your team.

### Step 1: Define the skill scope

```
I want to create a custom skill called "financial-demo-prep" that will help 
our team quickly prepare financial analytics POCs for future projects.
Proceed autonomously.

The skill should:
1. Gather project requirements (company info, pain points, stakeholders)
2. Generate customized sample data
3. Create a semantic model tailored to the use case
4. Create a Cortex Agent and enable it in Snowflake Intelligence
5. Produce presentation talking points

Help me outline the workflow steps this skill should contain.
```

### Step 2: Create the skill structure

```
Create the skill file structure in the skills/ directory. Proceed autonomously.

skills/
└── financial-demo-prep/
    ├── SKILL.md
    └── (any supporting files)

The SKILL.md should follow best practices:
- Proper frontmatter with name and description
- Clear workflow steps
- Stopping points for user input
- Success criteria
- Automatically create Cortex Agent and enable in Snowflake Intelligence
```

### Step 3: Write the skill content

Use this prompt to have Cortex Code help write the skill:

```
Write the SKILL.md content for the financial-demo-prep skill. Include:

## Frontmatter
- name: financial-demo-prep  
- description: Trigger phrases and when to use

## Workflow Steps
1. **Gather Requirements** - Questions to ask about the project
2. **Generate Schema** - Create tables matching the business
3. **Create Semantic Model** - Build Cortex Analyst config
4. **Create Agent** - Build Cortex Agent and enable in Snowflake Intelligence
5. **Generate Presentation Script** - Talking points and queries
6. **Validation** - Ensure everything works

## Stopping Points
- After requirements gathering (confirm understanding)
- After data generation (verify looks realistic)
- After presentation script (approve before presenting)

## Output
What artifacts this skill produces

Keep it under 200 lines - skills should be concise.
```

### Step 4: Test the skill (Optional)

Test your new skill:

> **Note:** This step may take 5-10 minutes to complete as the skill generates demo data, creates schemas, and builds a semantic model.

```
Use the financial-demo-prep skill to prepare a POC for a fictional 
scenario: "Cascade Wealth Management" - a $500M AUM RIA focused on 
retirement planning. Their main pain point is client profitability analysis.
```

### Step 5: Promote to Global Skill (Optional)

If your skill works well and you want to reuse it across all projects, promote it from project-local to global:

```
Copy the financial-demo-prep skill from the project's .cortex/skills/ 
directory to my global skills directory (~/.cortex/skills/) so I can 
use it in any project.
```

**Why promote a skill?**
- Share across multiple projects
- Build a personal library of reusable workflows
- Team members can copy your global skills to their machines

**Alternative:** Create directly in global from the start:
```
Create the financial-demo-prep skill in my global skills directory 
(~/.cortex/skills/) instead of the project-local directory.
```

---

## Task 4: Understand Skill Best Practices (Bonus)

### Key principles from the skill development guide:

1. **Conciseness is key** - Keep SKILL.md under 500 lines
2. **Degrees of freedom** - Match specificity to task fragility
3. **Stopping points** - Always pause before making changes
4. **Modularity is optional** - Single files work for simple workflows
5. **Test with real scenarios** - Skills should handle edge cases

### Skill quality checklist:

```markdown
□ Clear trigger description in frontmatter
□ Workflow steps are numbered and specific
□ Actions use directive language ("Ask", "Create", "Verify")
□ Stopping points marked with ⚠️
□ Success criteria defined
□ Error handling guidance included
□ Under 200 lines (simple) or 500 lines (complex)
```

---

## Validation Checklist

Before proceeding to Exercise 3, verify:

- [ ] Used the agent-optimization bundled skill successfully
- [ ] Created financial-demo-prep skill with proper structure
- [ ] Skill has clear frontmatter and workflow steps
- [ ] Skill includes appropriate stopping points
- [ ] Tested skill with a sample scenario (optional)
- [ ] Skill produces expected outputs

---

## Key Takeaways

1. **Skills save time** - Encode once, use repeatedly
2. **Built-in skills are powerful** - Check what exists before building
3. **Start simple** - Single-file skills work for most use cases
4. **Stopping points are critical** - Never auto-execute risky actions
5. **Share with your team** - Skills are documentation + automation

---

## Pro Tips

1. **Name skills descriptively** - Use trigger words in the description
2. **Version your skills** - Put them in source control
3. **Iterate based on use** - Improve skills after real-world testing
4. **Keep references separate** - Large docs go in references/ folder
5. **Test edge cases** - What if user provides incomplete info?

---

## Solution Reference

If you get stuck, reference solutions are available in `solutions/exercise-2-solution/`

---

## Next Steps

Proceed to [Exercise 3: Stakeholder Documentation](exercise-3-documentation.md) where you'll generate architecture diagrams and integration guides to present to leadership.
