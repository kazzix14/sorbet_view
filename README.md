# SorbetView

Sorbet type-checking for Rails view templates (ERB). Extracts Ruby code from templates, generates typed Ruby files, and provides LSP support for editor integration.

## Features

- Type-check Ruby code inside ERB templates with [Sorbet](https://sorbet.org/)
- LSP proxy server for hover, completion, go-to-definition in `.erb` files
- ViewComponent `erb_template` heredoc support
- Source mapping between templates and generated Ruby for accurate error reporting
- Tapioca DSL compiler for helper method RBI generation

## Installation

Add to your Gemfile:

```ruby
gem 'sorbet_view'
```

Then run:

```bash
bundle install
```

## Setup

Generate a config file:

```bash
bundle exec sv init
```

This creates `.sorbet_view.yml`:

```yaml
input_dirs:
  - app/views

exclude_paths: []

output_dir: sorbet/templates

extra_includes: []

skip_missing_locals: true
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `input_dirs` | `['app/views']` | Directories to scan for `.erb` templates |
| `exclude_paths` | `[]` | Paths to exclude from scanning |
| `output_dir` | `'sorbet/templates'` | Where generated Ruby files are written |
| `extra_includes` | `[]` | Additional modules to include in generated classes |
| `extra_body` | `''` | Additional code to include in generated classes |
| `skip_missing_locals` | `true` | Skip partials without `locals:` declaration |
| `sorbet_path` | `'srb'` | Path to the Sorbet binary |
| `typed_level` | `'true'` | Sorbet `typed` level for generated files |
| `component_dirs` | `[]` | Directories to scan for ViewComponent files |
| `controller_dirs` | `['app/controllers']` | Controller directories to watch for changes (LSP recompiles associated templates) |

| `sorbet_options` | `[]` | Additional options passed to Sorbet |

## Usage

### Compile templates

```bash
bundle exec sv compile
```

### Compile and type-check

```bash
bundle exec sv tc
```

Pass extra arguments to Sorbet after `--`:

```bash
bundle exec sv tc -- --error-url-base=https://srb.help/
```

### LSP server

```bash
bundle exec sv lsp
```

Used by the [VSCode extension](vscode/) for editor integration.

### Clean generated files

```bash
bundle exec sv clean
```

## Declaring locals in partials

Use magic comments to declare partial locals and their types:

```erb
<%# locals: (user:, admin: false) %>
<%# locals_sig: sig { params(user: User, admin: T::Boolean).void } %>

<h1><%= user.name %></h1>
<% if admin %>
  <p>Admin</p>
<% end %>
```

## ViewComponent support

Add `component_dirs` to your config:

```yaml
component_dirs:
  - app/components
```

Components using `erb_template` heredocs are automatically detected and compiled.

## Tapioca integration

SorbetView includes a Tapioca DSL compiler that generates RBI files for controller helper methods and extracts instance variable types from controller actions using [srb_lens](https://github.com/kazzix14/srb_lens).

```bash
bundle exec tapioca dsl
```

This generates:
- RBI files for helper methods
- `.defined_ivars.json` mapping template paths to instance variable types

After running `tapioca dsl`, recompile templates to apply the updated types:

```bash
bundle exec sv compile
```

When using the LSP server, templates are automatically recompiled when the corresponding controller file is saved.

## Requirements

- Ruby >= 3.2
- [Sorbet](https://sorbet.org/)
- [herb](https://herb-tools.dev/) (for fast ERB parsing)

## License

MIT License. See [LICENSE](LICENSE) for details.
