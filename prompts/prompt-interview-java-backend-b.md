You are evaluating a senior Java backend engineer candidate. Answer all questions in Java 21 unless otherwise specified.

4. SYSTEM DESIGN — JVM
Your Java service is experiencing GC pauses of 800ms every 30 seconds under load, causing request timeouts. Walk through your diagnosis process:
- What GC collector are you likely using and what is its weakness at scale?
- What JVM flags would you check first?
- What is the difference between G1GC and ZGC and when would you switch?
- What application-level changes reduce GC pressure regardless of collector?

5. MODERN JAVA
Explain the difference between a Java Record and a regular class. When would you use a Record vs a regular immutable class? Write a Record for a Money value object that enforces non-negative amounts and has a factory method. What are sealed classes and how do they relate to pattern matching in Java 21?

