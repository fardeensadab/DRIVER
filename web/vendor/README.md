# Vendored bower packages

These folders replace bower packages whose GitHub repositories no longer exist,
so `bower install` (run while building the `driver-web` Docker image) can finish.
They were added by the local install patch set (see `INSTALL-NOTES.md` at the
repository root).

| Folder | Replaces | Source of the code |
|---|---|---|
| `angular-uuid/` | `ajsd/angular-uuid` ~0.1 (module `uuid`, service `uuid4`) | Small re-implementation with the same API (`generate()`, `validate()`) |
| `ng-debounce/` | `shahata/angular-debounce` ^0.1.7 (module `debounce`) | Built copy published on npm as `ng-debounce@1.0.1` (MIT) |
| `file-saver.js/` | `Teleborder/FileSaver.js` 1.20150507.2 (needed by `angular-file-saver`) | `eligrey/FileSaver.js` at commit `babc6d9` (2015-05-07, MIT) |

`angular-uuid` and `ng-debounce` are referenced as local paths in `web/bower.json`.
`file-saver.js` is a dependency of a dependency, so the Dockerfile turns it into a
local git repository and points git at it with `url.<path>.insteadOf`.
