# WildMinds

WildMinds is a 2D PyGame survival sandbox where the creatures are driven by a local AI model instead of fixed enemy scripts.

Each wolf, boar, and scavenger gets a compact world summary, its own short memory, its current needs, and a personality prompt. The model chooses a high-level action such as `attack`, `stalk`, `forage`, or `flee`, and the game carries that action out in real time.

## What Makes It Different

- Local AI-driven creatures through `Ollama`
- Automatic hardware check and model selection
- Smooth background AI decisions so gameplay stays responsive
- Named creatures with visible action logs
- Survival systems for hunger, energy, gathering, combat, and campfires

## Requirements

- Python `3.10+`
- `Ollama` installed locally if you want live local-model creatures

If `Ollama` is unavailable, the game falls back to rule-based survival behavior instead of crashing.

## Install

```powershell
python -m pip install -r requirements.txt
```

## Run

```powershell
python main.py
```

## Headless Smoke Test

```powershell
python main.py --headless-smoke --frames 90
```

## Automated Tests

```powershell
pytest -q
```

## Controls

- `WASD`: move
- `E`: gather nearby resource
- `Space`: attack
- `Q`, `1`, or `Enter`: eat a berry
- `F`: place a campfire

## Local AI Notes

The game tries to:

1. detect your hardware
2. pick a suitable local model
3. start `Ollama` if needed
4. pull the model if it is missing

On mid-range hardware, the current selector usually prefers `llama3.2:3b`.
