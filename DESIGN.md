# Design System

## Overview

This design system is **Mac-first**. The current Mori macOS app is the source of truth for Mori’s visual identity, and iPhone/iPad work should adapt that language rather than invent a parallel mobile style.

The current Mac app already establishes the right product character:

- a **three-part workspace shell** built around navigation and terminal work
- a **quiet, compact, developer-oriented sidebar language**
- **thin-material and low-chrome surfaces** instead of heavy cards or large shadows
- **small radii, tight spacing, and muted typography** that keep attention on the work
- **accent as selection/focus**, not decoration

Across iPhone, iPad, and Mac, Mori should feel like the same product scaled to different constraints:

- **Mac** = canonical layout and interaction language
- **iPad** = Mac’s workspace model, simplified for touch and adaptive layouts
- **iPhone** = the same hierarchy and component language, compressed into single-column navigation

The goal is not “responsive consumer UI.” The goal is a **portable native terminal workspace** with one identity.

### Source-of-truth references from the current Mac app

These existing Mac patterns should drive cross-device consistency:

- `ProjectRailView`: narrow project rail, circular project avatars, low-emphasis footer tools, material background
- `SidebarContainerView`: segmented mode switcher (`Workspaces`, `Tasks`, `Agents`) at top
- `WorktreeSidebarView`: flat grouped sidebar sections with uppercase headers and divider-based structure
- `WorktreeRowView`: compact two-line rows, small rounded rectangles, hover reveal actions, subdued metadata
- `WindowRowView`: tiny state dot, active row tint, small shortcut pill, compact utility density
- `AgentSidebarView`: state-grouped sections, muted headers, selective semantic color for status
- `MoriTokens`: current spacing, radius, icon, and typography scales

When in doubt, **borrow from the current Mac sidebar and rail first**, then adapt to iPad/iPhone ergonomics.

## Colors

Color behavior should follow the current Mac app’s logic more than MoriRemote’s current custom dark theme. The main product identity today comes from the Mac app’s restrained neutral surfaces plus accent-driven selection.

### Color strategy

- Use **semantic colors**, not ad hoc screen-level colors.
- On **Mac**, preserve the current behavior where interactive selection tracks `Color.accentColor`.
- On **iPhone/iPad**, introduce a shared Mori accent asset that visually matches the Mac accent behavior rather than keeping a separate mobile-only accent language.
- Keep terminal-adjacent screens dark, but avoid making every surface a fully custom “neon terminal” aesthetic.

### Semantic palette

#### Core interactive colors

- **Interactive Accent**: source of truth is the current Mac app’s `Color.accentColor`
  - usage: selected project avatar, selected row tint, active dots, primary toggles, focused shortcuts
- **Interactive Accent Soft**: accent at 8–12% opacity
  - usage: selected row backgrounds, active pills, subtle focus regions
- **Interactive Accent Border**: accent at 20–35% opacity
  - usage: active row outlines, selected borders, emphasized inline states

#### Neutral UI colors

These should follow current Mac semantics rather than strong custom fills:

- **Background Base**: window/sidebar canvas using system background/material behavior
- **Background Material**: `.ultraThinMaterial` or equivalent system material for rails and light chrome surfaces
- **Row Hover**: secondary/muted color at ~8% opacity
- **Row Active**: accent at ~8–12% opacity
- **Divider**: subtle separator matching current sidebar divider treatment
- **Muted Surface**: secondary at ~4–8% opacity for pills, shortcut hints, subtle badges

#### Status colors

Use semantic status color only where the Mac app already does:

- **Success**: running/healthy state
- **Warning / Attention**: waiting for input, long-running, caution states
- **Error**: failure/error state
- **Info**: unread output / informational signal
- **Muted**: inactive/default metadata

### Color rules

- Accent means **selected, active, or focused**.
- Neutral/muted means **structural UI chrome**.
- Success/warning/error/info should be reserved for **runtime state**, not general decoration.
- Do not fill large surfaces with accent color.
- Do not introduce bright gradients, glow, or marketing-style color transitions.
- On mobile, if a dark custom surface is needed around the terminal, it should still inherit the Mac hierarchy: background → muted row/panel → active accent tint.

