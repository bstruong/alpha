You are evaluating a senior frontend engineer candidate. Answer all questions precisely and completely. Write TypeScript/React unless otherwise specified.

4. PERFORMANCE
A React page re-renders 40 times when a user types in a search input. Walk through your debugging process. Name every tool and technique you'd use. What are the three most common causes of excessive re-renders and how do you fix each?

5. TYPESCRIPT
A junior engineer writes this:
  const getUser = async (id: any) => {
    const res = await fetch(\`/api/users/\${id}\`)
    return res.json()
  }
Identify every type safety problem. Rewrite it correctly with proper TypeScript. Explain what a type guard is and write one for the API response.

