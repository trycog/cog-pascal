<div align="center">

# cog-pascal

**Pascal language extension for [Cog](https://github.com/trycog/cog-cli).**

SCIP-based code intelligence and native debugging for Pascal, Object Pascal, Delphi, and Free Pascal projects.

[Installation](#installation) · [Code Intelligence](#code-intelligence) · [Debugging](#debugging) · [How It Works](#how-it-works) · [Development](#development)

</div>

---

## Installation

### Prerequisites

- [Free Pascal Compiler (FPC)](https://www.freepascal.org/) 3.2+
- [Cog](https://github.com/trycog/cog-cli) CLI installed

### Install

```sh
cog ext:install https://github.com/trycog/cog-pascal.git
cog ext:install https://github.com/trycog/cog-pascal --version=0.1.0
cog ext:update
cog ext:update cog-pascal
```

Cog downloads the tagged GitHub release tarball, then builds locally on the installing machine with `fpc` and installs to `~/.config/cog/extensions/cog-pascal/`. `--version` matches an exact release version after optional `v` prefix normalization.

The extension version is defined once in `cog-extension.json`; release tags use `vX.Y.Z`, and the install flag uses the matching bare semver `X.Y.Z`.

---

## Code Intelligence

Add index patterns to your project's `.cog/settings.json`:

```json
{
  "code": {
    "index": [
      "src/**/*.pas",
      "src/**/*.pp",
      "src/**/*.inc",
      "**/*.lpr",
      "**/*.dpr",
      "**/*.dpk",
      "**/*.dfm",
      "**/*.lfm"
    ]
  }
}
```

Then index your project:

```sh
cog code:index
```

Once indexed, AI agents query symbols through Cog's MCP tools:

- `cog_code_explore` -- Find symbols by name, returns full definition bodies and references
- `cog_code_query` -- Low-level queries: find definitions, references, or list symbols in a file
- `cog_code_status` -- Check index availability and coverage

The index is stored at `.cog/index.scip` and automatically kept up-to-date by Cog's file watcher after the initial build.

| File Type | Capabilities |
|-----------|--------------|
| `.pas` | Go-to-definition, find references, symbol search, project structure |
| `.pp` | Same capabilities (Free Pascal source files) |
| `.lpr` | Same capabilities (Lazarus program files) |
| `.dpr` | Same capabilities (Delphi program files) |
| `.dpk` | Same capabilities (Delphi package files) |
| `.inc` | Same capabilities (include files) |
| `.dfm` | Delphi form objects, components, properties, and nested hierarchies |
| `.lfm` | Lazarus form objects, components, properties, and nested hierarchies |

### Indexing Features

The SCIP indexer supports:

- Units (`unit`), programs (`program`), and libraries (`library`) with dotted names
- Classes (`class`) with visibility sections (public, private, protected, published, strict)
- Records (standard and packed) with fields and methods
- Interfaces (`interface`, `dispinterface`)
- Enums with member extraction
- Type aliases, subranges, sets, arrays, and pointer types
- Functions and procedures with arity tracking and parameter modifiers (`var`, `const`, `out`, `constref`)
- Constructors and destructors
- Properties with directives (`default`, `stored`, `nodefault`)
- Constants and resource strings (`resourcestring`)
- Variables and thread-local variables (`threadvar`)
- Generics (skips `<T>` syntax gracefully)
- Method directives (`virtual`, `abstract`, `override`, `overload`, `inline`, `static`)
- Calling conventions (`cdecl`, `stdcall`, `pascal`, `register`, `safecall`)
- Forward declarations
- Qualified method implementations (`TFoo.Method`)
- Variant records with case selectors
- Import tracking (`uses` clause)
- Scope tracking with `enclosing_symbol` for nested definitions
- DFM/LFM form files: objects, components, properties, collections, and nested hierarchies

---

## Debugging

Cog's debug daemon manages debug sessions through native debugging. AI agents interact with debugging through MCP tools -- `cog_debug_launch`, `cog_debug_breakpoint`, `cog_debug_run`, `cog_debug_inspect`, `cog_debug_stacktrace`, and others.

### Daemon commands

```sh
cog debug:serve       # Start the debug daemon
cog debug:status      # Check daemon health and active sessions
cog debug:dashboard   # Live session monitoring TUI
cog debug:kill        # Stop the daemon
```

### Configuration

| Setting | Value |
|---------|-------|
| Debugger type | `native` |
| Boundary markers | `$PASCALMAIN`, `FPC_SysEntry`, `FPC_SYSTEMMAIN`, `FPC_DO_EXIT`, `FPC_RAISEEXCEPTION`, `FPC_CATCHES`, `FPC_RERAISE` |

Boundary markers filter Free Pascal runtime internals from stack traces so agents only see your code.

---

## How It Works

Cog invokes `cog-pascal` once per extension group. It expands the matched file
paths directly onto argv, and the binary processes each file sequentially.
Individual file failures are logged and converted into empty documents so the
rest of the batch still completes. As each file finishes, `cog-pascal` emits
structured progress events on stderr so Cog can advance its progress UI file by
file.

```
cog invokes:  bin/cog-pascal --output <output_path> <file_path> [file_path ...]
```

**Auto-discovery:**

| Step | Logic |
|------|-------|
| Workspace root | Walks up from each input file until a directory containing `.lpr`, `.dpr`, `.dpk`, `.lpi`, or `.dproj` is found (fallback: file parent directory). |
| Project name | Extracted from the first project file found (filename without extension). Falls back to workspace directory name. |
| Indexed target | Every file expanded from `{files}`; output is one SCIP protobuf containing one document per input file. |

### Architecture

```
src/
├── cogpascal.pas       # Entry point (CLI, orchestration)
├── analyzer.pas        # Pascal AST walker and symbol extraction
├── forms.pas           # DFM/LFM form file parser
├── symbols.pas         # SCIP symbol string builder
├── scip.pas            # SCIP protocol data structures and protobuf encoder
└── workspace.pas       # Project root discovery
```

Parsing uses a hand-written recursive descent parser with lookahead. Protobuf encoding is implemented locally with no external dependencies. The entire extension is self-contained Free Pascal with zero third-party units.

---

## Development

### Build from source

```sh
fpc -O2 -Mobjfpc -Sh src/cogpascal.pas -FUbin -FEbin -ocog-pascal
```

Produces the `cog-pascal` binary in `bin/`.

### Release

- Set the next version in `cog-extension.json`
- Tag releases as `vX.Y.Z` to match Cog's exact-version install flow
- Pushing a matching tag triggers GitHub Actions to verify the tag against `cog-extension.json` and create a GitHub Release
- Cog installs from the release source tarball, but the extension still builds locally after download

### Manual verification

```sh
fpc -O2 -Mobjfpc -Sh src/cogpascal.pas -FUbin -FEbin -ocog-pascal
./bin/cog-pascal --output /tmp/index.scip /path/to/file.pas /path/to/other.pas
```

---

<div align="center">
<sub>Built with <a href="https://www.freepascal.org">Free Pascal</a></sub>
</div>
