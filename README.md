# GB10 serving stacks by Ollie

For now just **DeepSeek-V4-Flash-Vision-Exp** stack (stable, super fast, no looping, fixed vision) on a 2 x GB10.

**The most important thing**: vision-exp-stack is a **runnable and configuration at the same time**, read it, it's a pretty simple script! :)

You need the `hf` CLI. If it's missing, `up`/`heal` will print install instructions (or run `pip install "huggingface_hub[cli]"`).

<br>


## Quick start

**1. Clone this repo**

```bash
git clone <this-repo-url>
cd ollie-gb10-serving-stacks
```
<br>

**2. Set your CLUSTER_NODES in the vision-exp-stack**

**Note:** If you followed https://build.nvidia.com/spark/connect-two-sparks/stacked-sparks, they are already correct.

<br>

**3. Start serving**

```bash
./vision-exp-stack up
```

`up` will handle everything: it fetches the launcher, downloads, copies the model + image to both nodes, and starts serving. If something goes wrong try `heal` command :)

<br>


## Everything else

### Commands

| Command | What it does |
|---|---|
| `heal` | Force re-download + redistribute the model and ensure the image. Use it if a worker is missing the model/image. |
| `up` | Ensure everything is ready, then start serving and follow the head log. |
| `down` | Stop it! |
| `status` | Show node status, available KV Cache size, and the v1/models output. |
| `tail-head` | Follow the head node's log. |
| `tail-worker` | Ditto. |
| `log` | Follow compact performance stats summary (pp, decode, etc). **My favorite!** |
| `build-image` | Build a local Docker image (see below). |

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
- Don't remember where did I get speculative k=5 fix, but thank you, author! :)