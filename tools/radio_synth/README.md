# radio_synth
Deterministic (seeded) generator for the radio tracks.
Needs: Python 3, numpy, scipy, ffmpeg with libvorbis.

    python render_all.py [drift|dark|synthwave]
    RADIO_OUT=../../assets/radio python render_all.py

Sections: I intro, V verse, B break, D drop, O outro. 2x oversampling.
Files: synth.py (instruments/FX), synth2.py (master + refined voices), synth3.py (plan-driven generators), render_all.py (track specs + export).

Output: Vorbis q3 at 32 kHz (loudnorm I=-16, TP=-1.5). Set FFMPEG=/path/to/ffmpeg if it is not on PATH.
