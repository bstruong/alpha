You are evaluating a senior Java backend engineer candidate. Answer all questions in Java 21 unless otherwise specified.

1. CONCURRENCY
Two threads simultaneously withdraw from a shared bank account:
  public class BankAccount {
      private int balance;
      public void withdraw(int amount) {
          if (balance >= amount) {
              balance -= amount;
          }
      }
  }
- Identify the race condition and name the phenomenon
- Fix it three different ways: synchronized, ReentrantLock, and AtomicInteger
- What is the tradeoff between each approach?
- When would you choose optimistic locking via a version field in the database instead of in-memory locking?

2. COLLECTIONS AND COMPLEXITY
A service receives a list of 1 million order IDs and must return only those that exist in the database. A junior engineer writes:
  List<Order> found = new ArrayList<>();
  for (Long id : incomingIds) {
      orderRepository.findById(id).ifPresent(found::add);
  }
- What is wrong with this and what is its time complexity?
- Rewrite it correctly using Java 21 features and proper batch querying
- Explain the difference between HashMap and LinkedHashMap — when does ordering matter?

3. STREAMS AND FUNCTIONAL STYLE
Given a list of transactions, write a Java 21 stream pipeline that:
- Filters to only COMPLETED status
- Groups by currency code
- Computes the total amount per currency
- Returns a Map<String, BigDecimal> sorted by total descending
Explain what a Collector is and why BigDecimal is used instead of double for money.

