# Design System

## Overview

This design system is **Mac-first**. The current Mori macOS app is the source of truth for Mori’s visual identity. iPhone and iPad work should adapt that language, not invent a separate mobile style.

The current Mac app already defines the right product character:

- a **three-part workspace shell** centered on navigation and terminal work
- a **quiet, compact, developer-oriented sidebar language**
- **Ghostty-theme-backed window chrome with selective material**, not blanket card styling
- **small radii, tight spacing, and muted typography** that keep attention on the work
- **accent as selection and focus**, not decoration

Across iPhone, iPad, and Mac, Mori should feel like the same product scaled to different constraints:

- **Mac**: the canonical layout and interaction model
- **iPad**: the Mac workspace model adapted for touch and adaptive layouts
- **iPhone**: the same hierarchy and components compressed into single-column navigation

The goal is not a generic responsive consumer UI. The goal is a **portable native terminal workspace** with one consistent identity.

### Source-of-truth references from the current Mac app

These existing Mac patterns should drive cross-device consistency:

- `MainWindowController` + `TerminalAreaViewController`: the window, panels, and terminal surfaces inherit `GhosttyThemeInfo` for appearance and background color
- `ProjectRailView`: 36pt circular project avatars, ultra-thin-material rail, and muted icon-only footer tools
- `WorktreeSidebarView`: flat grouped project sections with uppercase headers, compact summary chips, divider-based structure, and dense nested rows
- `WorktreeRowView`: 28pt icon box, two-line rows, 7pt row radius, hover-reveal actions, and subdued git metadata
- `WindowRowView`: tiny state dot, active row tint, subtle shortcut pill, compact utility density, and hover preview behavior
- `AgentWindowRowView`: the same compact row geometry with semantic state color reserved for agent runtime state
- `SidebarFooterView`: divider-separated footer with icon-first utility actions and ephemeral shortcut hint overlays
- `MoriTokens`: current spacing, radius, icon, opacity, and typography scales

When in doubt, **start with the current Mac sidebar and rail patterns**, then adapt them for iPad and iPhone ergonomics.

## Colors

Color behavior should follow the current Mac app more closely than MoriRemote’s custom dark theme. Mori’s identity today comes from restrained neutral surfaces with accent-driven selection.

### Color strategy

- Use **semantic colors**, not ad hoc screen-specific colors.
- On **Mac**, preserve the current interaction model where selection tracks `Color.accentColor`.
- Window and panel backgrounds should follow the resolved **Ghostty theme background**; SwiftUI chrome should sit on top of that instead of inventing a separate app-level palette.
- On **iPhone** and **iPad**, introduce a shared Mori accent asset that visually matches Mac accent behavior rather than keeping a mobile-only accent language.
- Keep terminal-adjacent screens dark when appropriate, but avoid turning every surface into a neon terminal aesthetic.

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

- **Background Base**: Ghostty theme background or effective background for windows, panels, and terminal-adjacent surfaces
- **Background Material**: `.ultraThinMaterial` or equivalent system material for the project rail and similarly lightweight chrome surfaces
- **Row Hover**: muted color at roughly 8% opacity
- **Row Active**: accent at roughly 8–12% opacity
- **Divider**: subtle separator matching the current sidebar divider treatment
- **Muted Surface**: secondary at roughly 4–8% opacity for pills, shortcut hints, and subtle badges

#### Status colors

Use semantic status color only where the Mac app already does:

- **Success**: running or healthy state
- **Warning / Attention**: waiting for input, long-running, or caution states
- **Error**: failure or error state
- **Info**: unread output or informational signal
- **Muted**: inactive or default metadata

### Color rules

- Accent means **selected, active, or focused**.
- Neutral and muted colors mean **structural UI chrome**.
- Success, warning, error, and info should be reserved for **runtime state**, not decoration.
- Do not fill large surfaces with accent color.
- Do not introduce bright gradients, glow, or marketing-style color transitions.
- On mobile, if a dark custom surface is needed around the terminal, it should still preserve the Mac hierarchy: background → muted row or panel → active accent tint.

## Typography

Typography should follow the current Mac app’s compact, system-driven hierarchy.

### Font families

- **Primary UI font**: SF Pro Text / SF Pro Display (system)
- **Technical font**: system monospaced design / SF Mono

### Existing Mac-inspired scale

This section mirrors the current `MoriTokens` scale and should be reused cross-device unless a touch target requires a larger control.

- **Section Header**: 11pt bold, uppercase, tracking +1.2
- **Project Header / Group Title**: 14pt bold
- **Primary Row Title**: 13.5pt semibold
- **Window Row Title**: 12.5pt regular
- **Label**: 12pt (`caption`-like)
- **Caption**: 11pt (`caption2`-like)
- **Badge Count**: 9–9.5pt bold or semibold
- **Monospaced Branch**: 11pt monospaced
- **Monospaced Detail / Stats**: 10–10.5pt monospaced
- **Monospaced Shortcut Pill**: 10pt monospaced

### Typography rules

