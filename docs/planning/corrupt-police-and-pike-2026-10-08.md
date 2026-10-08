# Corrupt police and Pike: story and gameplay proposal (2026-10-08, rev 4, final)

Status: DECIDED by Roy (rounds 1-3, 2026-10-08), except what the rookie does about the player at the end (open, 7b). Docs only. Nothing is built. Story is Roy's to write; every name is a placeholder. Police are Stage F, so this shapes Stage F and the story, it does not jump ahead of them.

**Roy's ask (2026-10-08 12:29):** some police are corrupt and work with Pike. They side with Pike but also hate the player, because Pike uses racers against the player. Research it.

Inputs read: `docs/story-bible.md` (main 09455e0), narrative fabric (PR #175, section 9 Pike), sound research section 7 police voices (PR #216), heat helicopter proposal (decided 2026-10-08: top heat only, spots only, escapes by driving), gas station decisions (Pike clues at stations, item 23), living-world notes (police crackdown, scanner).

## Decided (Roy, 2026-10-08 12:45)

1. **Why they serve Pike:** Pike is trying to take over everything. The bad cops get paid, and he owns their debts.
2. **You can spot a bad cop** by menacing items on their cars. We need **distinct corrupt police cars** (section 5).
3. ~~When bad cops catch you, they take the cash and give you a ticket.~~ Replaced in round 2, answer 5.
4. Bad cops do **not necessarily** back off when someone is watching. Witnesses are not a guaranteed escape.
5. **Pike's racers set you up:** yes.
6. **The rookie can be won over**, but he must keep the moral high ground and never team up with racing criminals (the player). Research how (section 7).
7. **The bad cops are the sergeant and his partner.** From the sound questions, the **veteran** is also Pike's man, so the veteran is the sergeant's partner.
8. **The story ends with the bad cops exposed.**

## Decided (Roy, 2026-10-08 12:53), round 2

1. **Car parts as proposed** (ghost paint, scraped push bar, spotlight, hidden strobes, dark windows), **plus different, scary lights**: the reaction should be "oh f***". Light design in section 5b.
2. **Bad cop cars are faster:** yes. Where they are placed needs judging (section 5c).
3. **The rookie meets you in private**, and also learns about you over time through Dave's broadcast (section 7).
4. **Whether the rookie comes after you at the end is OPEN.** Roy: a big question that could break the story. Not decided here; risks in section 7b.
5. **Bad cops take ALL the cash; honest cops take little or none.** The ticket is **not** assumed: research the real differences between good and bad cops first (section 6a). This replaces round-1 answer 3 ("cash and a ticket").

## Decided (Roy, 2026-10-08 13:08), round 3

1. **Honest cops catch you:** a ticket paid from your **bank**, plus a **tow fee that depends on your heat level**. You keep tonight's cash.
2. **Bad cops catch you:** they take **all** tonight's cash and write **no ticket** (no trail).
3. **Honest cops give up** a chase that gets too dangerous for traffic; **bad cops never give up**.
4. **The scare:** bad cops creep up with lights off, then hit you with everything at once, **with their own different lights** (section 5b).
5. **Hiding spots:** yes, and they can be **anywhere** on the map (still never on a road with no way out).
6. **The rookie only takes proof got legally, and that is part of the story** (section 7).

Earlier decisions kept: police voice lines are **captions + squelch now**, voices later (offline text-to-speech that passes the free-assets rule: Chatterbox MIT, Kokoro Apache 2.0). The police radio cast keeps its five roles. Pike takes Cred, never cars, mods or progress.

## One line

**Pike owns two cops, and you can see it on their cars.** The sergeant and his veteran partner drive marked-but-wrong police cars paid for with Pike's money, go quiet on the radio when they come for you, and take all your cash. An honest rookie works to bring them down and meets you in private, but never becomes your partner.

## Steelman and premortem

- Steelman: a small, named pair of bad cops with their own cars makes the corruption personal and readable. The player learns to dread one silhouette in the mirror, and the ending (exposing them) is a clear goal.
- Premortem, it failed because:
  1. Players could not tell bad cops from honest ones. Fix: the cars look different (section 5) and the radio goes quiet. Two tells, one you see and one you hear, no HUD marker.
  2. Bad cops felt unfair. Fix: they only ever take tonight's unbanked cash, and they can always be outdriven.
  3. The rookie read as the player's buddy, breaking Roy's rule. Fix: he meets you only on his terms, takes nothing, never helps you escape (section 7).
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

**Chosen set for the first build (Roy):** ghost livery, scraped push bar, A-pillar spotlight, grille strobes with no roof bar, dark tint. The rest come later.

### 5b. The lights: the "oh f***" moment (Roy: different and scary)

The scare is a **contrast**: a dark, silent car becomes a wall of light and noise all at once, inside your mirror. Built in layers:

| Layer | What happens | Why it scares |
|---|---|---|
| **1. Dark run** | They tail you with **headlights off**. In the mirror you see nothing but a faint shape against the streetlights, and you hear a tuned engine that is not yours | You feel something is there before you can see it |
| **2. The hit** | At about 20-30 m everything comes on in the same frame: high beams, the A-pillar spotlight swung straight into your rear window, grille and rear-window strobes | Sudden white glare fills the mirrors and the cockpit; a jump scare you earned by being careless |
| **3. Wig-wag headlights** | Their headlights alternate left-right fast (real police "wig-wag" flashers) | Aggressive, reads as "pull over now" even at a glance |
| **4. Red-heavy strobes** | Honest cars flash an even red and blue. Bad cars flash **mostly red** in a **fast, broken, irregular** rhythm, with only a little blue | Red reads as danger; the broken rhythm looks wrong, like a glitch |
| **5. The rumble** | Instead of a normal wail, one burst of a **deep, low siren you feel more than hear**, then silence. Real police use this: the Federal Signal **Rumbler** drops the siren tone by 75% and shakes nearby cars for about 8 s ([Federal Signal](https://www.fedsig.com/product/rumbler)) | The cockpit shakes (camera shake, bass in the speakers). Nothing else in the game sounds like it |
| **6. Red cabin glow** | A dim red light inside their cabin shows a faceless shape behind the tint | Faceless, wrong colour, very PS2-horror |

In first person the spotlight and wig-wags hit the cockpit glass and mirrors (bloom and glare), which is where the scare lands hardest. Cost: lights and a mirror glare pass the game needs anyway; a low synth sine burst for the rumble (original, no asset licence needed). Honest cars keep their normal steady pattern and normal wail, so the difference is obvious.

### 5c. Where the bad cars show up (Roy: faster, placement needs judging)

They are a little faster than honest police (Pike's money), so where they appear decides whether they are fair. Proposed rules:

| Rule | Why |
|---|---|
| **Only one bad pair in the world at a time**, and only when the hidden "Pike reach" number allows it | Keeps them special and scary, not common |
| **Lurk spots anywhere on the map (Roy)**: parked dark with cover, such as a closed lot, under an overpass, behind a billboard, a canyon pull-off, the docks, a downtown side street. You can see them before they move if you look | Gives the player a fair chance to notice and pick another road |
| **Never spawn in front of you on a straight you cannot leave**; always where there is a side street or exit | Being faster must not mean "no way out" |
| **Sent by Pike's racers** (tip-off, setup race): they arrive from behind, from the direction the tip came | The setup feels like a setup, not a random spawn |
| **Faster on straights, worse in tight turns** (heavy push bar) | The counterplay is choosing twisty roads |
| **Story nights** place them by hand (the shakedown in Act 1, the Turn at the liquor store) | Story beats happen where Roy wants them |

## 6. How bad cops play differently

| | Honest cops (incl. rookie) | The sergeant and the veteran |
|---|---|---|
| **Radio** | Call everything in; captions describe the chase | **Go quiet.** Captions show the dispatcher asking "Unit 12, say your location... Unit 12?" with no answer |
| **Driving** | Follow, box, roadblock at high heat | Ram and push early, spotlight you, ignore "pursuit called off". A little faster (tuned engines) |
| **Where they show up** | Anywhere you break the law in their sight | Wherever Pike's racers send them (R1, R2). More often at night in docks, back roads and the canyon, but they **can come anywhere** |
| **Witnesses** | n/a | **Not a guaranteed escape** (Roy). They are a bit more careful near the helicopter, but they do not simply leave |
| **When they catch you** | **Arrest by the book** (options in 6a): little or no cash taken | **Shakedown:** they take **all of tonight's unbanked cash**. No paperwork assumed (6a). Cash goes to Pike |
| **How to beat them** | Driving, the escapes from the helicopter design | Out-drive them. They are faster but heavier; the push bar makes them worse in tight turns. Lose the spotlight with hard turns and cover, like the helicopter beam |

### 6a. Good cops and bad cops: what really differs (Roy: research, do not assume a ticket)

What an honest US officer does, from current policy guidance and how the real corruption cases were caught:

| Thing | Honest officer (procedure) | Corrupt officer (the real cases) |
|---|---|---|
| **Starting a chase** | Many departments now limit pursuits. The Police Executive Research Forum (2023) recommends chasing only when a violent crime has happened and the driver is an immediate danger; otherwise find another way, "you can get a suspect another day" ([Police1 on the PERF report](https://www.police1.com/suspect-pursuit/articles/perf-report-recommends-limiting-police-pursuits-to-violent-crimes-suspects-who-pose-imminent-threats-Am1uwNdLFpoXkIr1)) | Chases whoever they are told to, for as long as they want |
| **Ending a chase** | Calls it off when it gets too dangerous (traffic, speed, people around). Supervisor can order it ended | Ignores "call it off" |
| **Radio** | Reports everything: where, what car, what for | Goes quiet; nothing on the record |
| **Cameras** | Dashcam and body camera on | Cameras "off" or "broken" |
| **Money** | Does not take your cash. If cash is seized as evidence, it is logged and you get a receipt | Takes it, no receipt, no record (Baltimore unit robbed people during stops and searches) |
| **Paper** | Writes the ticket or report for what you did; it goes to court | Avoids paper, because paper is evidence against them. A ticket would show they stopped you |
| **Force** | The minimum needed | Rams, threatens, hurts |
| **Afterwards** | Your record shows the offence | Nothing on record, but they remember you |

**What this means for the game.** A corrupt cop writing a ticket would leave a trail, so the realistic bad-cop catch is **cash gone, no paper**. That also makes the difference clean: honest cops cost you **a ticket**, bad cops cost you **your cash**.

Options for the honest arrest. **Decided (round 3): H2 with the tow fee scaled by heat level.**

| Option | Honest cops catch you | Bad cops catch you |
|---|---|---|
| H1. Ticket only | A ticket (fine taken from your **bank** at the garage, size by what you did). You **keep** tonight's cash | All tonight's cash, no ticket |
| **H2. Ticket + tow fee (DECIDED)** | Ticket from your bank plus a tow fee that grows with heat level; cash kept | Same as above |
| H3. Small cut | A share of tonight's cash (say a quarter) as a fine on the spot | All of it |

Result: the two kinds of cop hurt you in two different ways the player can feel (honest: your bank; bad: tonight's pot). Stage C's "bust loses the pot" rule now applies to bad cops only; honest busts cost ticket + tow from the bank.

Honest cops also **call off** a chase that gets too dangerous for traffic (the policy above), which bad cops never do. In play: if you are fast and the roads are busy, honest cops give up sooner. Bad cops never give up, which is part of the fear.

**Getting proof:** escaping a shakedown, or getting a bad cop into the helicopter's beam, earns a clue (a dashcam still, a plate, a number). Clues join the gas station clues for the Pike story.

## 7. The rookie: winning him over without him joining you (Roy: research)

**Roy's rule:** the rookie keeps the moral high ground. He does not team up with racing criminals, and the player is a racing criminal.

**What the research says:** honest insiders who bring down corrupt cops usually **go around the department, not to criminals**. Serpico reported inside, was ignored, and went to the press; the Baltimore unit fell to federal investigators. In both, the honest side never worked with the people breaking the law.

**Roy's call (round 2): he meets you in private, and he also learns about you over time through Dave's broadcast.** So the rookie and the player meet, but they are **never partners**. He is won over to the **truth**, not to the player. How he keeps the high ground while meeting you:

| Rule for every meeting | Why it keeps his high ground |
|---|---|
| **He sets the meeting**, not you: a note under your wiper, "Diner, 5 a.m., come alone" | He is in control; you do not recruit him |
| **He meets you as a cop meets a witness**, in uniform or off duty, never in a race car, never at a meet | He questions you; he does not hang out |
| **He takes nothing from you**: no money, no favours, pays for his own coffee | Nothing anyone could call a bribe |
| **He only takes proof he can use by the book** (decided, and part of the story): dashcam footage from a public road, a plate, a time and place. Anything you got by breaking in or stealing, he refuses, and the story can turn on it: one piece of proof you got the wrong way is useless, so you have to get it again the right way | A real limit that shapes what you collect |
| **He says what he will not do**: "I won't look the other way for you. Not once." | Said out loud, so the player knows the line |
| **He never warns you about honest police**, never helps you escape, never races | He stays on the side of the law |

**How he learns about you over time (Dave's broadcast):** the rookie is a listener. Dave reads out things that happen in your nights: a shakedown on a dark road, a racer's car with Pike's money in it, "a listener" who caught a cop car with no plates on camera. The rookie pieces it together like a detective, and his radio captions show it ("Dispatch, was there a stop on Pier Road at two? ... No record? Copy."). The meetings come only after he already suspects.

**How it plays out (proposed beats, Roy writes the words):**
1. **Act 1:** the rookie chases you like any honest cop. Good, polite on the radio, never lets you go.
2. **Act 2:** Dave's broadcasts about shakedowns get his attention. He notices the sergeant and the veteran keep going quiet, asks about it, is told to drop it.
3. **The Turn:** like Serpico, the bad cops leave him without backup in a dangerous moment. He survives. Next night, the note on your wiper: first private meeting. He tells you what he wants (proof he can use) and what he will never do.
4. **Act 3:** you bring him proof in two or three short meetings, each one tense. He never thanks you. On Dave's show you hear the effect: a stop "with no record" now has one.
5. **Ending:** the rookie arrests the sergeant and the veteran. **What he does about you next is open** (7b).

### 7b. Open: what the rookie does about you at the end (Roy: could break the story)

Not decided. Each option and how it could hurt the story:

| Option | What happens | Story risk |
|---|---|---|
| He comes after you ("you're next") | Arrests the bad cops, then turns on you; a final chase or a warning | Can make the win feel hollow, and makes all your help feel like it was used against you. Also clashes with "the shop is saved" if you end in cuffs |
| He lets you go once | "Tonight you get a head start. Next time, no." | Bends his high ground at the very end, the thing Roy wants protected |
| He does nothing about you | Arrests them and walks away; you never see him again | Safe but flat; wastes a strong character |
| He becomes your honest rival after the story | Free roam after the ending: he leads the honest police, a fair, tough cop who chases you | Keeps his high ground and gives free roam a face; needs the post-ending free play to exist (it does: legends reunion) |

Whatever is picked, two rules protect the story: the rookie never gets paid back for the meetings, and the ending never takes the shop or the car away because of him.

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
| Act 1 | First shakedown: cash gone, no paper. Dave on air: "funny, no record of any stop on Pier Road last night" |
| Act 2 | Pike's racers start the tip-offs and setup races. The rookie starts asking questions |
| Turn | The night Dave's tower goes silent: the sergeant's car is outside the liquor store with Ironbridge's cars. The rookie is left without backup; next night, his note on your wiper |
| Act 3 | Private meetings: you bring proof he can use by the book. Dave's show carries the rest |
| Ending | The rookie arrests the sergeant and the veteran during the Ledger rematch night. What he does about you: open (7b) |

## 10. Cost and assets

- Code: one flag on the cop car, a few behaviour switches, caption lines, a hidden number. Builds on Stage F cops.
- Art: the normal cop body plus props (push bar, spotlight, grille strobes, black wheels, tint, ghost livery texture). Simple meshes or Kenney CC0; original textures.
- Sound: tuned engine voice from the per-car engine work. Captions + squelch now; voices later with offline text-to-speech (Chatterbox or Kokoro), radio filter. Squelch and static from the Sonniss GDC bundle (royalty-free, commercial, no credit). All pass the free-assets rule.

## Still open

- What the rookie does about the player at the end (section 7b). Roy: could break the story; decide when the story is written.
- Names, dialogue and the exact story beats are Roy's to write.

## Sources

- [Need for Speed Heat, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed_Heat)
- [Need for Speed: Undercover, Wikipedia](https://en.wikipedia.org/wiki/Need_for_Speed:_Undercover)
- [PERF report recommends limiting police pursuits, Police1 (2023)](https://www.police1.com/suspect-pursuit/articles/perf-report-recommends-limiting-police-pursuits-to-violent-crimes-suspects-who-pose-imminent-threats-Am1uwNdLFpoXkIr1)
- [Rumbler low-frequency siren, Federal Signal](https://www.fedsig.com/product/rumbler)
- [Frank Serpico, Wikipedia](https://en.wikipedia.org/wiki/Frank_Serpico)
- [How the GTTF cops were caught, WYPR (2018)](https://www.wypr.org/wypr-news/2018-06-06/how-the-gttf-cops-were-caught-and-why-didnt-local-authorities-catch-em)
- [Drug dealers testify against Baltimore Police at trial, The Daily Record (2018)](https://thedailyrecord.com/2018/02/01/baltimore-police-trial/)
