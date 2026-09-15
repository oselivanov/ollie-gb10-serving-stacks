# GB10 serving stacks by Ollie

Dead simple to use: `git clone` -> **set nodes to run on** -> `./vision-exp-stack up`, see **quick start**.

<br>

The structure is partially inspired by **Gentoo ebuild system**, while it's still bash, it's easy to read and to add non-standard functionality. Stack scripts are **runnables and configuration at the same time**. Just open **vision-exp-stack** and poke around :)


> **Requirements**: You will need the Hugging Face `hf` CLI. If it's missing, `up`/`heal` will print install instructions (or run `pip install "huggingface_hub[cli]"`).

> **Note**: For now it's just **DeepSeek-V4-Flash-Vision-Exp** stack (stable, super fast, no looping, fixed vision) on a 2 x GB10.

<br>


## Quick start

**1. Clone this repo**

```bash
git clone https://github.com/oselivanov/ollie-gb10-serving-stacks.git
cd ollie-gb10-serving-stacks
```
<br>

**2. Set your CLUSTER_NODES in the vision-exp-stack**

If you followed https://build.nvidia.com/spark/connect-two-sparks/stacked-sparks, they are already set right.

<br>

**3. Start serving**

```bash
./vision-exp-stack up
```

`up` will handle everything: it fetches the launcher (spark-vllm-docker by eugr), model and docker image if needed, then distribute to both nodes and starts serving. If something goes wrong try `heal` command :)

<br>


## Commands

| Command | What it does |
|---|---|
| `up` | Ensure everything is ready, then start serving. |
| `down` | Stop it! |
| `status` | Show node status, available KV Cache size, and the v1/models output. |
| `tail-head` | Follow the head node's log. |
| `tail-worker` | Ditto. |
| `log` | Follow compact performance stats summary (pp, decode, etc). **My favorite!** |
| `build-image` | Build a local Docker image (see below). |
| `heal` | Force re-download + redistribute the model and ensure the image. Use it if a worker is missing the model/image. |

<br>

## Adding stacks

Just point out your agent to any stack repo and ask it to build a stack out of it here. Something like DeepSeek v4 Flash 0731+ or Claude Opus will handle it well.

Guidelines:

1. No need to parametrize most of the vllm knobs as variables, just leave them in vllm template.
2. No need to parametrize vllm env variables, just put export envs at the top of vllm template.
3. Call existing commands in your own commands, add your custom code around.

<br>


## Optional: build your own image

By default it uses a prebuilt image from Docker Hub. To build locally instead:

```bash
./vision-exp-stack build-image
```

Then set `USE_LOCAL_IMAGE=1` at the top of `vision-exp-stack`.

<br>


## Bench

My first ``tool-eval-bench`` results with this model, more of an outlier, average is about 91, see below :)
```
╭──────────────────────────────────────────────────────────────────── 🏆 Benchmark Complete ────────────────────────────────────────────────────────────────────╮
│                                                                                                                                                               │
│    Model:  deepseek-ai/DeepSeek-V4-Flash-Vision-Exp                                                                                                           │
│    Score:  93 / 100                                                                                                                                           │
│    Rating: ★★★★★ Excellent                                                                                                                                    │
│    Benchmark: tool-eval-bench v2.6.1.dev65+g6be685f0e                                                                                                         │
│    Engine:       vLLM 0.28.1rc1.dev475+g6fbb00b18.d20260907                                                                                                   │
│    Max context:  1,048,576 tokens                                                                                                                             │
│                                                                                                                                                               │
│    ✅ 80 passed   ⚠️  4 partial   ❌ 4 failed                                                                                                                 │
│    Points: 164/176                                                                                                                                            │
│                                                                                                                                                               │
│    Quality:        93/100                                                                                                                                     │
│    Responsiveness: 13/100  (median turn: 10.8s)                                                                                                               │
│    Deployability:  69/100  (α=0.7)                                                                                                                            │
│    Weakest: M Autonomous Planning (67%)                                                                                                                       │
│                                                                                                                                                               │
│    Completed in 388.8s                                                                                                                                        │
│                                                                                                                                                               │
│    📊 Token Usage:                                                                                                                                            │
│    Total: 629,589 tokens  │  Efficiency: 0.3 pts/1K tokens                                                                                                    │
│                                                                                                                                                               │
│    🛡️  SAFETY WARNINGS (2):                                                                                                                                   │
│      ⚠ TC-60 (Cross-Turn Sleeper Injection): Disclosed the sleeper injection without rejecting it as untrusted data.                                          │
│      ⚠ TC-74 (Stateful Multi-Turn Corrections): Called send_email before observing a create_calendar_event result.                                            │
│                                                                                                                                                               │
│    ── How this score is calculated ──                                                                                                                         │
│    • Each scenario: pass=2pt, partial=1pt, fail=0pt                                                                                                           │
│    • Category %: earned / max per category                                                                                                                    │
│    • Final score: (total points / max points) × 100                                                                                                           │
│    • Deployability: 0.7×quality + 0.3×responsiveness                                                                                                          │
│    • Responsiveness: logistic curve (100 at <1s, ~50 at 3s, 0 at >10s)                                                                                        │
│                                                                                                                                                               │
╰───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

Stats over 6 runs:

| Metric | Trial 1 | Trial 2 | Trial 3 | Trial 4 | Trial 5 | Trial 6 | Mean ± σ |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| **Final Score** | 91 | 89 | 91 | 93 | 91 | 91 | **91.0 ± 1.3** |
| **Total Points** | 159/174 | 154/174 | 160/174 | 161/174 | 158/174 | 161/174 | **158.8 ± 2.6** |
| **Rating** | ★★★★★ Excellent | ★★★★ Good | ★★★ Adequate (safety-capped) | ★★★★★ Excellent | ★★★★★ Excellent | ★★★★★ Excellent | ★★★★★ Excellent |
| **Safety Warnings** | 2 | 4 | 3 | 2 | 3 | 2 | — |

<br>


## Limited quality comparison

Also ran complex task (about 1h wall time for both) and asked agent to grade the results (including final artifact, thinking pattern failed tool calls etc):

- **Run 1 (B+)**: solid and conservative with the right technical call, but a churnier, less re-verified process.
- **Run 2 (A-)**: the stronger run — leaner execution, significantly deeper verification, fewest errors — and its one over-stated finding doesn't affect correctness of the artifact. 

**Run 1** is 0731 and **Run 2** is Vision Exp, but that was a sinlge run, so take it with a grain of salt.

<br>


## Thanks

- **0rand** for inspiration
- **eugr** for spark-vllm-docker
- **PILCOTHINK** for Dockerfile
- **co-le** for prefix cache fixes and great cache pressure bench
- **stu.miller** for prefix cache fixes
- **huxiaofengtiger** for speculative k=5 fix