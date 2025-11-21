# Contributing to OCI Free Tier Manager

Thank you for considering contributing to this project!

## Development Environment

This project uses [devbox](https://www.jetpack.io/devbox/) for reproducible development environments.

```bash
# Install devbox
curl -fsSL https://get.jetpack.io/devbox | bash

# Enter development environment
devbox shell

# Pre-commit hooks will be installed automatically
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for detailed setup instructions.

## Code Standards

### Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Code style (formatting, missing semi-colons, etc.)
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `test`: Adding tests
- `chore`: Changes to build process or auxiliary tools

**Examples:**
```
feat(tofu): add Proxmox provider configuration

docs: update README with devbox instructions

fix(check_availability): handle OCI API timeout errors
```

### Code Quality

Before committing, ensure:

1. **Code is formatted:**
   ```bash
   devbox run fmt
   ```

2. **Linters pass:**
   ```bash
   devbox run lint
   ```

3. **Pre-commit hooks pass:**
   ```bash
   pre-commit run --all-files
   ```

### OpenTofu/Infrastructure

- Use meaningful resource names
- Document all variables with descriptions
- Add validation blocks where appropriate
- Keep modules focused and reusable
- Follow the 3-layer structure (oci, proxmox-cluster, talos)

### Python

- Follow PEP 8 (enforced by Black + Flake8)
- Add docstrings to functions
- Use type hints where beneficial
- Maximum line length: 100 characters

### Documentation

- Update relevant docs when changing functionality
- Use clear, concise language
- Include code examples where helpful
- Keep CHANGELOG.md updated

## Pull Request Process

1. **Fork the repository**

2. **Create a feature branch:**
   ```bash
   git checkout -b feat/your-feature-name
   ```

3. **Make your changes:**
   - Follow code standards above
   - Update documentation
   - Add/update tests if applicable

4. **Test locally:**
   ```bash
   devbox run lint
   devbox run check  # Validate OpenTofu
   ```

5. **Commit with conventional commits:**
   ```bash
   git add .
   git commit -m "feat: add new feature"
   ```

6. **Push to your fork:**
   ```bash
   git push origin feat/your-feature-name
   ```

7. **Open a Pull Request:**
   - Provide clear description of changes
   - Link any related issues
   - Ensure CI passes

## What to Contribute

### Good First Issues

- Documentation improvements
- Bug fixes in availability checker
- Additional OCI region support
- Example configurations
- Test coverage improvements

### Larger Contributions

Please open an issue first to discuss:
- New features
- Architecture changes
- Breaking changes

## Questions?

- Open an issue for questions
- Check [DEVELOPMENT.md](DEVELOPMENT.md) for dev setup
- Check [WARP.md](WARP.md) for architecture details

## Code of Conduct

Be respectful and constructive. This is a collaborative project.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
