---
name: Linqo
description: A cheerful bookmark companion for a private library.
colors:
  canvas: "#F8F4FF"
  surface: "#FFFFFF"
  ink: "#30134D"
  muted: "#705E82"
  purple: "#7435C9"
  lavender: "#EAD9FF"
  mint: "#9AF1CE"
  yellow: "#FFDB79"
  pink: "#F3B3DD"
  lilac: "#DCC5FA"
  note: "#E8DAFF"
  container-low: "#F2EAFB"
  container: "#F0E5FC"
  outline: "#9C86AE"
  outline-variant: "#E5D7F3"
  secondary: "#27684E"
  on-mint: "#173F30"
  on-yellow: "#503A15"
  error: "#B12450"
  dark-canvas: "#191121"
  dark-surface: "#281D36"
  dark-container-low: "#21172E"
  dark-container: "#30223F"
  dark-container-highest: "#3C2B4E"
  dark-ink: "#F8F0FF"
  dark-muted: "#CEBDDD"
  dark-primary: "#C59AFF"
  dark-primary-container: "#4B2C68"
  dark-on-primary-container: "#F2E4FF"
  dark-secondary-container: "#234C3D"
  dark-on-secondary-container: "#D0FFE9"
  dark-tertiary-container: "#5A4729"
  dark-on-tertiary-container: "#FFE4A0"
  dark-outline: "#9680AA"
  dark-outline-variant: "#4C3A5F"
  dark-error: "#FFAFC4"
typography:
  headline-large:
    fontFamily: Fredoka
    fontSize: "34px"
    fontWeight: 600
    letterSpacing: "-0.4px"
  headline-medium:
    fontFamily: Fredoka
    fontSize: "28px"
    fontWeight: 600
  headline-small:
    fontFamily: Fredoka
    fontSize: "24px"
    fontWeight: 500
  title-large:
    fontFamily: Fredoka
    fontSize: "21px"
    fontWeight: 500
  title-medium:
    fontFamily: Nunito
    fontSize: "16px"
    fontWeight: 800
    lineHeight: 1.3
  title-small:
    fontFamily: Nunito
    fontSize: "14px"
    fontWeight: 800
  body-large:
    fontFamily: Nunito
    fontSize: "16px"
    fontWeight: 500
    lineHeight: 1.5
  body-medium:
    fontFamily: Nunito
    fontSize: "14px"
    fontWeight: 500
    lineHeight: 1.45
  body-small:
    fontFamily: Nunito
    fontSize: "13px"
    fontWeight: 500
    lineHeight: 1.4
  label-large:
    fontFamily: Nunito
    fontSize: "15px"
    fontWeight: 800
  label-medium:
    fontFamily: Nunito
    fontSize: "13px"
    fontWeight: 800
  label-small:
    fontFamily: Nunito
    fontSize: "11px"
    fontWeight: 700
rounded:
  card: "28px"
  field: "20px"
  button: "22px"
  chip: "15px"
  floating-action: "24px"
  snackbar: "18px"
spacing:
  compact: "8px"
  grid-gap: "12px"
  standard: "16px"
  field-inset: "18px"
  panel-inset: "20px"
  page-inset: "24px"
  page-bottom: "32px"
components:
  button-primary:
    backgroundColor: "{colors.purple}"
    textColor: "{colors.surface}"
    typography: "{typography.label-large}"
    rounded: "{rounded.button}"
    height: "54px"
    padding: "0px 24px"
  button-outlined:
    textColor: "{colors.purple}"
    typography: "{typography.label-large}"
    rounded: "{rounded.button}"
    height: "50px"
  field:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    rounded: "{rounded.field}"
    padding: "18px"
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.card}"
  chip:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.ink}"
    typography: "{typography.label-large}"
    rounded: "{rounded.chip}"
    padding: "8px 10px"
  chip-selected:
    backgroundColor: "{colors.lavender}"
    textColor: "{colors.ink}"
    rounded: "{rounded.chip}"
  navigation:
    backgroundColor: "{colors.surface}"
    textColor: "{colors.muted}"
    typography: "{typography.label-medium}"
