# Visual Design System

## Design Thesis

Sudoku Duel uses calm competitive intelligence: quiet surfaces, clear score hierarchy, restrained motion, and reward color only where value is exchanged.

## Color Tokens

| Role | Light | Dark |
| --- | --- | --- |
| background | `#F6F8F9` | `#0E1518` |
| surface | `#FFFFFF` | `#121C20` |
| surfaceContainerLow | `#F0F4F5` | `#162126` |
| surfaceContainer | `#E9EFF1` | `#19262B` |
| surfaceContainerHigh | `#E1E8EA` | `#213138` |
| primary | `#176B63` | `#73D7C6` |
| primaryContainer | `#D7F2EC` | `#164C46` |
| secondary | `#526575` | `#B6C7D5` |
| tertiary | `#6657B8` | `#B9AAFF` |
| reward | `#A66F12` | `#F1C45B` |
| success | `#287859` | `#64D3A2` |
| error | `#B83A3A` | `#FFB4AB` |
| onSurface | `#172126` | `#E7F0F2` |
| onSurfaceVariant | `#59676D` | `#A9B8BD` |

`GameColors` extends the Flutter theme with success, reward, local player, opponent player, warning, and timer-critical roles. Screens should consume semantic theme roles rather than hardcoded colors.

## Typography

- System font remains the default for body, controls, forms, and dense UI.
- Display and title weights are strong but compact.
- Sudoku numbers, scores, and timers use tabular figures.
- User text scaling is not globally clamped; layouts must adapt through constraints and wrapping.

## Geometry

- Compact screen margin: 16.
- Compact gameplay margin: 10 to 12.
- Section gap: 24.
- Related item gap: 8 to 12.
- Card radius: 18 to 20.
- Button radius: 14 to 16.
- Small chip radius: 999.
- Sudoku outer radius: 16.
- Elevation: 0 to 2 except transient overlays.

## Components

The shared component set is intentionally small: `AdaptiveAppShell`, `GameNavigationBar`, `AdaptivePageContainer`, `SectionHeader`, `PrimaryPlayCard`, `ModeTile`, `CompactStat`, `CoinPill`, `PlayerPlate`, `DuelTimer`, `ConnectionIndicator`, `RankBadge`, `RewardCard`, `EmptyState`, `ErrorState`, `LoadingSkeleton`, `ResultStat`, `PrimaryActionButton`, and `SecondaryActionButton`.

Cards are reserved for independent interactive groups. Related content should use spacing, typography, alignment, and tonal surfaces first.

## Motion

- Press feedback: 100 to 140 ms.
- Small state changes: 160 to 220 ms.
- Navigation or modal transitions: 220 to 450 ms.
- No continuous glow, broad blur, heavy backdrop filters, or multi-layer animated shadows.
- `MediaQuery.disableAnimations` must be respected for result and timer flourishes.
