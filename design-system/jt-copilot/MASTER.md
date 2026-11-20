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
- Expanded widget: `372 x 166` DIP.
- Collapsed widget: `72 x 72` DIP.
- Icon controls: 32 DIP with at least 6 DIP internal padding.
- Primary microphone control: 56 DIP expanded, 48 DIP collapsed.
- Keep fixed dimensions so status text and recording state cannot resize the
  widget.

## Interaction

- Hover transitions: 150-200 ms.
- No continuous pulse, shake, or decorative motion.
- Recording is communicated through state text, timer, muted-red status dot, stop
  icon, and live volume level.
- The floating widget never takes keyboard focus from the target application.
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