---

# Design System: Linqo

## Overview

**Creative North Star: "The Cheerful Bookmark Companion"**

The supplied cheerful bookmark collector is the current visual authority. The user explicitly replaced the earlier pink meal-planner direction; this document records the implemented mascot identity in version 0.4.0+4. Pale lavender, purple ink, rounded lettering and bookmark-colored accents make the private library welcoming within familiar Android navigation.

The full supplied lockup belongs on startup. A faithful text-free mascot appears in the launcher, compact header and selected empty states. Populated libraries give saved content priority. Artwork stays colorful in dark mode while surrounding surfaces and text adapt for legibility.

**Key Characteristics:**
- Supplied mascot artwork with purpose-specific placement.
- Purple actions, lavender ground and pastel bookmark accents.
- Fredoka headings paired with readable Nunito text.
- Flat rounded surfaces and labelled native navigation.
- Restrained motion that respects reduced-motion settings.

Ground truth: `lib/theme.dart`, `lib/ui/brand.dart`, `lib/ui/components.dart`, `lib/ui/library_shell.dart`, `lib/ui/settings_screen.dart`, `lib/ui/save_editor.dart` and `pubspec.yaml`. Direction contract: `docs/MASCOT_REBRAND_UI_BRIEF.md`. Frontmatter uses CSS-compatible px notation; Flutter renders logical pixels and supports native text scaling.

## Colors

The logo palette becomes a lavender workspace with deep purple actions and mint, yellow and blush bookmark accents. Frontmatter owns exact values.

### Primary
- **Bookmark Purple** (`purple`): light-theme actions, selection, cursor and progress.
- **Soft Lavender** (`lavender`): light primary containers, selected navigation/chips and pastel covers.
- **Night Lavender** (`dark-primary`): dark-theme actions with the corresponding dark container and foreground tokens.

### Secondary
- **Fresh Mint** (`mint`): place covers, light secondary containers and dark-theme secondary foreground.
- **Leaf Ink** (`secondary`, `on-mint`): light secondary text and container foreground.

### Tertiary
- **Bookmark Yellow** (`yellow`): recipe covers and light tertiary containers; use on-yellow for container text.
- **Blush Pink** (`pink`), **Lilac Paper** (`lilac`) and **Note Paper** (`note`): file, link and note fallback covers. Pastel covers keep deep ink in both themes.
- **Error Berry** (`error`, `dark-error`): semantic failures rather than decoration.

### Neutral
- **Lavender Ground** (`canvas`), **White Paper** (`surface`) and container tokens separate the library and panels.
- **Purple Ink** (`ink`) and **Quiet Violet** (`muted`) distinguish primary and supporting text.
- Outline tokens provide subtle boundaries; dark counterparts accompany dark canvas, surfaces and container levels.

### Named Rules
**The Artwork Integrity Rule.** Preserve the supplied artwork's colors and proportions; use the full lockup for startup and the text-free mascot for the launcher.

## Typography

**Display Font:** Fredoka, bundled locally.
**Body Font:** Nunito, bundled locally; Flutter platform fallback handles unsupported glyphs.

Rounded headings echo the logo while Nunito keeps working text readable. Both font files and OFL notices ship offline; there is no runtime font request.

### Hierarchy
- **Headlines:** large for library/search headings, medium for intermediate hierarchy, small for empty states and the settings welcome.
- **Titles:** Fredoka title-large for app bars and section titles; Nunito title-medium/title-small for saved items and compact hierarchy.
- **Body:** large for reading, medium for general text, small for secondary metadata.
- **Labels:** large for actions/chips, medium for navigation, small for compact metadata. Inherit Material line-height where the theme supplies none.

### Named Rules
**The Two Voices Rule.** Use Fredoka for welcoming hierarchy and Nunito for working text; preserve the bundled pairing.

## Layout

Library, Collections and Search are peers. Phones use labelled bottom navigation; widths from 840 logical pixels use a labelled navigation rail. The compact brand header preserves access to settings. The floating Save action remains available in an empty library; the processing strip keeps Stop accessible below the header.

