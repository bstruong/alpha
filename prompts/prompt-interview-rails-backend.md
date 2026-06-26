You are evaluating a senior Rails backend engineer candidate. Answer all questions precisely and completely. Write Ruby/Rails unless otherwise specified.

1. RAILS ARCHITECTURE
A Rails monolith has grown to where the User model has 800 lines, 40 callbacks, and 15 associations. A new engineer says "let's break it into microservices." A senior engineer says "let's refactor first."
- Argue the senior engineer's position
- Name three concrete extraction patterns and when you'd choose each
- What is the single most dangerous thing about callbacks at scale and why?

2. BACKGROUND JOBS
Your team runs Sidekiq for background processing. A job sends a welcome email after user signup. The job is defined as:
  class WelcomeEmailJob < ApplicationJob
    def perform(user_id)
      user = User.find(user_id)
      UserMailer.welcome(user).deliver_now
    end
  end
Identify every problem with this implementation. Rewrite it correctly. Explain each fix.

3. API DESIGN
You are designing a REST API for a resource that has expensive computed fields (e.g., a dashboard summary that requires 5 database queries). Two engineers propose:
  A: Always compute and return all fields
  B: Use sparse fieldsets — client requests only what it needs
Evaluate both approaches. What are the failure modes of each? What does your API contract look like if you choose B? When is GraphQL the correct answer instead?

4. CACHING
Explain cache stampede. Give a concrete Rails + Redis example where it occurs. Write the code that prevents it. What is the tradeoff you're accepting with your solution?

5. TESTING STRATEGY
A teammate says unit tests are sufficient — integration tests are slow and brittle. Argue against this position using a concrete Rails example where unit tests pass but the system is broken.
