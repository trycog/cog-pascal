# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-03-27

### Added

- SCIP indexer for Pascal source files (.pas, .pp, .lpr, .dpr, .dpk, .inc)
- DFM/LFM form file parser with component hierarchy extraction
- Support for units, programs, and libraries with dotted names
- Class, record, interface, and enum type indexing with member extraction
- Function/procedure indexing with arity tracking
- Property, constant, variable, and resource string indexing
- Uses clause import tracking
- Scope tracking with enclosing symbols for nested definitions
- Qualified method implementation handling (TFoo.Method)
- Native DWARF debugger configuration with verified FPC runtime boundary markers
- Workspace auto-discovery from .lpr/.dpr/.dpk/.lpi/.dproj project files
- Structured progress reporting on stderr

[0.1.0]: https://github.com/trycog/cog-pascal/releases/tag/v0.1.0
