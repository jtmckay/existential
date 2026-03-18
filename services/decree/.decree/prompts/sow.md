# Statement of Work Template

A Statement of Work (SOW) captures the business intent behind a body of work.
It defines the value being delivered, the problems being solved, and the outcomes
expected — written from the perspective of the people who benefit from the work.

## Structure

A SOW should include:

- **Title**: Clear, outcome-oriented project name
- **Business Context**: Why this work matters — the problem, opportunity, or need
- **Jobs to Be Done**: What users/stakeholders need to accomplish (framed as jobs)
- **User Scenarios**: Concrete narratives showing how people interact with the solution
- **Scope**: Boundaries — what is and isn't included in this engagement
- **Deliverables**: Tangible outputs that fulfill the jobs to be done
- **Acceptance Criteria**: How we know the work is complete and successful
- **Assumptions & Constraints**: Known limitations, dependencies, or preconditions

## Writing Guidelines

- Lead with **why** before **what** — business value before technical detail
- Frame work as **jobs to be done**: "When [situation], I want to [motivation], so I can [outcome]"
- Use **user scenarios** to ground abstract requirements in real usage
- Keep scope boundaries explicit — what's excluded is as important as what's included
- Deliverables should map back to jobs and scenarios, not implementation artifacts
- Acceptance criteria should be verifiable from a user/stakeholder perspective

## Example

# SOW: Secure Account Access

## Business Context

Users currently have no way to maintain persistent sessions across visits.
Every interaction requires re-identification, creating friction and abandonment.
Providing secure account access increases retention and enables personalized
experiences that drive engagement.

## Jobs to Be Done

1. When I return to the application, I want to resume where I left off,
   so I don't lose progress or repeat steps.
2. When I create an account, I want confidence my credentials are secure,
   so I can trust the platform with my information.
3. When I'm done using the application, I want to end my session cleanly,
   so others on shared devices can't access my account.

## User Scenarios

- **New visitor signup**: A first-time user provides an email and password,
  receives confirmation, and lands in their personalized workspace.
- **Returning user login**: A registered user enters credentials and is
  returned to their previous state within seconds.
- **Shared device logout**: A user on a library computer logs out and
  verifies the next person sees no trace of their session.

## Scope

**In scope:**

- Account creation and credential management
- Session-based login and logout
- Secure credential storage

**Out of scope (future work):**

- Social login and OAuth providers
- Multi-factor authentication
- Password recovery flows

## Deliverables

1. Account registration and login experience
2. Persistent session management
3. Secure credential handling
4. Clean session termination

## Acceptance Criteria

- A new user can create an account and immediately access the application
- A returning user can authenticate and resume their previous session
- A logged-out session reveals no user data on subsequent visits
- Credentials are never stored or transmitted in plaintext

## Assumptions & Constraints

- Users have a valid email address for registration
- The application runs in a modern web browser
- No existing user data needs migration