- Prioritize **small, crisp, high-density hierarchy** over large mobile-first type.
- Use **uppercase section headers** for navigation structure and grouped form sections.
- Use monospaced text for:
  - branches
  - window or session identifiers
  - shortcuts
  - technical status counts
  - ports, hosts, paths, and shell values
- Avoid oversized marketing-style headings in workspace screens.
- On iPhone, increase line height and hit area before increasing headline size.

## Elevation

The current Mac app is mostly flat. Keep it that way.

### Elevation model

- **Layer 0 — Window canvas**: system background or app background
- **Layer 1 — Structural chrome**: material rail, segmented header region, sidebars
- **Layer 2 — Interactive rows and pills**: hover tint, active tint, shortcut hint pills, compact grouped controls
- **Layer 3 — Popovers, sheets, and overlays**: pane previews, modals, transient overlays

### Elevation rules

- Prefer **material, tint, divider, and contrast** over shadow.
- Most surfaces should separate through **spacing and subtle opacity changes**, not card stacking.
- Use shadows only for popovers, floating overlays, and sheets.
- The terminal remains the deepest visual plane because of its content and darkness, not because it sits inside a heavy card.

## Components

### Design tokens

Cross-device work should reuse the current Mac token system as the foundation.

#### Spacing

Based on `MoriTokens.Spacing`:

- **1pt** `xxs`: hairline or internal micro spacing
- **2pt** `xs`: tight inline badge spacing
- **4pt** `sm`: compact gaps, pills, inner badge padding
- **8pt** `md`: default stack or row spacing
- **10pt** `lg`: section or group spacing, row rhythm
- **16pt** `xl`: main content inset
- **20pt** `xxl`: deeper indent or nested hierarchy offset
- **40pt** `emptyState`: top offset for empty states

#### Radius

Based on `MoriTokens.Radius` and current Mac usage:

- **3pt**: badge and shortcut tiny pills
- **7pt**: standard rows, hover and selection shapes, compact grouped surfaces
- **10pt**: previews, small cards, larger grouped controls
- **12–14pt**: mobile forms and larger touch-first controls only when needed

Rule: **default to the Mac app’s smaller radii**. Only increase radius on touch surfaces when it clearly improves usability.

### Layout

#### Core shell

The Mac app’s shell is the model:

1. **Project rail**
2. **Mode-aware sidebar**
3. **Workspace / terminal area**

Cross-device adaptations should preserve this mental model.

#### Mac

- Keep the current multi-column shell.
- The project rail remains narrow and icon-first.
- The sidebar remains structured, dense, and section-based.
- The workspace remains dominant.

#### iPad

- In regular width, iPad should be the closest match to Mac.
- Preferred structure:
  - server or workspace navigation at left
  - persistent context or sidebar when connected
  - terminal or workspace dominant at right
- Use larger touch hit areas, but preserve Mac grouping, typography, and hierarchy.
- Avoid turning everything into oversized cards.

#### iPhone

- Collapse the Mac shell into a single-column navigation flow.
- Preserve the same hierarchy by turning rail, sidebar, and workspace into navigation levels and contextual top bars.
- Keep row styling, section headers, and status language visually tied to Mac.

### Navigation

#### Mac-first navigation language

Use the current Mac app’s structural conventions as the base:

- uppercase section headers inside sidebars
- divider-separated project or group sections
- stable visible row selection
- footer utility actions with muted icons
- contextual utility affordances revealed on hover instead of always-on chrome

#### Cross-device navigation rules

- If a Mac surface uses a persistent sidebar, iPad should prefer a persistent sidebar in regular width.
- If persistence is impossible on iPhone, preserve context in the navigation title, subtitle, or top identity block.
- Avoid decorative navigation chrome. Mori navigation should feel operational and compact.

### Project rail

This is a defining Mac component and should inform cross-device identity.

#### Spec

- narrow vertical rail
- ultra-thin material background
- 36pt circular project avatars using a first letter or simple identity
- selected state uses interactive accent, unselected avatars use muted fill
- project label below avatar in small caption style
- footer utilities are icon-only, muted, and evenly spaced

#### Adaptation guidance

- iPad does not need a literal rail if that hurts usability, but it should preserve the same idea through a compact leading navigation column or project switcher.
- iPhone may collapse this into a project or server switcher list or menu, but should preserve icon-first project identity.

### Sidebars

Current Mac sidebars are mostly **flat, grouped lists**, not card stacks.

#### Sidebar structure

1. Top mode or header control when needed
2. Section label
3. Flat section groups separated by dividers
4. Dense rows for primary items
5. Nested rows indented beneath parent rows
6. Footer utility bar

#### Sidebar styling

- Prefer transparent or lightly tinted row backgrounds over heavy card blocks.
- Use 16pt horizontal padding for major headers and structure.
- Use 7pt row radii by default.
- Use subtle dividers between project and group sections.
- Reserve stronger tinting for compact summary chips and active-worktree callouts, not for the entire sidebar.

#### Mobile adaptation

- On iPad and iPhone, keep the row language and section structure.
- It is acceptable to wrap top identity blocks or forms in cards, but main navigation lists should still feel closer to the Mac sidebar than to a consumer settings app.

