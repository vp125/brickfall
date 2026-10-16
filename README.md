# Shardfall

A neon crystal Breakout game made with Godot 4. No art or audio files: every visual is drawn with shaders and every sound is synthesised at startup.

**Play it in the browser:** https://vp125.github.io/brickfall/
(On a phone, turn it sideways. Tap to launch, drag anywhere to move the paddle.)

## Features
- 7 levels, the last one a boss fight (The Prism) with three phases and aimed bolts
- Crystal bricks that shatter into shards; multi-hit bricks lose layers with a ring effect
- Armored (steel) bricks that never break, explosive bricks that chain
- Paddle shrinks every level; wide-paddle and multi-ball power-ups
- Procedural ambient music and sound effects
- Top-10 high score list with initials
- Touch controls (relative drag), larger buttons on phones, low-quality mode

## Controls
| Action | Desktop | Touch |
|---|---|---|
| Move | Mouse or arrow keys / A D | Drag anywhere |
| Launch / continue | Space or click | Tap |
| Pause | P | Pause button |
| Mute | M | Speaker button |
| Graphics low/high | G (or button while paused) | Button while paused |

## Run from source
Open `project.godot` in Godot 4.3 or newer and press F5.

## Web build
Export preset "Web" (single-threaded, so it runs on GitHub Pages and iOS Safari). The published build lives on the `gh-pages` branch.

## Levels
Edit `LEVELS` at the top of `main.gd`. Row strings: `.` empty, `1`-`3` hits to break, `A` armored, `X` explosive.
