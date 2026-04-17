# Curriculum — five sessions

Cross-links: [schedule.md](schedule.md), [safety-and-batteries.md](safety-and-batteries.md), [pawnshop-procurement.md](pawnshop-procurement.md).

```
  S1 bench ──► S2 roll ──► S3 PWM+gear ──► S4 RC stack ──► S5 longboard
```

---

## Session 1

**Name:** Ratchet proof of motion  
**Where it lands:** Bench or tethered; **no radio**.

### Learning objectives

- Explain **voltage**, **current**, and why a stalled motor **heats** faster than a free-spinning one.
- Wire **battery → fuse (optional) → switch → motor** with clean joins (no dry twists on power paths).
- Name one reason **proprietary RC** is harder to repair than **wood + standard screws**.

### Minimum viable build

- **Chassis**: scrap wood, cardboard, or small plastic box; **zip ties** or wood screws; no aesthetic requirement.
- **Motor**: small **brushed** DC (toy, VCR/DVD donor, or **drill motor removed from gearbox** for lighter load in hour one).
- **Power**: **AA holder** or **current-limited bench supply**; avoid mystery lithium. See [safety-and-batteries.md](safety-and-batteries.md).
- **Control**: **toggle or slide switch**; demonstrate **reverse polarity** swaps spin direction.

### Stretch

- Add an **LED + resistor** across the motor terminals (unplug battery first) to show **back-EMF** flicker when hand-spinning.

### Failure modes (teach intentionally)

- **Stall until warm**: feel the case; relate to “why ESCs die” preview for Session 3.
- **Loose wire**: intermittent run; introduce **strain relief**.

### Homework before Session 2

- Thrift: **skate wheels** or a **caster cart**, **rubber bands**, **string**, **small bolts/nuts** matching wood you will use.
- Read: [pawnshop-procurement.md](pawnshop-procurement.md) **Standardization** section.

### Parts list

```
  SOURCE          PARTS
 ═══════════════════════════════════════════════════════════════════════
  Pawn / thrift   Wood scrap, zip ties, AA holders, toy motors, VCR motors
  Buy-new         Fuse + holder or bench supply access, hookup wire, switch
```

---

## Session 2

**Name:** Rolling chassis without mystery electronics  
**Where it lands:** Rolls on **replaceable wheels**; drive is intentionally **janky**.

### Learning objectives

- Compare **friction drive**, **string/belt wrap**, and **rubber-band pulley** for slip vs grip.
- Explain why **wheel diameter** changes top speed for a given motor RPM.
- Use a **fuse** or supply limit and articulate **why** moving mass needs more current.

### Minimum viable build

- **Deck**: same junk chassis or a **short plank**; attach **two axles**: fixed rear, lazy front is OK at this stage.
- **Wheels**: **skate/longboard wheels** on bolts-as-shafts **with washers and nuts** (teach **retention** now—it pays off Session 5).
- **Drive**: pick one janky path: rubber band around motor shaft to wheel OD; or string wrapped once; or foam wheel pressed on tire.
- **Power**: still tethered or switch; **no radio**.

### Stretch

- Measure **distance per 10 seconds** with different wrap tension; plot on a whiteboard.

### Failure modes

- **Slip forever**: not enough normal force; add weight block or second rubber band.
- **Axle bind**: misaligned holes; introduce **shim washers**.

### Homework before Session 3

- Acquire **cordless drill** carcass (battery optional) for gearbox extraction demo.
- Decide series **connector family** (see [pawnshop-procurement.md](pawnshop-procurement.md)).

### Parts list

```
  SOURCE          PARTS
 ═══════════════════════════════════════════════════════════════════════
  Pawn / thrift   Wheels, bearings if present, bolts, scrap aluminum
  Buy-new         Nylock nuts, washers, fuse, decent wire
```

---

## Session 3

**Name:** Controlled speed — brushed path  
**Where it lands:** **PWM** speed control; **mechanical reduction**; optional **wired throttle** (pot + small brushed ESC that supports it, or ESC stick endpoints learned on bench).

### Learning objectives

- Define **PWM** as rapid on/off averaging; relate **duty cycle** to “feels like lower voltage.”
- Tie **gear reduction** to **torque at the wheel** and **lower stall tendency** at the battery.
- Map **current**, **heat**, and **undersized ESC** to the real-world “we killed an ESC” story.

### Minimum viable build

- **Motor + gearbox**: **drill planetary** stage driving a shaft to Session 2 wheel system (adapter plate from plywood).
- **Controller**: **brushed ESC** rated for your pack voltage with headroom; or robust DC motor driver module if curriculum prefers Arduino-free simplicity—pick one pedagogy and stay consistent.
- **Input**: **radio optional** this session; a **wired** throttle keeps focus on PWM. If you already introduce TX, keep steering disconnected or fixed straight.

### Stretch

- **Thermal**: tape a thermocouple strip or IR gun on ESC heatsink; log **after 30 s** at partial throttle vs stall-sniff test (brief!).

### Failure modes

- **ESC beeps / no spin**: **calibration** or **no signal**; teach **arm sequence** if using RC ESC early.
- **Grinding gearbox**: wrong alignment; **shim** motor face to pinion.

