# Recursive Hierarchy Rollup (Org Charts, BOM, Category Trees)

## Difficulty

🔴 **Hard**

## Companies

Google, Amazon, Salesforce, SAP, LinkedIn, Workday

---

## Problem Statement

You are a Data Engineer at an enterprise software company building headcount and budget reporting for leadership. Employees are stored in a self-referencing `employees` table where each employee has a `manager_id` pointing to another row in the same table (and the CEO has `manager_id IS NULL`).

Finance wants a report showing, for **every employee** (from the CEO down to individual contributors):
1. Their **reporting depth** (CEO = level 1, direct reports = level 2, etc.) and full **management path** (e.g., `Alice > Bob > Carol`).
2. Their **direct salary** and their **total subtree salary rollup** (their own salary plus the salaries of everyone who reports directly or indirectly beneath them).
3. Their **total org size** (count of all direct + indirect reports under them, excluding themselves).

This recursive tree aggregation pattern applies identically to Bill of Materials (BOM) cost rollups, multi-level category revenue trees, and folder storage quotas.

---

## Schema DDL

```sql
CREATE TABLE employees (
    emp_id      INT PRIMARY KEY,
    emp_name    VARCHAR(100) NOT NULL,
    title       VARCHAR(100) NOT NULL,
    department  VARCHAR(50)  NOT NULL,
    manager_id  INT REFERENCES employees(emp_id),
    salary      DECIMAL(12, 2) NOT NULL
);

-- Insert top-down by management tier so self-referencing FK constraints pass across engines
INSERT INTO employees (emp_id, emp_name, title, department, manager_id, salary) VALUES
(1,  'Alice Chen',    'CEO',                  'Executive',   NULL, 350000.00);

INSERT INTO employees (emp_id, emp_name, title, department, manager_id, salary) VALUES
(2,  'Bob Patel',     'VP Engineering',       'Engineering', 1,    260000.00),
(3,  'Carol Diaz',    'VP Sales',             'Sales',       1,    240000.00);

INSERT INTO employees (emp_id, emp_name, title, department, manager_id, salary) VALUES
(4,  'David Kim',     'Director Data Eng',    'Engineering', 2,    200000.00),
(5,  'Eva Novak',     'Director Platform',    'Engineering', 2,    195000.00),
(10, 'Jack Ross',     'Enterprise AE',        'Sales',       3,    140000.00),
(11, 'Karen Ortiz',   'SMB Sales Manager',    'Sales',       3,    150000.00);

INSERT INTO employees (emp_id, emp_name, title, department, manager_id, salary) VALUES
(6,  'Frank Wu',      'Staff Data Engineer',  'Engineering', 4,    175000.00),
(7,  'Grace Lee',     'Senior Data Engineer', 'Engineering', 4,    155000.00),
(9,  'Ivy Taylor',    'Senior Platform Eng',  'Engineering', 5,    160000.00),
(12, 'Leo Martin',    'Account Executive',    'Sales',       11,   110000.00);

INSERT INTO employees (emp_id, emp_name, title, department, manager_id, salary) VALUES
(8,  'Henry Brooks',  'Data Engineer',        'Engineering', 6,    130000.00);
```

---

## Sample Input

**employees**

| emp_id | emp_name     | title                | department  | manager_id | salary    |
|--------|--------------|----------------------|-------------|------------|-----------|
| 1      | Alice Chen   | CEO                  | Executive   | NULL       | 350000.00 |
| 2      | Bob Patel    | VP Engineering       | Engineering | 1          | 260000.00 |
| 3      | Carol Diaz   | VP Sales             | Sales       | 1          | 240000.00 |
| 4      | David Kim    | Director Data Eng    | Engineering | 2          | 200000.00 |
| 5      | Eva Novak    | Director Platform    | Engineering | 2          | 195000.00 |
| 6      | Frank Wu     | Staff Data Engineer  | Engineering | 4          | 175000.00 |
| 7      | Grace Lee    | Senior Data Engineer | Engineering | 4          | 155000.00 |
| 8      | Henry Brooks | Data Engineer        | Engineering | 6          | 130000.00 |
| 9      | Ivy Taylor   | Senior Platform Eng  | Engineering | 5          | 160000.00 |
| 10     | Jack Ross    | Enterprise AE        | Sales       | 3          | 140000.00 |
| 11     | Karen Ortiz  | SMB Sales Manager    | Sales       | 3          | 150000.00 |
| 12     | Leo Martin   | Account Executive    | Sales       | 11         | 110000.00 |

---

## Expected Output