## Typography

Typography should follow the current Mac app’s compact system-driven hierarchy.

### Font families

- **Primary UI font**: SF Pro Text / SF Pro Display (system)
- **Technical font**: system monospaced design / SF Mono

### Existing Mac-inspired scale

This section intentionally mirrors the current `MoriTokens` scale and should be reused cross-device unless a touch target requires a larger control.

- **Section Header**: 11pt bold, uppercase, tracking +1.2
- **Project Header / Group Title**: 14pt bold
- **Primary Row Title**: 13.5pt semibold
- **Window Row Title**: 12.5pt regular
- **Label**: 12pt (`caption`-like)
- **Caption**: 11pt (`caption2`-like)
- **Badge Count**: 9–9.5pt bold/semibold
- **Monospaced Branch**: 11pt monospaced
- **Monospaced Detail / Stats**: 10–10.5pt monospaced
- **Monospaced Shortcut Pill**: 10pt monospaced

### Typography rules

- Prioritize **small, crisp, high-density hierarchy** over large mobile-first type.
- Use **uppercase section headers** for navigation structure and grouped form sections.
- Use monospaced text for:
  - branches
  - window/session identifiers
  - shortcuts
  - technical status counts
  - ports, hosts, paths, shell values
- Avoid oversized marketing-style headings in workspace screens.
- On iPhone, increase line height and hit area before increasing headline size.

## Elevation

The current Mac app is mostly flat. Keep that.

### Elevation model

- **Layer 0 — Window canvas**: system background / app background
- **Layer 1 — Structural chrome**: material rail, segmented header region, sidebars
- **Layer 2 — Interactive rows/pills**: hover tint, active tint, shortcut hint pills, compact grouped controls
- **Layer 3 — Popovers/sheets/overlays**: pane previews, modals, transient overlays

### Elevation rules

- Prefer **material, tint, divider, and contrast** over shadow.
- Most surfaces should separate via **spacing and subtle opacity changes**, not card stacking.
- Use shadows only for popovers, floating overlays, and sheets.
- The terminal remains the deepest visual plane because of content and darkness, not because it is boxed into a card.

## Components

### Design tokens

Cross-device work should reuse the current Mac token system as the foundation.

#### Spacing

Based on `MoriTokens.Spacing`:

- **1pt** `xxs`: hairline/internal micro spacing
- **2pt** `xs`: tight inline badge spacing
- **4pt** `sm`: compact gaps, pills, inner badge padding
- **8pt** `md`: default stack/row spacing
- **10pt** `lg`: section/group spacing, row rhythm
- **16pt** `xl`: main content inset
- **20pt** `xxl`: deeper indent / nested hierarchy offset
- **40pt** `emptyState`: top offset for empty states

#### Radius

Based on `MoriTokens.Radius` and current Mac usage:

- **3pt**: badge/shortcut tiny pills
- **7pt**: standard rows, hover/selection shapes, compact grouped surfaces
- **10pt**: previews, small cards, larger grouped controls
- **12–14pt**: mobile forms and larger touch-first controls only when needed

Rule: **default to the Mac app’s smaller radii**. Only grow radii on touch surfaces where it improves usability.

### Layout

#### Core shell

The Mac app’s shell is the model:

1. **Project rail**
2. **Mode-aware sidebar**
3. **Workspace / terminal area**

Cross-device adaptations should preserve this mental model.

#### Mac

- Keep the current multi-column shell.
- Project rail remains narrow and icon-first.
- Sidebar remains structured, dense, and section-based.
- Workspace remains dominant.

#### iPad

- In regular width, iPad should be the closest match to Mac.
- Preferred structure:
  - server or workspace navigation at left
  - persistent context/sidebar when connected
  - terminal/workspace dominant at right
- Use larger touch hit areas, but preserve Mac grouping, typography, and hierarchy.
- Avoid converting everything into oversized cards.

