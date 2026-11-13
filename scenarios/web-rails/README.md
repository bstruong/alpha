# web-rails — shared Alpha web coding library

Single Rails 8 app used by `ruby-coding`, `frontend-coding`, and `hotwire-coding`.

## Product grading

Task verifiers use **Cuprite (Ferrum)** + headless Chromium. Source-only matches are not enough; the rendered page must behave correctly.

Set a Chrome binary if auto-detect fails:

```bash
export ALPHA_CHROME_PATH=~/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome
```

`bin/alpha doctor` reports whether a Chrome binary is visible.
