# Corrupt police and Pike: story and gameplay proposal (2026-10-08)

Status: PROPOSAL, docs only. Nothing is built. Story is Roy's to write; every name is a placeholder. Police are Stage F, so this shapes Stage F and the story, it does not jump ahead of them.

**Roy's ask (2026-10-08 12:29):** some police are corrupt and work with Pike. They side with Pike but also hate the player, because Pike uses racers against the player. Research it.

Inputs read: `docs/story-bible.md` (main 09455e0), narrative fabric (PR #175, section 9 Pike), sound research section 7 police voices (PR #216), heat helicopter proposal (decided 2026-10-08: top heat only, spots only, escapes by driving), gas station decisions (Pike clues at stations, item 23), living-world notes (police crackdown, scanner).

Already decided and kept: police voice lines are **captions + squelch now**, voices later (offline text-to-speech that passes the free-assets rule: Chatterbox MIT, Kokoro Apache 2.0). Police cast of 5 is **kept** (dispatcher, veteran, rookie, sergeant, air unit). Pike takes Cred, never cars, mods or progress.

## One line

**Bad cops hunt you where nobody is watching.** Honest police chase you for breaking the law; Pike's cops chase you for Pike, off the radio, in the dark parts of the map, and they back off the moment a witness shows up.

## Steelman and premortem

- Steelman: one rule ("bad cops avoid witnesses") gives the player something to read and play against without any on-screen hint, ties heat, the helicopter, gas stations and the radio into the Pike story, and gives the ending a clear goal: get the bad cops seen.
- Premortem, it failed because:
  1. Players could not tell bad cops from honest ones, so it felt random. Fix: two tells you can hear and see (the radio goes quiet, the car looks different), never a HUD marker.
  2. Bad cops felt unbeatable or unfair (ramming, stealing money). Fix: they take only tonight's unbanked cash, and every one of them can be shaken by driving into witnesses.
  3. It made the police system twice as big. Fix: same cop AI, same cars, one flag (`on_pikes_payroll`) that changes a few behaviours and lines.
- Falsification: if playtesters, asked after a chase, cannot say whether a bad cop was in it, the tells are too weak.

## What other stories do (checked)

| Source | What happens | What we take |
|---|---|---|
| **Need for Speed Heat** (2019) | Lt. Frank Mercer's High-Speed Task Force impounds racers' cars and extorts racers for money; seized cars go out through Mercer's illegal chop shop. Day races are legal, night racing pays rep and draws cops. Busts cost a fine, never the car. The crew exposes the task force; Mercer is taken down at the port. ([Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)) | The closest match. Corrupt cops who profit from racers; exposing them is the story's goal. We differ: our cops serve a lender, not themselves |
| **Need for Speed Undercover** (2008) | The player's FBI handler, Chase Linh, secretly works with the crime boss, betrays and frames the player; an honest lieutenant helps clear them. ([Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Undercover)) | An honest cop as an ally against the bent ones |
| **Baltimore Gun Trace Task Force** (real, convicted 2018) | Officers robbed people during stops and searches, faked overtime and warrants. A detective tipped off his dealer friend about police, and the dealer **fed him names of rival dealers to rob**. Caught when a dealer found a federal tracker on his car and called the detective. ([WYPR](https://www.wypr.org/wypr-news/2018-06-06/how-the-gttf-cops-were-caught-and-why-didnt-local-authorities-catch-em), [The Daily Record](https://thedailyrecord.com/2018/02/01/baltimore-police-trial/)) | The exact shape Roy described: a criminal feeds cops targets, cops protect the criminal. Pike's racers feed the cops the player |
| NFS Most Wanted (2005), from memory, not re-checked | Sgt. Cross is an honest, hard cop who hates street racers personally | A cop who hates you can still be honest; keeps the honest side interesting |

## 1. Why the bad cops work for Pike (the deal)

Pike is a lender. The cleanest reason is that **he owns them**, the same way he owns the shop's debt.

| Option | What it means | Fits |
|---|---|---|
| **A. Pike holds their debts (recommended)** | Gambling, a mortgage, a kid's tuition. Pike forgives a little each time they do him a favour | Pike's whole character is debt; it mirrors the player's own situation |
| **B. Pike gives them easy arrests (recommended, with A)** | Pike's racers phone in where other racers are. The cops get arrests that look good; Pike's crew gets rivals cleared off the streets. This is the Baltimore pattern | Explains why they are always where you are |
| C. Pike pays them a cut of the mayor's waterfront deal | Plain bribes | Works, but generic |
| D. Impound racket (NFS Heat) | They seize racers' cars and sell them through the scrapyard | Clashes with the decision that the player never loses a car |

## 2. Why they hate the player (not just "Pike said so")

1. **You cost them money.** Every district your crew takes from Pike's racers is one where Pike stops paying them. Every Cred you pay Pike off is a favour they will not get credited.
2. **You make them look bad.** Escaping a bad cop in front of his colleagues gets talked about on the scanner. Dave mentions it on air.
3. **You are collecting proof.** The clues you find at gas stations (decided, item 23) point at Pike, and the cops know the trail leads to them too. Later in the story this is the real reason they come after you.
4. **Pike tells them you are the problem.** Pike's racers lose to you, then report you. The cops get your car, your route and your habits.

## 3. How Pike uses racers against the player

All of these use systems that already exist or are planned (traffic, race events, heat, scanner):

| # | Move | What the player sees | Tie-in |
|---|---|---|---|
| R1 | **The tip-off** | You beat one of Pike's racers; a minute later the scanner picks up "caller reports a [your colour] [your car type] on [street]" and heat jumps one level | Heat, scanner captions |
| R2 | **The setup race** | A Pike racer offers a race on the event board or at a station. The finish line has bad cops waiting | Event board, roadblock |
| R3 | **The box-in** | During a chase, Pike's racers drive alongside and brake in front of you to slow you for the cops | Traffic AI, blind spot lamp mod pays off here |
| R4 | **The free pass** | Bad cops chase Pike's racers past you and let them go, then turn on you. You see the racer slip away untouched | Shows the corruption without a line of dialogue |
| R5 | **The poach** | The crew member poached by a rival (story bible) is turned using a bad cop's threat | Crew drama |

## 4. Who the bad cops are (cast, placeholders)

Small group, so honest police stay the norm and bad ones feel personal. The 5-voice radio cast stays; corruption is a trait, not more voices.

| Character | Honest or bad | Role |
|---|---|---|
| Dispatcher | Honest | The steady voice. Notices when units go quiet |
| Veteran unit | Honest, tired | Chases you by the book; low heat |
| Rookie | Honest, can be turned to your side | Sees too much. Later in the story becomes your inside source |
| **Sergeant** | **Bad: Pike's man** | Runs roadblocks at high heat. The face of the corruption |
| **Sergeant's partner** (a second car, no new voice) | **Bad** | Does the ramming and the shakedowns |
| Air unit (helicopter) | Honest, by the book | Witness from above. Bad cops back off when it arrives |
| Captain (story only, stills and texts) | Bad, tied to the mayor | Protects the sergeant. Only seen in the story |

## 5. How bad cops play differently

Same cop AI and cars, one flag. Differences, all readable without on-screen hints:

| | Honest cops | Pike's cops |
|---|---|---|
| **Radio** | Call everything in; captions describe the chase | **Go quiet.** Captions show the dispatcher asking "Unit 12, say your location... Unit 12?" with no answer. Silence is the tell |
| **Look** | Marked black-and-white with red and blue bar | Mostly **unmarked dark sedans** with grille lights (one reused NPC body, no new model), sometimes a marked car with a dented push bar |
| **Where** | Anywhere you break the law in their sight | Dark, empty places: docks, back roads, the canyon, late at night. Never busy downtown or gas station forecourts |
| **Driving** | Follow, box, roadblock at high heat | Ram and push early, ignore "pursuit called off" |
| **Witnesses** | Do not care | **Back off** when the helicopter, an honest unit, a busy street or a lit gas station is near |
| **Catch you** | **Bust:** lose tonight's unbanked cash plus a fine (Stage C, P2) | **Shakedown:** lose tonight's unbanked cash, **no fine, no record**, and the cash goes to Pike. Dave hears about it |
| **Heat after** | Stays, then cools | Drops to zero (they never reported it), which is itself suspicious |

**The counterplay (the fun part):** escape bad cops by driving **toward** witnesses. Pull them into downtown traffic, under the helicopter's beam, past an honest unit, or onto a lit gas station forecourt (station heat cool-down is decided, item 6). This turns the helicopter from only a threat into a tool: at top heat it is dangerous to you and to them.

**Getting proof:** escaping a shakedown, or getting a bad cop into the helicopter's beam, earns a clue (dashcam clip, a plate). Clues feed the Pike story with the gas station clues.

## 6. How it fits heat and the helicopter

- **One heat meter, no second bar.** Heat rules stay as Stage C and the helicopter proposal set them.
- A hidden **Pike attention** number (story act + how much you owe + how many of his racers you beat) sets the chance that a chase includes bad cops. Low in Act 1, high after the Turn. Lives in the tunables file with the other Pike numbers.
- Heat ladder with corruption on top:
  1. Low heat: honest patrols. Bad cops only if Pike's racers tipped them (R1).
  2. Mid heat: more units; bad units can join, going quiet on the radio.
  3. High heat: roadblocks. If the sergeant runs one, it is placed on a dark road, not a main street.
  4. Top heat: the honest helicopter arrives. Bad units peel away. You now have only honest cops on you, so it is harder to lose but safe from a shakedown.
- The helicopter's beam lighting the road (decided) can also light a bad cop car, which is how you get proof.

## 7. Story beats (Roy writes the words)

| Beat | What happens with the bad cops |
|---|---|
| Prologue | After Ledger beats you, a cop pulls you over and lets Ledger's car go past. Just a feeling |
| Act 1 | First shakedown on a dark road. Tonight's cash is gone, no ticket. Dave on air: "funny, no record of any stop" |
| Act 2 | Pike's racers start the tip-offs and setup races. The rookie notices the sergeant's unit always goes quiet |
| Turn | The night Dave's tower goes silent: you see the sergeant's car outside the liquor store with Ironbridge's cars |
| Act 3 | The rookie becomes your inside source (scanner tips, a safe route). You collect proof |
| Ending | Proof goes out on Dave's broadcast; the honest air unit and dispatcher take the sergeant down during the Ledger rematch, or the story keeps him for later. Roy's call |

## 8. Cost and assets

- Code: one flag on the cop car, a few behaviour switches, caption lines, a hidden number. Builds on Stage F cops; nothing before Stage F.
- Art: unmarked car = an existing NPC sedan body with grille lights and a push bar. No new model.
- Sound: captions + squelch now. Voices later with offline text-to-speech (Chatterbox or Kokoro), radio filter. Squelch and static from the Sonniss GDC bundle (royalty-free, commercial, no credit). All pass the free-assets rule.

## Questions for Roy (recommendation marked)

1. Why do the bad cops help Pike? **He owns their debts and hands them easy arrests (recommended)** / he pays them / both plus the mayor's money
2. Can you tell a bad cop when you see one? **Yes: dark unmarked car and they go quiet on the radio (recommended)** / no, they look the same
3. When bad cops catch you, do they take tonight's cash and skip the ticket? **Yes (recommended)** / no, same as a normal bust
4. Do bad cops back off when someone is watching, like the helicopter or a busy street? **Yes (recommended)** / no
5. Do Pike's racers set you up, like phoning you in or a race that ends at a roadblock? **Yes (recommended)** / no
6. Can you win the rookie cop over to your side later in the story? **Yes (recommended)** / no
7. How many bad cops? **A small group: one sergeant and his partner (recommended)** / a whole squad
8. Does the story end with the bad cops exposed? **Yes, at the end (recommended)** / leave them around for later

## Sources

- [Need for Speed Heat, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)
- [Need for Speed: Undercover, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Undercover)
- [How the GTTF cops were caught, WYPR (2018)](https://www.wypr.org/wypr-news/2018-06-06/how-the-gttf-cops-were-caught-and-why-didnt-local-authorities-catch-em)
- [Drug dealers testify against Baltimore Police at trial, The Daily Record (2018)](https://thedailyrecord.com/2018/02/01/baltimore-police-trial/)
