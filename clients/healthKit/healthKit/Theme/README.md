# Theme — Databricks Brand Design System

Centralizes all visual styling — colors, gradients, typography, and button styles — using the Databricks brand identity.

## Files

| File | Description |
|---|---|
| `DBXTheme.swift` | Defines the complete design system: `DBXColors` (brand colors: `dbxRed` #FF3621, `dbxDarkTeal` #1B3139, `dbxNavy` #0D2228, `dbxOrange` #FF6A33, `dbxGreen` #00A972, plus light/dark adaptive grays), `DBXGradients` (primary red-to-orange, dark background), `DBXTypography` (heroTitle 28pt, sectionHeader 20pt, stat 36pt, mono 12pt), and view modifiers (`.dbxCard()`, `.dbxGlassCard()`) for consistent card styling. Also includes `DatabricksWordmark` — a stylized text placeholder for the "databricks" logo (no external image assets). |
| `DBXButtonStyles.swift` | Custom SwiftUI button styles: `DBXPrimaryButtonStyle` (gradient background with scale animation on press) and `DBXSecondaryButtonStyle` (outlined with red border). |
