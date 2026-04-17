# Safety and batteries

This series is **hobby and educational**. Runs belong on **private property** or a **closed course** with permission, not public roads. See also [liability-and-disclaimer.md](liability-and-disclaimer.md).

## Personal protective equipment and workspace

```
  PRACTICE                              WHY
 ═══════════════════════════════════════════════════════════════════════
  Eye protection (cut / drill / solder) Chips + flux splash
  Ventilation when soldering            Flux fumes
  Cut gloves optional; never catch blade Unpredictable pawn tools
  Clear bench; metal tray for hot parts Shorts + clutter = fires
  One energized circuit at first power Easier to find the mistake
```

## Electrical: shorts, heat, and “smoke events”

- **Assume every unknown wire is live** until proven otherwise.
- **Fuse or current-limited supply** for early sessions; a bench supply with adjustable current limit teaches more than instant lithium smoke.
- **Polarity matters** for brushed DC; reversing battery swaps spin direction, not “fix” a dead short.
- **Heat is normal; smoke is not.** If something smells sweet or sharp, **disconnect power** and wait before touching.
- **Strain relief**: battery leads that flex will fatigue and short; zip-tie service loops away from wheels.

## Battery chemistries (what to use when)

```
 ┌─────────────┬──────────────────┬────────────────────────────────────────┐
 │ Chemistry   │ Session fit      │ Notes                                   │
 ├─────────────┼──────────────────┼────────────────────────────────────────┤
 │ AA / AAA    │ 1–2 tiny motors  │ High Ri; safe-ish; weak for real loads │
 │ alkaline    │                  │                                         │
 ├─────────────┼──────────────────┼────────────────────────────────────────┤
 │ NiMH packs  │ 2–4 gentle brushed│ Forgiving vs LiPo; still respect shorts│
 ├─────────────┼──────────────────┼────────────────────────────────────────┤
 │ SLA 12 V    │ 2–3 tethered     │ Heavy; teaches sag; strap the brick    │
 ├─────────────┼──────────────────┼────────────────────────────────────────┤
 │ LiPo        │ 3+ with rules only│ Balance charge · no puncture · fire bag│
 └─────────────┴──────────────────┴────────────────────────────────────────┘
```

**Do not** build Session 1 around **random laptop 18650 packs** from a pawn shop unless you have **known-good BMS**, tested cells, and adult supervision comfortable with spot-welding and pack design. That is a **different course**.

## LiPo minimum rules (if introduced Session 3+)

- **Hard case** where possible; **tape balance leads** so they cannot short.
- **XT60 or Deans** (pick one family for the series) and **no alligator clips** on LiPo main leads for driving.
- **Low-voltage cutoff** on ESC or explicit discipline: stop when cells sag under load.
- **Fire bag or metal bucket with lid** in the run area; know where **sand** is.

## Radio drive sessions (4–5)

- **Failsafe**: throttle neutral and brake/reverse behavior understood before wheels touch ground.
- **Foot speed limit**: cap endpoints mechanically (gear ratio) or in transmitter model limits where possible.
- **Spotter**: someone whose only job is to call stop if the vehicle heads for people, cars, or traffic.

## Venue

Indoor carpet **reduces** injury from small cars; it **increases** heat in ESCs. Outdoor asphalt needs **clear runoff** and **no spectators in line of travel**.

```
        INDOOR                         OUTDOOR
     softer impact                  clear runoff lane
     ESC runs hotter                 spotter + no line-of-fire crowd
```