| emp_id | emp_name     | level | management_path                                              | direct_salary | total_org_salary | total_reports |
|--------|--------------|-------|--------------------------------------------------------------|---------------|------------------|---------------|
| 1      | Alice Chen   | 1     | Alice Chen                                                   | 350000.00     | 2265000.00       | 11            |
| 2      | Bob Patel    | 2     | Alice Chen > Bob Patel                                       | 260000.00     | 1275000.00       | 6             |
| 4      | David Kim    | 3     | Alice Chen > Bob Patel > David Kim                           | 200000.00     | 660000.00        | 3             |
| 6      | Frank Wu     | 4     | Alice Chen > Bob Patel > David Kim > Frank Wu                | 175000.00     | 305000.00        | 1             |
| 8      | Henry Brooks | 5     | Alice Chen > Bob Patel > David Kim > Frank Wu > Henry Brooks | 130000.00     | 130000.00        | 0             |
| 7      | Grace Lee    | 4     | Alice Chen > Bob Patel > David Kim > Grace Lee               | 155000.00     | 155000.00        | 0             |
| 5      | Eva Novak    | 3     | Alice Chen > Bob Patel > Eva Novak                           | 195000.00     | 355000.00        | 1             |
| 9      | Ivy Taylor   | 4     | Alice Chen > Bob Patel > Eva Novak > Ivy Taylor              | 160000.00     | 160000.00        | 0             |
| 3      | Carol Diaz   | 2     | Alice Chen > Carol Diaz                                      | 240000.00     | 640000.00        | 3             |
| 10     | Jack Ross    | 3     | Alice Chen > Carol Diaz > Jack Ross                          | 140000.00     | 140000.00        | 0             |
| 11     | Karen Ortiz  | 3     | Alice Chen > Carol Diaz > Karen Ortiz                        | 150000.00     | 260000.00        | 1             |
| 12     | Leo Martin   | 4     | Alice Chen > Carol Diaz > Karen Ortiz > Leo Martin           | 110000.00     | 110000.00        | 0             |

---

## Brute Force Solution

**Approach: Fixed-depth multi-way self-joins**

If you don't use recursion, you have to self-join the `employees` table up to the maximum assumed hierarchy depth (here, 5 levels) and flatten every ancestor-descendant relationship with `UNION ALL`.

```sql
-- Hard-coded up to 5 levels of management
WITH pairs AS (
    -- Depth 0 (self)
    SELECT e1.emp_id AS ancestor_id, e1.emp_id AS descendant_id, e1.salary
    FROM employees e1
    UNION ALL
    -- Depth 1 (direct reports)
    SELECT e1.emp_id, e2.emp_id, e2.salary
    FROM employees e1
    JOIN employees e2 ON e2.manager_id = e1.emp_id
    UNION ALL
    -- Depth 2
    SELECT e1.emp_id, e3.emp_id, e3.salary
    FROM employees e1
    JOIN employees e2 ON e2.manager_id = e1.emp_id
    JOIN employees e3 ON e3.manager_id = e2.emp_id
    UNION ALL
    -- Depth 3
    SELECT e1.emp_id, e4.emp_id, e4.salary
    FROM employees e1
    JOIN employees e2 ON e2.manager_id = e1.emp_id
    JOIN employees e3 ON e3.manager_id = e2.emp_id
    JOIN employees e4 ON e4.manager_id = e3.emp_id
    UNION ALL
    -- Depth 4
    SELECT e1.emp_id, e5.emp_id, e5.salary
    FROM employees e1
    JOIN employees e2 ON e2.manager_id = e1.emp_id
    JOIN employees e3 ON e3.manager_id = e2.emp_id
    JOIN employees e4 ON e4.manager_id = e3.emp_id
    JOIN employees e5 ON e5.manager_id = e4.emp_id
)
SELECT
    e.emp_id,
    e.emp_name,
    e.salary AS direct_salary,
    SUM(p.salary) AS total_org_salary,
    COUNT(p.descendant_id) - 1 AS total_reports
FROM employees e
JOIN pairs p ON e.emp_id = p.ancestor_id
GROUP BY e.emp_id, e.emp_name, e.salary
ORDER BY e.emp_id;
```

**Explanation:**
1. Explicitly enumerate paths of length 0, 1, 2, 3, and 4 using cascading self-joins.
2. Union all ancestor-descendant pairs together.
3. Aggregate by `ancestor_id` to get subtree salary sums and descendant counts.

**Drawbacks:**
- **Breaks silently if depth increases** — if Henry Brooks hires an intern (level 6), that intern is completely dropped from Alice's and Bob's rollups.
- **Does not cleanly compute dynamic `level` or `management_path`** without even messier `COALESCE` chains across 5 left joins.
- **Redundant scans** — scans and joins `employees` $1 + 2 + 3 + 4 + 5 = 15$ times.

---

## Optimal Solution

**Approach: Recursive CTE (`WITH RECURSIVE`) building ancestor-descendant closure + path**

We run two cleanly separated ideas in one recursive pipeline:
1. Build the top-down tree (`org_tree`) starting from roots (`manager_id IS NULL`) to get exact `level` and `management_path` for every node.
2. Build the transitive closure (`closure`) starting every employee as their own ancestor, then walking down `manager_id` to attach every descendant to every ancestor above them, and finally `GROUP BY` ancestor.

