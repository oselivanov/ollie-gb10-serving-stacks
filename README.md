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


## Thanks

- **0rand** for inspiration
- **eugr** for spark-vllm-docker
- **PILCOTHINK** for Dockerfile
- **co-le** for prefix cache fixes and great cache pressure bench
- **stu.miller** for prefix cache fixes

- Don't remember where did I get speculative k=5 fix for Vision Exp model, but thank you, author! :)
