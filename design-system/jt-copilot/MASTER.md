# JT Copilot Design System

## Direction

Minimal desktop utility with a quiet graphite surface and one teal action color.
The floating widget should remain legible over any desktop content and must not
look like a chat landing page or a dashboard.

## Color Tokens

| Role | Value | Usage |
| --- | --- | --- |
| Canvas | `#0B1117` | Window foundation |
| Panel | `#FA131C25` | Floating surface |
| Panel solid | `#131C25` | Settings dialog |
| Raised | `#1B2732` | Inputs and secondary controls |
| Border | `#2B3A47` | Separation and focus |
| Text primary | `#F3F7FA` | Primary content |
| Text secondary | `#9BABB8` | Supporting content |
| Text tertiary | `#70808D` | Metadata |
| Accent | `#2DD4BF` | Active microphone and positive state |
| Accent strong | `#14B8A6` | Primary action surface |
| Accent ink | `#042F2E` | Content on accent |
| Danger | `#FB7185` | Recording active and destructive context |
| Warning | `#F4B860` | Recoverable faults |

Do not use purple gradients, decorative orbs, glass-only contrast, or multiple
competing accent colors.

## Typography

- Primary: Segoe UI Variable Text with Segoe UI fallback.
- Numeric timing: Cascadia Mono with Consolas fallback.
- Use sentence case.
- Keep metadata at 10-12 DIP and primary status at 15-16 DIP.
- Letter spacing stays at zero.

## Geometry

- Surface radius: 8 DIP maximum.
- Control radius: 6 DIP.
- Floating orb: `72 x 72` DIP.
- Icon controls: 32 DIP with at least 6 DIP internal padding.
- Primary microphone control: 56 DIP expanded, 48 DIP collapsed.
- Guidance panel: `820 x 260` DIP with a horizontal working surface.
- Guidance glass: outer radius `26`, inner module radius `14`, panel padding `12`,
  module gap `8`, module padding `12`.
- Default orb opacity: `78%`; default guidance opacity: `68%`.
- Keep fixed dimensions so status text and recording state cannot resize the
  widget.

## Interaction

- Hover transitions: 150-200 ms.
- No continuous pulse, shake, or decorative motion.
- Recording is communicated through state text, timer, muted-red status dot, stop
  icon, and live volume level.
- The floating widget never takes keyboard focus from the target application.
- The guidance panel is topmost and non-activating; it must never steal the
  document caret.
- Live recognition uses Unicode insertion with minimal backspace corrections.
- Settings is a normal keyboard-accessible window.
- Tooltips describe unfamiliar icon actions.

## State Rules

| State | Status | Accent |
| --- | --- | --- |
| Idle | Ready with current microphone | Teal |
| Recording | Listening with elapsed time and level | Coral |
| Captured | Saved with duration | Teal |
| Faulted | Actionable error without losing prior text | Amber |

Never show model chain-of-thought. Future panels show concise results only.

## Guidance Glass Tokens

The guidance panel uses one `NSVisualEffectView` as its only backdrop source.
All color and geometry values are centralized in `GlassTokens` and
`GlassMetrics`.

| Token | Dark value | Light value |
| --- | --- | --- |
| `--glass-blur` | `NSVisualEffectView(.popover)` | same |
| `--glass-tint` | `#26262A` at `0.56...0.66` | `#FFFFFF` at `0.58...0.72` |
| `--glass-border` | white `28%` | white `44%` |
| `--glass-highlight` | white `18%` | white `55%` |
| `--module-tint` | white `6.4%...8%` | white `30%...32%` |
| `--module-border` | white `22%` | white `52%` |
| `--panel-radius` | `26` | `26` |
| `--module-radius` | `14` | `14` |

Layer order:

1. Native behind-window blur.
2. Panel tint.
3. SVG `feTurbulence` noise at `4.5%` with overlay blending.
4. Outer border, inner lowlight, and top inset highlight.
5. Three-stop black shadow.

Module cards only use fill, border, and inset highlight. They never create a
second backdrop filter.

The panel responds to macOS Reduce Transparency by replacing blur and noise
with `#1C1C1E` (dark) or `#F2F2F7` (light), and module cards with `#2C2C2E`
or `#FFFFFF`. Reduce Motion removes the 220 ms scale/fade entrance.

Text tokens intentionally exceed the base vibrancy percentages where needed
for small-copy contrast: primary white `96%`, secondary white `78%`, tertiary
white `66%` in dark mode. In light mode, primary black `88%`, secondary black
`68%`, tertiary black `56%`.
