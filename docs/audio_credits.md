# Audio credits

All sounds in `assets/audio/` are synthesized offline by `tools/gen_sfx.py` (Python and numpy, no samples, no
third-party audio, no recordings). They are original to this project and carry no outside licence; the project may
ship and sell them freely. Regenerate with `python3 tools/gen_sfx.py` (deterministic: each variant seeds its own RNG).

Methods: modal synthesis (decaying inharmonic partials) for steel, plate and aluminium; filtered noise bursts over
pitch-dropping sine thumps for flesh and body falls; layered noise, resonant "bubble" chirps and tiny grains for wet
cuts and gore; clustered noise clicks for bone; swept band-pass noise for whooshes; granular noise for sand and mail;
formant-filtered glottal pulses for grunts and cries; hundreds of detuned, randomised formant voices plus claps and
murmur for the crowd.

No file was taken from an external source, so there is no per-file third-party attribution to record. If one is
ever added, list it here with its source URL and licence (CC0 or public domain only).

| Folder | Sounds (variants each) |
| --- | --- |
| `assets/audio/impact/` | clang_steel, ring_steel, thunk_wood, bat_crack, bat_tink, body_thud, fist_punch, flesh_cut, flesh_pierce, bone_crack, armor_clank, mail_jingle, leather_slap, helm_knock, drop_sand, drop_sand_metal |
| `assets/audio/gore/` | sever, behead, gut, run_through, spurt_hiss, blood_spatter_sand |
| `assets/audio/move/` | whoosh_slow, whoosh_mid, whoosh_fast, footstep_sand, body_fall_sand, sand_impact, armor_rattle |
| `assets/audio/voice/` | grunt, pain_light, pain_heavy, death_gurgle (non-verbal) |
| `assets/audio/crowd/` | amb_low and amb_high (seamless loops), gasp, cheer, roar, boo, chant, finisher_roar |

Files are `<name>_<n>.wav`, 16-bit 44.1 kHz mono. `assets/audio/manifest.json` lists the variant counts.

Runtime-synthesised (not in assets/audio/): the laser sword hum, clash and sizzle are generated in `game/audio/laser_synth.gd` at load time. No samples, no outside licence.
