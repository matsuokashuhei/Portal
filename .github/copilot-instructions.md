# GitHub Copilot Custom Instructions

## Review Response Handling

When a reviewee responds to your review comment:
1. Read and understand the response carefully
2. Verify if the issue has been resolved by checking:
   - The linked commit or code change
   - Whether the fix addresses the original concern
   - If the explanation is valid when no code change is needed
3. Reply with a clear resolution status:
   - If resolved: Acknowledge the fix and mark as resolved
   - If not resolved: Explain what's still needed
   - If clarification needed: Ask specific follow-up questions

## Code Review Focus Areas

### Security (Swift/macOS)
- Check for proper Accessibility API permission handling
- Verify no hardcoded credentials or API keys
- Review input validation for user-provided data
- Ensure proper sandboxing considerations

### Performance
- Identify potential main thread blocking
- Check for memory leaks (retain cycles, strong references in closures)
- Review async/await usage for proper concurrency
- Spot inefficient loops or unnecessary recomputation

### Swift/SwiftUI Best Practices
- Verify proper use of `@MainActor` for UI updates
- Check for appropriate use of value types vs reference types
- Review optional handling (force unwraps, nil coalescing)
- Ensure proper error handling with Swift's error types

### Code Quality
- Functions should follow Single Responsibility Principle
- Use clear, descriptive naming following Swift conventions
- Ensure proper access control (private, internal, public)
- Check for appropriate use of protocols and extensions

## Review Style
- Be specific and actionable in feedback
- Explain the "why" behind recommendations
- Acknowledge good patterns when you see them
- Ask clarifying questions when code intent is unclear
- Respect the project's existing patterns and conventions

## Review Scope Awareness

Check the PR description's "Review scope" section:
- Focus on items marked as "Review requested"
- Skip items marked as "Out of scope" (planned for future issues)
- Don't flag TODOs that reference future issue numbers

## Language

Provide review comments in English.
