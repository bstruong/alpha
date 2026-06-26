You are being evaluated on Ruby and Rails fundamentals. Answer all questions. Be precise and complete.

1. RUBY LANGUAGE
Explain the difference between include, extend, and prepend in Ruby.
Give a concrete use case for each. What is the method lookup order
(MRO) when prepend is used?

2. ACTIVERECORD
A Rails app has a Post model with many Comments. A developer writes:
  Post.all.each { |post| puts post.comments.count }
What is wrong with this code? Fix it two different ways and explain
the tradeoff between the fixes.

3. DESIGN — ANTI-PATTERN
What is a God object? Give a Rails-specific example of how one forms.
Name two concrete refactoring patterns that break it apart and explain
when you'd choose one over the other.

4. TESTING
What is the difference between a mock and a stub?
A teammate says "we should mock the database in all unit tests."
Argue for and against this position.

5. SANDI METZ
Summarize the core argument of Practical Object-Oriented Design.
What are her four rules for developers? Why does she say "duplication
is far cheaper than the wrong abstraction"?