#### iPhone

- Collapse the Mac shell into a single-column navigation flow.
- Preserve the same hierarchy by turning rail/sidebar/workspace into navigation levels and contextual top bars.
- Keep row styling, section headers, and status language visually tied to Mac.

### Navigation

#### Mac-first navigation language

Use the current Mac app’s structural conventions as the basis:

- top-level mode switcher via segmented control when multiple operational views exist
- uppercase section headers inside sidebars
- divider-separated project/group sections
- stable visible selection in rows
- footer utility actions with muted icons

#### Cross-device navigation rules

- If a Mac surface uses a persistent sidebar, iPad should prefer a persistent sidebar in regular width.
- If persistence is impossible on iPhone, preserve context in the navigation title/subtitle or top identity block.
- Avoid decorative navigation chrome. Mori navigation should feel operational and compact.

### Project rail

This is a Mac-defining component and should inform cross-device identity.

#### Spec

- Narrow vertical rail
- Material background
- Circular project avatars using first letter / simple identity
- Selected state uses interactive accent
- Project label below avatar in small caption style
- Footer utilities are icon-only, muted, evenly spaced

#### Adaptation guidance

- iPad does not need a literal rail if that harms usability, but should preserve the same idea through a compact leading navigation column or project switcher.
- iPhone may collapse this into a project/server switcher list or menu, but should preserve icon-first project identity.

### Sidebars

Current Mac sidebars are mostly **flat, grouped lists**, not card stacks.

#### Sidebar structure

1. Top mode/header control if needed
2. Section label
3. Flat section groups separated by dividers
4. Dense rows for primary items
5. Nested rows indented beneath parent rows
6. Footer utility bar

#### Sidebar styling

- Prefer transparent or lightly tinted row backgrounds over heavy card blocks.
- Use 16pt horizontal padding for major headers and structure.
- Use 7pt row radii by default.
- Use hover reveal affordances on pointer platforms.
- Use subtle dividers between project/group sections.

#### Mobile adaptation

- On iPad/iPhone, keep the row language and section structure.
- It is acceptable to wrap top identity blocks or forms in cards, but main navigation lists should still feel closer to the Mac sidebar than to a consumer settings app.

### Rows

Rows are the most important reusable element.

#### Worktree/server/session/window row language

All of these should inherit the current Mac row model:

- compact vertical padding
- leading identity glyph/dot/icon
- primary title + secondary metadata
- optional trailing status/badge/shortcut
- active state via accent-soft fill
- hover state via muted-soft fill
- small radius

#### Row state rules

- **Default**: transparent or muted surface
- **Hover**: muted tint
- **Selected**: accent-soft background, accent foreground where useful
- **Busy**: swap leading icon for spinner, preserve row geometry
- **Attention/Error**: add trailing semantic badge/icon, do not redraw the whole row as warning/error unless necessary

### Window rows and badges

Mirror the current Mac `WindowRowView` behavior:

- tiny leading state dot indicates active/type/runtime state
- title stays compact
- trailing shortcut pill is subtle, never dominant
- badge icons communicate running, waiting, error, unread, completed
- hover can reveal richer preview/popover behavior on Mac/iPad pointer, but core information must remain visible without hover

### Cards and panels

Cards should be used more sparingly than in the current mobile UI.

#### Mac-based rule

If the current Mac app would render something as a flat grouped list or sidebar section, do **not** turn it into a large rounded card on iPad/iPhone by default.

#### Appropriate card use

Use cards/panels for:

- forms
- empty states in detail panes
- transient error blocks
- top identity summaries when needed on mobile
- floating overlays over terminal content

#### Card style

- small-to-medium radius
- subtle border or material separation
- low/no shadow
- compact internal spacing

### Forms

Forms should evolve from the current Mac sidebar/detail density, not generic iOS settings screens.

#### Rules

- Group inputs into clearly labeled uppercase sections
- Keep forms narrow even on large screens
- Use compact field heights and spacing
- Prefer one-column forms across all devices
- Primary action sits at the bottom of the form or in the sheet footer area

