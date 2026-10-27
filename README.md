# bun --compile --aot vs CRIU on arm64

A process started from a `bun build --compile --aot` executable ([oven-sh/bun#45631](https://github.com/oven-sh/bun/pull/45631)) can't be checkpointed with [CRIU](https://criu.org) on arm64. CRIU fails with `Can't rmap memfd for parasite blob` and then segfaults. The same server checkpoints fine when run with `bun` or from a plain `--compile` executable, and on x64 all three work.

## Run it

You need Docker on Linux, or Docker Desktop on a Mac. Checkpointing needs `--privileged`, and the bug needs an arm64 host, such as an Apple silicon Mac or a Graviton instance:

```sh
docker build -t bun-aot-criu .
docker run --rm --privileged bun-aot-criu
```

Without Docker, on Linux as root with CRIU installed and `bunx bun-pr 45631` run:

```sh
./repro.sh /path/to/bun-45631
```

[CI](../../actions/workflows/repro.yml) runs the Docker version on GitHub's x64 and arm64 runners.

## What it does

[`repro.sh`](repro.sh) builds [`hello.ts`](hello.ts), a one-line `Bun.serve`, in two ways: `--compile` and `--compile --aot`. It starts the server three times (with `bun`, then each executable), sends one request to each, and runs `criu dump`. It exits 1 if any dump fails.

## Results

x64 (Docker Desktop, kernel 6.12.76-linuxkit, CRIU 4.3, bun 1.4.4-canary.1+606f4485a):

```
bun: dump OK
compile: dump OK
aot: dump OK
```

arm64 (AWS m6g.large, Graviton2, Ubuntu 24.04, kernel 7.0.0-1014-aws, CRIU 4.3, bun 1.4.4-canary.1+72ab4f530):

```
bun: dump OK
compile: dump OK
Segmentation fault (core dumped) criu dump ...
aot: dump FAILED
(00.006609) Parasite syscall_ip at 0x1c0f000
(00.006709) Error (compel/src/lib/infect.c:876): Can't rmap memfd for parasite blob
```

## What we know

- To checkpoint a process, CRIU runs a few syscalls inside it so it can map its own helper code there. In the AOT process, `memfd_create` succeeds. The `mmap` that follows, mapping that memfd `MAP_SHARED` with `PROT_READ|PROT_EXEC`, returns an error. CRIU 4.3 doesn't log which error ([`remote_mmap`](https://github.com/checkpoint-restore/criu/blob/v4.3/compel/arch/aarch64/src/lib/infect.c#L201)).
- The process has no seccomp filter (`Seccomp: 0`). VmSize is 39 GB and RSS 21 MB.
- The AOT executable is mapped at a fixed low address. Its first executable mapping, where CRIU places its syscall instruction, is a single 4 KB page. Code is also mapped from the file at a high address:

```
00200000-00240000 r--p 00000000  hello-aot
007e0000-01960000 r--p 00040000  hello-aot
01bf0000-01bfb000 r--p 011c0000  hello-aot
01c0f000-01c10000 r-xp 011cf000  hello-aot
05840000-087ba000 r-xp 011d0000  hello-aot
...
1e76a4540000-1e76a4580000 r-xp 04200000  hello-aot
```
