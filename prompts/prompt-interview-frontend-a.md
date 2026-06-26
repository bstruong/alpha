You are evaluating a senior frontend engineer candidate. Answer all questions precisely and completely. Write TypeScript/React unless otherwise specified.

1. STATE MANAGEMENT
A React application has a dashboard that displays a list of contacts. When a user logs an interaction inline, the card should optimistically disappear from the dashboard without waiting for the server response. If the server returns an error, the card should reappear.
- Implement this with TanStack Query v5
- What is an optimistic update and why does it improve perceived performance?
- What is the rollback mechanism and when does it fire?

2. COMPONENT ARCHITECTURE
You have a ContactCard component that is used in three places: the dashboard reconnect list, the contact list page, and search results. Each context needs slightly different behavior — different actions, different data shown, different click targets.
- How do you design this component to avoid prop drilling and conditional rendering hell?
- What is the difference between composition and configuration as a design strategy here?
- Write the component interface (TypeScript props type) for your preferred approach

3. SERVER STATE VS CLIENT STATE
Explain the difference between server state and client state. Give a concrete example of each in a Rails API + React app. What goes wrong when you manage server state with useState instead of TanStack Query?

