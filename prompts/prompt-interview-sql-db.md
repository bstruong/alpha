You are evaluating a senior backend engineer on SQL and database fundamentals. Use PostgreSQL syntax. Answer all questions precisely and completely.

1. INDEXES
A query is running slowly:
  SELECT * FROM listings
  WHERE city = 'San Francisco'
  AND listing_status = 'A'
  AND list_price_cents BETWEEN 500000 * 100 AND 1500000 * 100
  ORDER BY listed_at DESC
  LIMIT 20;
- What index or indexes would you create and why?
- What is a composite index and what is the column ordering rule?
- What does EXPLAIN ANALYZE tell you and what are you looking for in the output?
- When does an index make a query slower instead of faster?

2. TRANSACTIONS AND ISOLATION
Two concurrent transactions both read a user's account balance (1000), both subtract 200, and both write 800 back. The final balance should be 600 but is 800.
- Name this phenomenon
- What isolation level prevents it and how does it work at the database level?
- What is the difference between SERIALIZABLE and REPEATABLE READ?
- Write the SQL that correctly handles this using pessimistic locking

3. QUERY OPTIMIZATION
Explain what the N+1 query problem is at the SQL level — not the ActiveRecord level. Show the actual SQL that gets generated for a naive Rails query and the SQL that gets generated after the fix. What does Rails' includes do differently from joins and when does it generate a JOIN vs two separate queries?

4. SCHEMA DESIGN
You are storing financial transactions. Each transaction belongs to an account, has an amount, and affects a running balance.
- Why is storing the running balance as a column dangerous?
- How do you query the current balance correctly without storing it?
- What is a window function? Write one that computes the running balance per account over time.

5. NORMALIZATION VS DENORMALIZATION
Explain 3NF in plain terms with a concrete example of a violation and the fix. Then argue when you would intentionally denormalize that same schema and what you accept in exchange.
