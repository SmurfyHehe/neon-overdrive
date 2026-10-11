# Treblo: can its songs go in a sold game? (checked 2026-10-10)

**Verdict: YES on the written terms, with two small unknowns I could not test without an account.**
Free plan is enough. No credit, no payment, no royalty, no usage restriction on songs you generate. Sold games are not excluded.

Identity confirmed: Treblo = formerly Sonauto, operator "Sonauto, Inc." (ToS header; blog post https://treblo.com/blog/sonauto-is-now-treblo, 2026-06-03). Not Trebble.

## How I fetched
Plain curl/Invoke-WebRequest got 403 on every treblo.com URL (bot block). I read the pages in the built-in browser and saved the text. Nothing signed up, nothing downloaded except page text.

| File | Source URL | Page's own date |
|---|---|---|
| tos.txt (full, ~820 lines) | https://treblo.com/tos | Dated September 22nd, 2026 |
| api-terms.txt (key clauses verbatim, 5 sections abridged) | https://treblo.com/api-terms | Dated August 20th, 2026 |
| privacy-excerpt.txt (keyword lines only) | https://treblo.com/privacy | Last updated September 22nd, 2026 |
| tool-royalty-free-music-generator.txt | https://treblo.com/tools/royalty-free-music-generator | none shown |
| home-and-faq.txt (excerpts) | https://treblo.com/ | comparison "as of September 25, 2026" |
| blog-sonauto-is-now-treblo.txt | https://treblo.com/blog/sonauto-is-now-treblo | June 3, 2026 |

Not found / not read: https://treblo.com/pricing is a 404 (no consumer pricing page; the site says free = unlimited). DMCA and Open Source Licenses pages not read (not relevant to output licence). PDFs not made.

## Roy's 10 points

| # | Test | Result | Evidence |
|---|---|---|---|
| 1 | Free plan personal/non-commercial only | **PASS** | ToS s8: "The restrictions on commercial use of the Services elsewhere in these Legal Terms do not limit Your use of Your Outputs." Tool page: "Treblo places no usage restrictions on songs made for free, including concerning commercial use." Home FAQ: "Yes, even on the free tier. We place no usage restrictions on songs you create". |
| 2 | Credit/attribution required | **PASS** (one thing to avoid) | Nothing in ToS s8 requires credit. Only attribution clause is API Terms s6: "When implementing the API in any user-facing application or service, you must prominently display an attribution link to Treblo". That is about apps that call the API. A game shipping finished WAVs from the web app is not that. Do not wire the API into the game. |
| 3 | Any fee or royalty | **PASS** | Tool page: "Treblo does not take a royalty from the songs you make". Home: "$0.00 Truly free. Unlimited songs with our latest model." |
| 4 | Treblo owns/keeps rights, or can revoke | **PASS with caveats** | ToS s8: "You own any right, title, or interest that may exist in the musical and/or audio content that You generate using the Services ("Outputs"). We hereby assign to You all our right, title, and interest, if any, in and to Your Outputs." Caveats: "to the extent permitted by applicable law"; "We make no warranties or representations regarding the Outputs, including as to their copyrightability". Treblo also keeps a non-exclusive licence: "an unrestricted, unlimited, irrevocable, perpetual, non-exclusive, transferable, royalty-free, fully-paid, worldwide license to use Your Outputs, and the prompts, lyrics ... to provide, maintain, develop, and improve the Services and our artificial intelligence and machine learning models". That is non-exclusive, it does not stop you. The revocable licence in ToS s2 is to access the Services, not the songs; ToS s15 lists s8 as surviving termination. |
| 5 | Audible watermark | **UNCLEAR** | No mention anywhere in the pages. Could only be settled by listening to a real export. |
| 6 | Content ID / copyright claims by Treblo | **UNCLEAR (low risk)** | Not mentioned. Treblo assigns its rights and says it takes no royalty, so a claim by Treblo would contradict its own terms. Third parties could still match similar-sounding songs; ToS s8 says "Outputs may not be unique". |
| 7 | Use in sold games/software prohibited | **PASS** | No such clause. ToS s6 forbids using the *Services* for commercial endeavours, but carves out outputs: "The restrictions in this paragraph do not apply to Your use of Your Outputs as described in Section 8". Home FAQ even lists "video game scores" and the tool page lists "game scene". |
| 8 | WAV/stems on the plan Roy would use | **UNCLEAR (marketing says yes)** | Home comparison table, free tier: "Downloads: All formats (OGG, MP3, WAV, FLAC, M4A)" and "stem separation" listed as a free feature. That is marketing copy, not contract text, and I could not log in to confirm the buttons. |
| 9 | Training/indemnity wording that blocks selling | **PASS, but know the liability** | Nothing blocks sale. But ToS s22: "You agree to defend, indemnify, and hold us harmless ... from and against any loss ... made by any third party due to or arising out of ... (5) your violation of the rights of a third party, including but not limited to intellectual property rights". ToS s8: "You are solely responsible for Outputs and Your use of Outputs". Treblo may train on your outputs and prompts on the web app; the API does not ("WE DO NOT USE YOUR API INPUTS OR API OUTPUTS TO TRAIN OR FINE-TUNE"). |
| 10 | Terms can change retroactively | **UNCLEAR (low risk)** | ToS intro: "Changes to Legal Terms will become effective seven (7) days after the notice is given". Terms can change going forward, and nothing says changes reach songs already made. API Terms s12 says rights in outputs generated before termination are unaffected; the web ToS has no equivalent sentence. |

## What you still need to do / watch
1. **Save the terms with the songs.** The copies in this folder are dated 2026-10-10. Keep a per-song note: date generated, prompt used. That is your proof of which terms applied.
2. **Keep prompts clean.** ToS s6 forbids using a named artist's name ("sounding like"), identifiable voices, or third-party copyrighted lyrics. A "drift phonk like <artist>" prompt breaks the terms and weakens the licence.
3. **Do the two unknown checks by hand on the first track:** (a) listen for any watermark/tag in the WAV; (b) confirm the WAV (and stems if wanted) download button exists on a free logged-in account. I was told not to sign up.
4. **Expect no copyright to enforce.** The terms disclaim copyrightability; others may get similar songs. For a soundtrack this is fine, but you may not be able to stop someone else reusing a track.
5. **Optional extra safety:** email support@treblo.com one line asking them to confirm "free-tier outputs may be used in a commercial game, no credit, no fee" and keep the reply. Not sending anything for you.

## Plan
Free account. No paid plan appears for consumers (/pricing is a 404). API credits are paid, and the API adds the "Powered By Treblo" attribution rule, so do not use the API for this.
