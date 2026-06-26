You are being evaluated on Java fundamentals. Answer all questions in Java 21 unless otherwise specified. Be precise and complete.

1. OOP — CORE CONCEPTS
Explain the four pillars of OOP (encapsulation, inheritance, polymorphism, abstraction) with a concrete Java example for each. Then explain why composition is often preferred over inheritance. Write a short example that demonstrates the composition approach and explain what problem it solves that inheritance cannot.

2. MEMORY MODEL
Explain the difference between the stack and the heap in Java. What lives on each? What is the difference between a primitive and a reference type? Given this code:
  String a = "hello";
  String b = "hello";
  String c = new String("hello");
  System.out.println(a == b);
  System.out.println(a == c);
  System.out.println(a.equals(c));
What does each print and why? Explain the String pool.

3. INTERFACES VS ABSTRACT CLASSES
Explain the difference between an interface and an abstract class in Java 21. When would you choose one over the other? What is a default method on an interface and why was it introduced? Write an example using a functional interface and a lambda expression that replaces an anonymous inner class.

4. GENERICS
Explain what type erasure is and why Java generics work this way. What is the difference between:
  List<Animal> animals
  List<? extends Animal> animals
  List<? super Animal> animals
Write a generic method that takes a List of any type extending Comparable and returns the maximum element. Explain the bounded type parameter syntax.

5. EXCEPTION HANDLING
Explain the difference between checked and unchecked exceptions. Why do some engineers argue checked exceptions were a mistake? What is the difference between throw and throws? Write a method that reads a file, uses try-with-resources correctly, and handles both IOException and a custom checked exception. When should you catch Exception vs a specific exception type?