#### Field style

- low-chrome field background
- subtle border/divider
- accent/focus treatment only on active field
- monospaced text only for technical values where useful

### Buttons

Button styling should follow the Mac app’s restraint.

#### Primary button

- use accent-filled background
- dark or high-contrast text depending on accent
- simple rounded rectangle
- no large shadows or glossy effects

#### Secondary button

- plain or softly bordered/tinted
- used for edit/manage actions

#### Utility button

- icon-first
- often plain style on Mac
- muted by default, accent only when active

#### Mobile adaptation

- Increase height and padding for touch targets, but keep the visual language plain and compact.
- Avoid oversized filled button bars unless the action is truly primary.

### Empty states

Empty states should look like they belong in the Mac app.

#### Structure

- muted symbol
- concise title
- one-sentence explanation
- one clear action

#### Tone

- straightforward
- operational
- calm
- not playful or promotional

Use the current Mac app’s empty-state restraint as the benchmark.

### Status and messaging

Current Mac patterns already provide the right model: small semantic icons, grouped sections, and compact inline indicators.

#### Status hierarchy

- **Selection/focus**: accent
- **Running/healthy**: success
- **Waiting/attention**: attention/warning
- **Error**: error
- **Unread/info**: info
- **Inactive metadata**: muted

#### Messaging rules

- Prefer inline message blocks over modal alerts when context matters.
- Keep titles short and direct.
- Show technical detail only after a plain-language summary.
- On mobile, bottom banners can be used for transient dismissal-friendly errors, but longer technical problems should use inline panels or detail states.

### Terminal and shell surfaces

The terminal is still Mori’s main workspace, but cross-device design should anchor it back to the Mac product language.

#### Rules

- The terminal should remain the dominant workspace plane.
- Overlays above the terminal should be compact and low-chrome.
- Sidebar/context surfaces adjacent to terminal should feel like extensions of the Mac sidebar system.
- Avoid making the mobile terminal experience look like a separate brand from the Mac app.

### Motion

Follow the Mac app’s understated feel:

- quick fade/opacity transitions
- short hover animations
- low-bounce selection transitions
- no playful spring motion in core navigation

## Do's and Don'ts

### Do

- Do treat the current Mac app as the canonical Mori design language.
- Do reuse `MoriTokens` spacing, radius, and typography as the basis for iPad/iPhone work.
- Do keep sidebars flat, structured, and dense.
- Do make active/selected state look the same across project rows, worktree rows, server rows, and tmux rows.
- Do preserve the Mac shell mental model even when layouts collapse on smaller devices.
- Do use semantic status colors the same way the Mac app already uses them.
- Do favor small radii, subtle dividers, muted metadata, and selective accent.

### Don't

- Don’t let MoriRemote define a separate visual identity from Mori for Mac.
- Don’t replace Mac-style grouped sidebars with stacks of oversized mobile cards.
- Don’t introduce a stronger or more decorative color language than the current Mac app already has.
- Don’t use heavy shadows, large blur panels, or over-rounded controls as the default style.
- Don’t scale typography up so much on iPad/iPhone that the product stops feeling like Mori.
- Don’t use accent as decoration instead of selection/focus.
- Don’t design disconnected, server, and tmux states as if they belong to a different app than the Mac workspace browser.

## Implementation Guidance

Use this document to drive follow-up implementation work in this order:

1. **Token alignment first**
   - align `MoriRemote/Theme.swift` with `Packages/MoriUI/Sources/MoriUI/DesignTokens.swift`
   - introduce shared semantic tokens derived from Mac usage
2. **Row consistency second**
   - make server rows, tmux window rows, and worktree rows share one state model
3. **Sidebar consistency third**
   - adapt iPad and iPhone navigation to feel like Mac sidebars, not standalone mobile screens
4. **Card reduction fourth**
   - remove unnecessary large card styling where Mac would use grouped lists
5. **Status and empty-state normalization last**
   - unify wording, badge shape, icon treatment, and inline message patterns across all devices
