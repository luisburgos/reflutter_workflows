# reflutter_workflows

Shared composite GitHub Actions for Flutter app CI.

```
reflutter_workflows/
  magic-strings/
    action.yml                 ← composite action
    check-magic-strings.sh     ← tripwire script
  README.md
```

Reference an action by its directory path and pin a tag (see [Versioning](#versioning)).

## `magic-strings` — l10n tripwire

Fails CI on hardcoded user-facing strings in l10n-enforced dirs.

### Usage

```yaml
jobs:
  magic-strings:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - uses: luisburgos/reflutter_workflows/magic-strings@v0.1.0
        with:
          enforced-dirs: lib   # space-separated; default: lib
```

### Inputs

| Input               | Default                          | Description                                       |
| ------------------- | -------------------------------- | ------------------------------------------------- |
| `enforced-dirs`     | `lib`                            | Space-separated dirs to enforce.                  |
| `arb-path`          | `lib/shared/l10n/arb/app_en.arb` | ARB path shown in the failure's fix hint.         |
| `working-directory` | `.`                              | App root to check.                                |

### Coverage

Catches:

- `Text('…')`, `SelectableText('…')`
- `Tooltip(message: '…')`
- Single-quoted literals in named params: `hintText:`, `labelText:`, `errorText:`, `confirmLabel:`

Ignores:

- Interpolations — `Text('$x')`
- Lines marked `// l10n-ok`
- `*.g.dart`, `*_test.dart`, `gen/`

### Suppress a finding

Append `// l10n-ok` to a line that should stay hardcoded:

```dart
Text('v$buildNumber'); // l10n-ok
```

## Versioning

Pin an immutable tag, e.g. `@v0.1.0`.