### Homework before Session 4

- Purchase or donor: **2.4 GHz TX/RX**, **standard servo**, **Y-harness or separate BEC** plan.
- Pre-build **plywood front steer** mock: two holes for kingpins (bolts) and horn attachment point.

### Parts list

```
  SOURCE          PARTS
 ═══════════════════════════════════════════════════════════════════════
  Pawn / thrift   Drill bodies, metal brackets
  Buy-new         Brushed ESC, connectors, low-C NiMH or small LiPo if policy
                  allows (see safety-and-batteries.md)
```

---

## Session 4

**Name:** Real RC stack  
**Where it lands:** **2.4 GHz** control; **BEC or UBEC** feeding receiver/servo; **steering servo** on **bolt-on plywood axle**.

### Learning objectives

- Separate **power path** (battery → ESC → motor) from **signal path** (receiver throttle).
- Explain **BEC**: why servos want ~5 V even when the battery is 7.4 V or 11.1 V.
- Set **failsafe** (throttle neutral) per radio manual; verbalize **stop** calls.

### Minimum viable build

- **Throttle channel** drives brushed ESC; **second channel** drives **steering servo**.
- **Mechanical**: **rear** stays Session 3 drive; **front** is **servo horn** pulling **tie rod** or **direct horn** on kingpin lever (simple trapezoid steering).
- **Power distribution**: if ESC BEC is weak, add **UBEC** to receiver bus and **remove** red wire from second device per your wiring plan (teach **one power source** rule).

### Stretch

- **Bike cable steering** with housing bends; compare **slack** vs **binding**.

### Failure modes

- **Brownouts**: steering glitches under acceleration; fix with **capacitor at receiver** (if spec allows) or **stronger BEC**.
- **Servo strip**: horn bolt not on **splined** hub correctly; mechanical end stops missing.

### Homework before Session 5

- Source **longboard deck + trucks**; confirm **wheel nuts** and **bearing seats**; clean threads.
- Plan **ESC mounting** with **air gap** to deck (vibration foam + zip ties or small standoffs).

### Parts list

```
  SOURCE          PARTS
 ═══════════════════════════════════════════════════════════════════════
  Pawn / thrift   Old RC for linkage ideas (may discard proprietary arms)
  Buy-new         TX/RX set, servo, horn assortment, UBEC if needed,
                  threadlocker (tiny dab on wheel nuts only where appropriate)
```

---

## Session 5

**Name:** Longboard RC integration  
**Where it lands:** **Driveable RC** on **longboard deck**; speed **capped** by ratio, endpoint trim, and house rules.

### Learning objectives

- Integrate prior subsystems with **strain relief**, **anti-vibration**, and **serviceability** (unplug motor without disassembling deck).
- Produce a **postmortem**: for each failure, **symptom → cause → generic fix vs proprietary fix** (use a whiteboard grid or copy the ASCII template below).
- Compare **OEM RC car** (e.g. integrated hubs) vs **skate standard** for **field repair**.

### Minimum viable build

- **Chassis**: longboard deck; trucks at both ends or **tail drive + front steer** per your safety layout.
- **Electronics migration**: Session 3–4 stack secured on **riser** or **small plywood sled** bolted through deck (use **backup washers**).
- **Wheel retention**: **axle nuts present**, threads clean, **re-torque** after first shakedown.
- **Cooling**: ESC not sandwiched on foam; **air path**; zip ties not covering FET face if manufacturer says otherwise.

### Stretch

- **Dual-motor** (differential throttle mixing) is a **different** series; do not add unless time and supervision are ample.

### Failure modes

- **Throwing a wheel**: wrong axle thread or missing spacer; teach **bearing inner race** support.
- **Receiver reboots on bumps**: bad **connector** crimp; fix, do not tape over.

### Homework (series closeout)

- Write your **personal parts BOM** with **vendor-agnostic names** (“2S–3S brushed ESC ≥ X A” not a single SKU cult).
- Optional: **photo doc** for next cohort.

### Parts list

```
  SOURCE          PARTS
 ═══════════════════════════════════════════════════════════════════════
  Pawn / thrift   Longboard, pads, helmet for humans
  Buy-new         Skate hardware, risers, quality zip ties, anti-vibration tape
```

### Postmortem template (whiteboard or notes)

```
  SYMPTOM              CAUSE                 GENERIC FIX        PROP FIX?
 ═══════════════════════════════════════════════════════════════════════════
  (example)            (example)             (example)          (Y/N/NA)
```

---

## Series capstone checklist

```
  CHECK                                                    OK?
 ═══════════════════════════════════════════════════════════════════════
  safety-and-batteries.md re-read same day                [ ]
  Failsafe verified                                        [ ]
  Run area fenced OR spotter assigned                        [ ]
  Fire bag / metal bin ready if LiPo                       [ ]
  First drive ≤ walking speed shakedown                    [ ]
```

Links: [safety-and-batteries.md](safety-and-batteries.md), [pawnshop-procurement.md](pawnshop-procurement.md), [schedule.md](schedule.md).