```sql
WITH RECURSIVE org_tree AS (
    -- Anchor: top-level roots (CEO / nodes with no manager)
    SELECT
        emp_id,
        emp_name,
        manager_id,
        salary,
        1 AS level,
        CAST(emp_name AS VARCHAR(1000)) AS management_path
    FROM employees
    WHERE manager_id IS NULL

    UNION ALL

    -- Recursive step: attach direct reports and extend path
    SELECT
        c.emp_id,
        c.emp_name,
        c.manager_id,
        c.salary,
        p.level + 1 AS level,
        CAST(p.management_path || ' > ' || c.emp_name AS VARCHAR(1000)) AS management_path
    FROM employees c
    JOIN org_tree p ON c.manager_id = p.emp_id
),
closure AS (
    -- Anchor: every employee is an ancestor of themselves (distance = 0)
    SELECT
        emp_id AS ancestor_id,
        emp_id AS descendant_id,
        salary AS descendant_salary
    FROM employees

    UNION ALL

    -- Recursive step: walk down to direct reports of current descendants
    SELECT
        cl.ancestor_id,
        e.emp_id AS descendant_id,
        e.salary AS descendant_salary
    FROM closure cl
    JOIN employees e ON e.manager_id = cl.descendant_id
),
rollup AS (
    SELECT
        ancestor_id AS emp_id,
        SUM(descendant_salary) AS total_org_salary,
        COUNT(*) - 1           AS total_reports
    FROM closure
    GROUP BY ancestor_id
)
SELECT
    t.emp_id,
    t.emp_name,
    t.level,
    t.management_path,
    t.salary AS direct_salary,
    r.total_org_salary,
    r.total_reports
FROM org_tree t
JOIN rollup r ON t.emp_id = r.emp_id
ORDER BY t.management_path;
```

### Why This Is Better

| Dimension | Brute Force (Self-Joins) | Optimal (Recursive CTE) |
|-----------|--------------------------|-------------------------|
| **Depth limit** | Hard-coded; silently drops deeper nodes | Arbitrary depth $D$ automatically |
| **Hierarchy path & level** | Messy multi-join `COALESCE` chains | Computed cleanly in single top-down pass |
| **Maintainability** | Adding a level requires rewriting SQL | Zero code changes for deeper orgs |
| **Algorithmic clarity** | Repeats join logic $D$ times | Standard transitive closure pattern |

> [!WARNING]
> **Cycle protection**: In dirty real-world data, bad updates can introduce cycles (`A -> B -> A`), causing a recursive CTE to loop infinitely until the query hits a max-recursion limit. In production, track visited IDs in a path string (`',' || emp_id || ','`) and filter `WHERE position(',' || c.emp_id || ',' IN p.id_path) = 0` (or use `CYCLE` clause in PostgreSQL 14+ / ANSI SQL).

---

## Interviewer Follow-Up Questions

### 1. "How do you prevent infinite loops if the data contains a cycle (e.g., A manages B, and B manages A)?"

Maintain an `id_path` alongside `management_path` and ensure the next node isn't already in the path (and cap `level` as a safety net):
```sql
-- Inside recursive member:
WHERE POSITION('|' || CAST(c.emp_id AS VARCHAR(20)) || '|' IN p.id_path) = 0
  AND p.level < 50
```
In PostgreSQL 14+ or Oracle, you can also use the native `CYCLE emp_id SET is_cycle USING path` clause directly on the recursive CTE.

### 2. "What if this were a Bill of Materials (BOM) where a single sub-component can appear in multiple parent assemblies with a `quantity` multiplier?"

Unlike org charts (trees where every node has 1 parent), a BOM is a **Directed Acyclic Graph (DAG)**. A sub-part can be reached via multiple paths, and each edge carries a `quantity`. In the `closure` CTE, carry a cumulative `multiplier`:
- Anchor: `1 AS qty_multiplier`
- Recursive step: `cl.qty_multiplier * bom.quantity`
- Final rollup: `SUM(cl.qty_multiplier * part.unit_cost)` (and do NOT deduplicate paths, because each distinct assembly path adds real cost!).

### 3. "Recursive CTEs can be slow on deep/wide trees read millions of times per day. How would you optimize this in a production data warehouse?"

Pre-compute a **Closure Table** (or **Nested Sets** / **Materialized Path** column) in an ETL/dbt batch job:
- Store `(ancestor_id, descendant_id, depth)` in a dedicated `dim_org_closure` table refreshed nightly.
- Any downstream subtree aggregation becomes a single indexed `JOIN` + `GROUP BY` with zero recursion at query time.

---

## Key Takeaways

- 📌 **`WITH RECURSIVE`** has two parts: a non-recursive **anchor member** and a **recursive member** joined via `UNION ALL`
- 📌 Top-down traversal computes **depth (`level`)** and **breadcrumbs (`management_path`)** naturally
- 📌 Building a **transitive closure `(ancestor_id, descendant_id)`** in SQL lets you aggregate any subtree metric (`SUM`, `COUNT`, `MAX`) with a simple `GROUP BY ancestor_id`
- 📌 **Org charts are trees; BOMs are DAGs** — for DAGs, propagate edge weights (`qty_multiplier`) down each path instead of assuming 1 parent per node
- 📌 Always guard recursive queries against **cycles** and **max recursion depth** in production
- 📌 For high-QPS analytics, materialize the **closure table** or **materialized path** in your warehouse rather than recursing on every dashboard query
