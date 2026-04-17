# Payloads — Payload Inspector Tab Views

Views for the Payloads tab, which provides a terminal-styled viewer for inspecting the last NDJSON payload sent per record type. Useful for demo verification and debugging.

## Files

| File | Description |
|---|---|
| `PayloadInspectorView.swift` | Main Payloads tab view. Features a record type picker, a metadata banner (record count, HTTP status, request headers), and a dark terminal-aesthetic scrollable list of NDJSON lines. Supports copy-to-clipboard for the full payload. |
| `NDJSONLineView.swift` | Displays a single NDJSON line with a truncated preview. Tapping a line expands it to show the full pretty-printed JSON. Uses monospace font for readability. |