Page insets generally use page-inset with compact header adjustments. Library/collection content caps at 1240 logical pixels; settings at 720 and save editing at 680, with its footer at 632. Library grids use two to four columns with grid-gap gutters; larger text switches browsing to a list. Appearance controls wrap; library type filters scroll horizontally. Preserve safe areas and clearance for floating Save.

Editing and detail use routes. The editor pins Save above the keyboard in a safe-area footer; metadata arrival must not move the action or overwrite edited titles. Panel padding follows each component's purpose rather than one universal card inset.

## Elevation & Depth

Tone, spacing and subtle outlines create separation. Cards, bottom navigation and floating Save have zero resting elevation; the app bar has zero scrolled-under elevation. Card borders use outline-variant at 60% alpha. Native Material pressed/focus overlays and dialogs remain in use; no custom shadow vocabulary is established.

### Named Rules
**The Paper Surface Rule.** Build hierarchy with tonal surfaces and readable boundaries; do not add decorative hard offset shadows to this soft stationery world.

## Shapes

Cards, dialogs and the library search shortcut share card rounding. Fields, buttons, chips, floating Save and snackbars use their dedicated radius tokens. Kind badges are circles. Compact preview thumbnails have smaller clipping. Icon/text actions retain minimum 48 logical-pixel targets; primary/outlined actions are taller.

## Components

### Buttons
Rounded, substantial and direct. Primary uses primary/on-primary, label-large, button rounding and a minimum height matching its token. Outlined uses the theme outline; text and icon buttons retain minimum 48 logical-pixel targets. Material supplies enabled, disabled, hover, focus and pressed states. Floating Save has no resting elevation.

### Chips
Surface at rest, primary-container when selected, with outline-variant boundaries and label-large text. Selection uses both foreground and container treatment. Appearance controls wrap and library filters scroll horizontally.

### Cards / Containers
Flat surface panels have rounded clipping and faint outlines. Settings uses panel-inset padding; save cards have distinct compact/grid layouts and bounded previews. Cached photography takes precedence over fallback covers. Missing covers use kind accents and deep ink; video covers expose an external-open play action.

### Inputs / Fields
Filled surface fields use outline-variant strokes (1.3 logical pixels), field rounding and field-inset padding. Focus changes the stroke to primary at 2 logical pixels. Labels/hints use on-surface-variant; errors use Material semantic behavior. The library search shortcut is a larger rounded surface; Search itself uses the field component.

### Navigation
Library, Collections and Search keep visible labels and selected icons. Bottom selection uses primary-container with primary text/icons; unselected content uses on-surface-variant. Wide rails retain labels and Settings remains a header action.

### Mascot and startup
The header combines a compact mascot with a lowercase Fredoka wordmark. Flutter startup centers the full supplied asset on lavender at the smaller of 260 logical pixels or 66% viewport width. Its scale entrance lasts 220 ms, ease-out cubic, and becomes immediate with reduced motion. This defines animation rather than measured startup duration. Empty-library artwork is larger; search misses and errors retain useful semantic icons.

Routes use a 180 ms fade and slight vertical slide (0.025 route height), ease-out cubic, disabled with reduced motion. No decorative looping motion is established.

## Do's and Don'ts

### Do:
- **Do** preserve the supplied full logo at startup and text-free mascot in the launcher.
- **Do** pair Fredoka hierarchy with bundled Nunito working text.
- **Do** retain labelled navigation, keyboard-safe Save and minimum 48 logical-pixel action targets.
- **Do** verify dark mode, narrow layouts and increased text size when extending a screen.
- **Do** preserve original source text, evidence and interruptible processing alongside browsing.

### Don't:
- **Don't** restore the superseded pink meal-planner reference as current visual authority.
- **Don't** recolor or distort the mascot or crowd populated libraries with repeated full lockups.
- **Don't** fetch thumbnails during browsing or add decorative looping motion.
- **Don't** turn fixture screenshots or animation durations into physical-device or startup-performance claims.

