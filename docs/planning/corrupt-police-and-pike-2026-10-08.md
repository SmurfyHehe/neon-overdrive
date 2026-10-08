# Corrupt police and Pike: story and gameplay proposal (2026-10-08, rev 2)

Status: PROPOSAL, docs only. Nothing is built. Story is Roy's to write; every name is a placeholder. Police are Stage F, so this shapes Stage F and the story, it does not jump ahead of them.

**Roy's ask (2026-10-08 12:29):** some police are corrupt and work with Pike. They side with Pike but also hate the player, because Pike uses racers against the player. Research it.

Inputs read: `docs/story-bible.md` (main 09455e0), narrative fabric (PR #175, section 9 Pike), sound research section 7 police voices (PR #216), heat helicopter proposal (decided 2026-10-08: top heat only, spots only, escapes by driving), gas station decisions (Pike clues at stations, item 23), living-world notes (police crackdown, scanner).

## Decided (Roy, 2026-10-08 12:45)

1. **Why they serve Pike:** Pike is trying to take over everything. The bad cops get paid, and he owns their debts.
2. **You can spot a bad cop** by menacing items on their cars. We need **distinct corrupt police cars** (section 5).
3. **When bad cops catch you, they take the cash and give you a ticket.**
4. Bad cops do **not necessarily** back off when someone is watching. Witnesses are not a guaranteed escape.
5. **Pike's racers set you up:** yes.
6. **The rookie can be won over**, but he must keep the moral high ground and never team up with racing criminals (the player). Research how (section 7).
7. **The bad cops are the sergeant and his partner.** From the sound questions, the **veteran** is also Pike's man, so the veteran is the sergeant's partner.
8. **The story ends with the bad cops exposed.**

Earlier decisions kept: police voice lines are **captions + squelch now**, voices later (offline text-to-speech that passes the free-assets rule: Chatterbox MIT, Kokoro Apache 2.0). The police radio cast keeps its five roles. Pike takes Cred, never cars, mods or progress.

## One line

**Pike owns two cops, and you can see it on their cars.** The sergeant and his veteran partner drive marked-but-wrong police cars paid for with Pike's money, go quiet on the radio when they come for you, and take your cash and write you a ticket. An honest rookie works to bring them down without ever becoming your friend.

## Steelman and premortem

- Steelman: a small, named pair of bad cops with their own cars makes the corruption personal and readable. The player learns to dread one silhouette in the mirror, and the ending (exposing them) is a clear goal.
- Premortem, it failed because:
  1. Players could not tell bad cops from honest ones. Fix: the cars look different (section 5) and the radio goes quiet. Two tells, one you see and one you hear, no HUD marker.
  2. Bad cops felt unfair. Fix: they only ever take tonight's unbanked cash plus a ticket, and they can always be outdriven.
  3. The rookie read as the player's buddy, breaking Roy's rule. Fix: the rookie never meets, helps or thanks the player (section 7).
  4. Two extra cop cars cost too much art. Fix: they are the normal cop body with bolt-on props, not new models.
- Falsification: if playtesters, shown a chase clip, cannot say whether a bad cop was in it, the car props are too subtle.

## What other stories do (checked)

| Source | What happens | What we take |
|---|---|---|
| **Need for Speed Heat** (2019) | Lt. Frank Mercer's High-Speed Task Force impounds racers' cars and extorts racers for money; seized cars go out through Mercer's illegal chop shop. Busts cost a fine, never the car. The crew exposes the task force. ([Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)) | Corrupt cops who profit from racers; exposing them is the goal |
| **Need for Speed Undercover** (2008) | The player's FBI handler secretly works with the crime boss and frames the player; an honest lieutenant helps clear them. ([Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Undercover)) | An honest cop on the other side of the same enemy |
| **Baltimore Gun Trace Task Force** (real, convicted 2018) | Officers robbed people during stops and searches and faked overtime and warrants. A detective tipped off his dealer friend, and the dealer **fed him names of rival dealers to rob**. Caught by federal investigators who followed the detective after a dealer found a tracker on his car and called him. ([WYPR](https://www.wypr.org/wypr-news/2018-06-06/how-the-gttf-cops-were-caught-and-why-didnt-local-authorities-catch-em), [The Daily Record](https://thedailyrecord.com/2018/02/01/baltimore-police-trial/)) | The exact shape Roy described: a criminal feeds cops targets, cops protect the criminal |
| **Frank Serpico** (real, NYPD, 1967-71) | Reported corruption inside the department; nothing happened. Helped get a front-page *New York Times* story, which led to the Knapp Commission. When he was shot during an arrest, colleagues did not call for help. Many officers still see him as a traitor. ([Wikipedia](https://en.wikipedia.org/wiki/Frank_Serpico)) | The model for the rookie: an honest cop who goes **outside** the department (the press) when the inside fails, and is hated for it by bad colleagues |

## 1. Why the bad cops work for Pike (decided)

Pike is trying to take over the city: the shop's debt, the waterfront, the rival crews, the police. The two cops are his because:
- **He owns their debts** (gambling, a mortgage; Roy writes which). Each favour knocks some off.
- **He pays them.** Cash from the mayor's waterfront deal, and a cut of what they take from racers.
- **He feeds them easy arrests** (the Baltimore pattern). Pike's racers phone in where other racers are; the cops look good on paper, and Pike's crews get rivals cleared off the street.

## 2. Why they hate the player

1. **You cost them money.** Every district your crew takes from Pike's racers is one where Pike stops paying them.
2. **You make them look bad.** Every escape from them is heard on the scanner and mentioned by Dave on air.
3. **You are collecting proof.** The clues you find at gas stations (decided, item 23) point at Pike, and the trail leads to them too.
4. **Pike tells them you are the problem.** His racers lose to you, then report you.

## 3. How Pike uses racers against the player (decided: yes)

| # | Move | What the player sees | Tie-in |
|---|---|---|---|
| R1 | **The tip-off** | You beat one of Pike's racers; a minute later the scanner picks up "caller reports a [your colour] [your car type] on [street]" and heat jumps one level | Heat, scanner captions |
| R2 | **The setup race** | A Pike racer offers a race on the event board or at a station. The finish line has the sergeant waiting | Event board, roadblock |
| R3 | **The box-in** | During a chase, Pike's racers drive alongside and brake in front of you to slow you for the cops | Traffic AI; the blind spot lamp mod pays off here |
| R4 | **The free pass** | The bad cops chase a Pike racer past you and let him go, then turn on you | Shows the corruption without a line of dialogue |
| R5 | **The poach** | The crew member poached by a rival (story bible) is turned with a threat from the sergeant | Crew drama |

## 4. Who is who

| Character | Honest or bad | Role |
|---|---|---|
| Dispatcher | Honest | The steady voice. Notices when two units keep going quiet |
| **Sergeant** | **Bad: Pike's man** | Runs roadblocks at high heat. The face of the corruption. Drives car B1 |
| **Veteran** (the sergeant's partner) | **Bad: Pike's man** | Does the ramming and the shakedowns. Drives car B2. Dry, unhurried voice |
| Rookie | Honest | Chases you hard by the book. Quietly builds the case against the other two (section 7) |
| Air unit (helicopter) | Honest | By the book. Its camera is a risk to the bad cops |
| Captain (story only, stills and texts) | Bad, tied to the mayor | Protects the sergeant |
| Other patrol units (no voice) | Honest | The normal police at low and mid heat |

## 5. The corrupt police cars (decided: distinct, spotted by menacing items)

**Rule:** same cop body and the same driving sim as honest cars (one data flag, `on_pikes_payroll`), with **bolt-on props, a darker paint and different lights**. No new models. Each prop reads at night, in the mirror, from about 50 m.

Ideas, all original, all built from simple meshes or Kenney CC0 parts plus our own textures:

| Prop | Honest cop | Bad cop | Why it reads |
|---|---|---|---|
| **Paint** | Clean black-and-white, reflective door lettering | **Blacked-out "ghost" livery**: dark grey letters on black that only flash when your headlights or a streetlight hit them | Sinister; there is a real thing called a ghost livery on US cruisers, so it is believable |
| **Push bar** | Plain, clean | **Heavy steel push bar, scraped bare, paint of other cars on it**, maybe a chain wrapped on it | Says "this car rams people" |
| **Spotlight** | None, or off | **A-pillar spotlight swung onto you** while they tail you; a hard white cone in your mirror | Very readable at night, menacing, and ties to the helicopter's beam |
| **Light bar** | Full red and blue bar, flashing in a regular pattern | **No roof bar.** Hidden red and blue strobes in the grille and rear window, flashing in a **faster, irregular** pattern | Different rhythm and placement in the mirror |
| **Windows** | Clear, you see the officer | **Dark tint**, no face | Faceless = threat |
| **Wheels** | Plain steel with hubcaps | **Black steel wheels, no caps** | Lower, meaner stance |
| **Engine** | Normal police engine | **Louder, tuned engine** (Pike's money). You hear them coming before you see them | Ties to the sound plan: per-car engine voices |
| **Damage** | Clean | Dents on the doors and a cracked tail lamp that are never fixed | They hit things and nobody asks |
| **Cabin details** (cockpit view, close passes) | Laptop, radio | A **cash envelope on the dash**, a cigarette glow, a racer's plate on the seat | A small reward for players who look |

**Palette:** red and blue are allowed (expanded palette). The police blue `#2E4FD8` and a matching red stay for all police lights; bad cops differ by pattern and placement, not by new colours. The spotlight is plain white. The ghost livery is navy-black `#0E1424` on black, so it fits Amber vs. Dusk.

**Recommended set for the first build:** ghost livery, scraped push bar, A-pillar spotlight, grille strobes with no roof bar, dark tint. Those five read from far away. The rest come later.

## 6. How bad cops play differently

| | Honest cops (incl. rookie) | The sergeant and the veteran |
|---|---|---|
| **Radio** | Call everything in; captions describe the chase | **Go quiet.** Captions show the dispatcher asking "Unit 12, say your location... Unit 12?" with no answer |
| **Driving** | Follow, box, roadblock at high heat | Ram and push early, spotlight you, ignore "pursuit called off". A little faster (tuned engines) |
| **Where they show up** | Anywhere you break the law in their sight | Wherever Pike's racers send them (R1, R2). More often at night in docks, back roads and the canyon, but they **can come anywhere** |
| **Witnesses** | n/a | **Not a guaranteed escape** (Roy). They are a bit more careful near the helicopter, but they do not simply leave |
| **When they catch you** | **Bust:** a fair fine, as Stage C P2 sets | **Shakedown:** they take **all of tonight's unbanked cash** and **write you a ticket** too. Cash goes to Pike. The ticket is a real fine (it is on paper) |
| **How to beat them** | Driving, the escapes from the helicopter design | Out-drive them. They are faster but heavier; the push bar makes them worse in tight turns. Lose the spotlight with hard turns and cover, like the helicopter beam |

**Getting proof:** escaping a shakedown, or getting a bad cop into the helicopter's beam, earns a clue (a dashcam still, a plate, a number). Clues join the gas station clues for the Pike story.

## 7. The rookie: winning him over without him joining you (Roy: research)

**Roy's rule:** the rookie keeps the moral high ground. He does not team up with racing criminals, and the player is a racing criminal.

**What the research says:** honest insiders who bring down corrupt cops usually **go around the department, not to criminals**. Serpico reported inside, was ignored, and went to the press; the Baltimore unit fell to federal investigators. In both, the honest side never worked with the people breaking the law.

**So the rookie and the player are never allies. They share an enemy and never meet as friends.** He is "won over" to the **truth**, not to the player.

| Option | How it works | Keeps his high ground? |
|---|---|---|
| **A. The drop (recommended)** | You never speak to him. You leave proof where he will find it: an unsigned envelope at a gas station, or a tip Dave reads on air. The rookie checks it himself, by the book | **Yes.** He acts on evidence, not on a racer's word |
| **B. Dave in the middle (recommended, with A)** | The rookie listens to Graveyard TV. Dave airs what you found; the rookie hears it like any listener. Dave is the "press", like Serpico's newspaper | **Yes.** A journalist, not a criminal, is the link |
| C. A grudging deal | He meets you once and says "give me the proof, and I'll still bring you in" | Partly. Roy's rule suggests not |
| D. Saves you once | He pulls you out of a shakedown | No. That is siding with you |

**How it plays out (proposed beats, Roy writes the words):**
1. **Act 1:** the rookie chases you like any honest cop. He is good, polite on the radio, and does not let you go.
2. **Act 2:** he notices the sergeant and the veteran keep going quiet. The dispatcher's captions show him asking about it. He gets told to drop it.
3. **The Turn:** like Serpico, the bad cops leave him without backup in a dangerous moment (no "officer needs help" call). He survives. He now knows.
4. **Act 3:** your proof reaches him by the drop and Dave's broadcast. He never thanks you. On air you hear him say something like "I don't care who sent it. It checks out."
5. **Ending:** the rookie arrests the sergeant and the veteran. Then he turns to you: **"You're next."** You get a ticket, or a head start. He keeps his high ground, and the player keeps an honest rival for later.

## 8. How it fits heat and the helicopter

- **One heat meter, no second bar.**
- A hidden **Pike reach** number (story act + how much you owe + how many of his racers you beat) sets the chance that the bad pair joins a chase. Low in Act 1, high after the Turn. Lives in the tunables file.
- Heat ladder with corruption on top:
  1. Low heat: honest patrols. The bad pair only if a Pike racer tipped them (R1).
  2. Mid heat: more units; the bad pair can join, going quiet on the radio.
  3. High heat: roadblocks; the sergeant may run one.
  4. Top heat: the honest helicopter. The bad pair stay but are a bit more careful in its beam; it can also catch them on camera for proof.

## 9. Story beats (Roy writes the words)

| Beat | What happens with the bad cops |
|---|---|
| Prologue | After Ledger beats you, a ghost-livery car pulls you over and waves Ledger's car past |
| Act 1 | First shakedown: cash gone, ticket written. Dave on air: "funny, the ticket's real, the cash isn't on it" |
| Act 2 | Pike's racers start the tip-offs and setup races. The rookie starts asking questions |
| Turn | The night Dave's tower goes silent: the sergeant's car is outside the liquor store with Ironbridge's cars. The rookie is left without backup |
| Act 3 | You collect proof and get it to the rookie by the drop and Dave's broadcast |
| Ending | The rookie arrests the sergeant and the veteran during the Ledger rematch night. Then: "You're next." |

## 10. Cost and assets

- Code: one flag on the cop car, a few behaviour switches, caption lines, a hidden number. Builds on Stage F cops.
- Art: the normal cop body plus props (push bar, spotlight, grille strobes, black wheels, tint, ghost livery texture). Simple meshes or Kenney CC0; original textures.
- Sound: tuned engine voice from the per-car engine work. Captions + squelch now; voices later with offline text-to-speech (Chatterbox or Kokoro), radio filter. Squelch and static from the Sonniss GDC bundle (royalty-free, commercial, no credit). All pass the free-assets rule.

## Questions for Roy, round 2 (recommendation marked)

1. Which car props go in first? **Ghost paint, scraped push bar, spotlight, hidden strobes, dark windows (recommended)** / all of them / pick your own
2. Should the bad cops' cars be a bit faster than normal police? **Yes, a little (recommended)** / no, same speed
3. How does your proof reach the rookie? **An unsigned drop plus Dave's broadcast, you never meet him (recommended)** / he meets you once
4. After he arrests the bad cops, does the rookie come after you? **Yes, "you're next" (recommended)** / no, he lets you go once
5. Bad cop ticket: bigger than a normal ticket? **Yes, double (recommended)** / same

## Sources

- [Need for Speed Heat, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)
- [Need for Speed: Undercover, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Undercover)
- [Frank Serpico, Wikipedia](https://en.wikipedia.org/wiki/Frank_Serpico)
- [How the GTTF cops were caught, WYPR (2018)](https://www.wypr.org/wypr-news/2018-06-06/how-the-gttf-cops-were-caught-and-why-didnt-local-authorities-catch-em)
- [Drug dealers testify against Baltimore Police at trial, The Daily Record (2018)](https://thedailyrecord.com/2018/02/01/baltimore-police-trial/)
