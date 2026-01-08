# Contributing to CausalDynamics.jl

Thank you for your interest in contributing to CausalDynamics.jl! This document provides guidelines and instructions for contributing.

## Development Setup

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/yourusername/CausalDynamics.jl.git
   cd CausalDynamics.jl
   ```
3. Install dependencies:
   ```julia
   using Pkg
   Pkg.activate(".")
   Pkg.instantiate()
   ```

## Making Changes

1. Create a new branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```
2. Make your changes
3. Add tests for new functionality
4. Run tests:
   ```julia
   using Pkg
   Pkg.test("CausalDynamics")
   ```
5. Update documentation if needed
6. Commit your changes with clear commit messages

## Code Style

- Follow Julia style guidelines
- Use British spelling (e.g., "organise", "colour")
- Include docstrings for all exported functions
- Add examples in docstrings where appropriate

## Documentation

- All exported functions must have docstrings
- Docstrings should include:
  - Clear description
  - Arguments section
  - Returns section
  - Examples
  - References (where appropriate)
- Update README.md if adding major features

## Testing

- Add tests for all new functionality
- Ensure all tests pass before submitting
- Aim for good test coverage

## Submitting Changes

1. Push your branch to your fork
2. Open a pull request on GitHub
3. Provide a clear description of your changes
4. Reference any related issues

## Questions?

Feel free to open an issue for questions or discussions about potential contributions.