### Rows

Rows are the most important reusable element.

#### Worktree, server, session, and window row language

All of these should inherit the current Mac row model:

- compact vertical padding
- leading identity glyph, dot, or icon
- primary title plus secondary metadata
- optional trailing status, badge, or shortcut
- active state via accent-soft fill
- hover state via muted-soft fill
- 7pt row radius
- preserve row geometry when badges, quick-reply affordances, or hover actions appear

#### Row state rules

- **Default**: transparent or muted surface
- **Hover**: muted tint
- **Selected**: accent-soft background, accent foreground where useful
- **Busy**: swap the leading icon for a spinner while preserving row geometry
- **Attention / Error**: add a trailing semantic badge or icon; do not redraw the whole row as warning or error unless necessary

### Window rows and badges

Mirror the current Mac `WindowRowView` behavior:

- tiny leading state dot indicates active, type, or runtime state
- title stays compact
- trailing shortcut pill is subtle, never dominant
- badge icons communicate running, waiting, error, unread, or completed
- hover can reveal richer preview or popover behavior on Mac and iPad pointer platforms, but core information must remain visible without hover

### Cards and panels

Cards should be used more sparingly than in the current mobile UI.

#### Mac-based rule

If the current Mac app would render something as a flat grouped list or sidebar section, do **not** turn it into a large rounded card on iPad or iPhone by default.

#### Appropriate card use

Use cards or panels for:

- forms
- empty states in detail panes
- transient error blocks
- top identity summaries when needed on mobile
- floating overlays over terminal content

#### Card style

- small-to-medium radius
- subtle border or material separation
- low or no shadow
- compact internal spacing

### Forms

Forms should evolve from the current Mac sidebar and detail density, not from generic iOS settings screens.

#### Rules

- Group inputs into clearly labeled uppercase sections.
- Keep forms narrow even on large screens.
- Use compact field heights and spacing.
- Prefer one-column forms across all devices.
- Place the primary action at the bottom of the form or in the sheet footer.

#### Field style

- low-chrome field background
- subtle border or divider
- accent or focus treatment only on the active field
- monospaced text only for technical values when useful

### Buttons

Button styling should follow the Mac app’s restraint.

#### Primary button

- accent-filled background
- dark or high-contrast text depending on accent
- simple rounded rectangle
- no large shadows or glossy effects

#### Secondary button

- plain or softly bordered / tinted
- used for edit and manage actions

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

Use the current Mac app’s restraint as the benchmark.

### Status and messaging

Current Mac patterns already provide the right model: small semantic icons, grouped sections, and compact inline indicators.

#### Status hierarchy

- **Selection / focus**: accent
- **Running / healthy**: success
- **Waiting / attention**: attention or warning
- **Error**: error
- **Unread / info**: info
- **Inactive metadata**: muted

#### Messaging rules

- Prefer inline message blocks over modal alerts when context matters.
- Keep titles short and direct.
- Show technical detail only after a plain-language summary.
- On mobile, bottom banners can be used for transient, dismissible errors, but longer technical problems should use inline panels or detail states.

### Terminal and shell surfaces

The terminal is still Mori’s main workspace, and the current Mac app ties it directly to Ghostty theme resolution.

#### Rules

- The terminal should remain the dominant workspace plane.
- Window, panel, and terminal-adjacent surfaces should inherit the resolved Ghostty appearance before any custom styling is applied.
- Overlays above the terminal should be compact and low-chrome.
- Sidebar and context surfaces adjacent to the terminal should feel like extensions of the Mac sidebar system.
- Avoid making the mobile terminal experience feel like a different brand from the Mac app.

### Motion

Follow the Mac app’s understated feel:

- quick fade and opacity transitions
- short hover animations
- low-bounce selection transitions
- no playful spring motion in core navigation

## Do’s and Don’ts

### Do

- Do treat the current Mac app as the canonical Mori design language.
- Do reuse `MoriTokens` spacing, radius, and typography as the basis for iPad and iPhone work.
- Do keep sidebars flat, structured, and dense.
- Do make active and selected state look consistent across project rows, worktree rows, server rows, and tmux rows.
- Do preserve the Mac shell mental model even when layouts collapse on smaller devices.
- Do use semantic status colors the same way the Mac app already uses them.
- Do favor small radii, subtle dividers, muted metadata, and selective accent.

### Don’t

- Don’t let MoriRemote define a separate visual identity from Mori for Mac.
- Don’t replace Mac-style grouped sidebars with stacks of oversized mobile cards.
- Don’t introduce a stronger or more decorative color language than the current Mac app already has.
- Don’t use heavy shadows, large blur panels, or over-rounded controls as the default style.
- Don’t scale typography so far up on iPad or iPhone that the product stops feeling like Mori.
- Don’t use accent as decoration instead of selection or focus.
- Don’t design disconnected, server, or tmux states as if they belong to a different app than the Mac workspace browser.

## Implementation Guidance

Use this document to guide follow-up implementation work in this order:

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
