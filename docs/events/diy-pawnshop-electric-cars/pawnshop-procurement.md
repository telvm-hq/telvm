# Pawn-shop and thrift procurement

Goal: **teachable parts** with **replaceable interfaces**. Proprietary RC (e.g. some brand-specific hubs) is fine as **donors** if you plan to **drill new patterns in plywood** rather than fight the OEM geometry.

```
  DONOR SHELF                         YOUR LESSON LOOP
 ┌──────────────┐                    ┌──────────────────┐
 │ pawn / thrift │─── extract ──────►│ bench proof      │
 │ buy-new spine │◄── standardize ───│ RC integration   │
 └──────────────┘      ▲             └────────┬─────────┘
                        │                      │
                        └── homework photos ───┘
```

## High-value donors

```
┌────────────────────┬─────────────────────────────┬──────────────────────────────┐
│ Donor              │ Extract                     │ Teaching payoff               │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ Cordless drill     │ Motor + planetary + chuck   │ Torque, reduction, stall I   │
│ (even bad battery) │                             │                               │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ Old RC car         │ Servo, links, RX/ESC?     │ Steering geometry, horn pat. │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ ATX PSU            │ 12 V rail (load 5 V if req) │ Tethered juice; shorts loud  │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ Brackets / extrusion│ Rigid mounts               │ Load paths; less solder flex │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ Longboard / skate  │ Deck, trucks, wheels, brgs │ Session 5; standard hardware │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ VCR / DVD / printer│ Small motors, belts, shafts│ Session 2 friction/string    │
├────────────────────┼─────────────────────────────┼──────────────────────────────┤
│ Bike cable + housing│ Optional pull-steer       │ Mechanical advantage, route  │
└────────────────────┴─────────────────────────────┴──────────────────────────────┘
```

## Buy-new (or known-good) instead of gambling

```
  ITEM                              WHY NOT PAWN-ONLY
 ═══════════════════════════════════════════════════════════════════════════
  Brushed ESC (V + rough I match)   Wrong guess = repeat smoke lessons
  2.4 GHz TX + RX set               AM/FM toys confuse; modern pairs are cheap
  Standard-size servo               Stripped gears; new = predictable
  Balance charger (if LiPo)        Non-negotiable for safe chemistry
  Fuses, wire, XT60/Deans family    Reliability on power path
```

## Avoid-list (until advanced)

```
  ITEM                              RISK
 ══════════════════════════════════════════════════════
  Unknown lithium (no BMS story)    Fire
  Mains AC fans as “DC motors”      Wrong domain; not the lesson
  Mystery BL + mystery ESC          Protocol / smoke roulette
  Hoverboard pack (no system know)  High A, unclear health
```

## Standardization (saves the series)

Pick once and stick to it for student builds:

1. **Battery connector family** (example: XT60).
2. **Motor connector** if students swap motors (bullet vs bare — but **consistent**).
3. **Wood + machine screws** for motor and ESC mounts (not hot glue alone for drive parts).
4. **Skate hardware** for wheels in Sessions 2–5 so **replacement wheels** are a hardware-store or skate-shop errand, not archaeology.

## Pre-session thrift homework

Publish a **photo checklist** (optional): “bring a cordless drill body with battery removed” or “bring a longboard deck even if grip tape is ugly.” See homework blocks in [curriculum.md](curriculum.md).

```
  HOMEWORK FLOW
      │
      ▼
  ┌─────────────┐     photo OK?     ┌─────────────┐
  │ announce    │ ─────────────────► │ session     │
  │ checklist   │                    │ starts on  │
  └─────────────┘                    │ real parts  │
                                     └─────────────┘
```
