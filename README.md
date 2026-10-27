# bun --compile --aot vs CRIU on arm64

A process started from a `bun build --compile --aot` executable ([oven-sh/bun#45631](https://github.com/oven-sh/bun/pull/45631)) can't be checkpointed with [CRIU](https://criu.org) on arm64. CRIU fails with `Can't rmap memfd for parasite blob` and then segfaults.

**Cause:** at startup the AOT executable turns on memory-deny-write-execute: `prctl(PR_SET_MDWE, PR_MDWE_REFUSE_EXEC_GAIN)`. To checkpoint a process, CRIU maps its parasite code into it. On arm64 it maps that code read-write-execute, and under MDWE the kernel refuses with `EACCES`. On x64, CRIU maps the parasite read-execute, so x64 works. A 10-line C program that only turns on MDWE ([`mdwe.c`](mdwe.c)) fails the same way on arm64. So any MDWE process hits this, not only Bun.

## Run it

You need Docker. Checkpointing needs `--privileged`, and the failure needs an arm64 host, such as an Apple silicon Mac or a Graviton instance:

```sh
docker build -t bun-aot-criu .
docker run --rm --privileged bun-aot-criu                # repro.sh: dump five processes
docker run --rm --privileged bun-aot-criu ./diagnose.sh  # trace the mmap CRIU injects
```

[CI](../../actions/workflows/repro.yml) runs both on GitHub's x64 and arm64 runners.

## What it does

- [`repro.sh`](repro.sh) starts five processes and runs `criu dump` on each. It exits 1 if any dump fails.
  - [`hello.ts`](hello.ts), a one-line `Bun.serve`, three ways: run by `bun`, built with `--compile`, and built with `--compile --aot`.
  - [`mdwe.c`](mdwe.c), a sleeping process, with and without MDWE.
- [`diagnose.sh`](diagnose.sh) checkpoints the AOT executable while tracefs records its `memfd_create` and `mmap` calls.

## Results

From [CI](../../actions/workflows/repro.yml), with CRIU 4.3 (from the CRIU PPA), Ubuntu 24.04 in Docker, and bun `1.4.4-canary.1+db149bafa`.

| `criu dump` of | x64 (kernel 6.17) | arm64 (kernel 7.0) |
|---|---|---|
| `bun hello.ts` | OK | OK |
| `--compile` executable | OK | OK |
| `--compile --aot` executable | OK | **fails**, CRIU segfaults |
| `mdwe` (no MDWE) | OK | OK |
| `mdwe on` (MDWE) | OK | **fails**, CRIU segfaults |

arm64 log:

```
aot: dump FAILED (criu exit 139)
(00.022270) Parasite syscall_ip at 0x1bb1000
(00.022403) Error (compel/src/lib/infect.c:876): Can't rmap memfd for parasite blob
c-mdwe: dump FAILED (criu exit 139)
(00.022033) Parasite syscall_ip at 0xaae4f7a40000
(00.022158) Error (compel/src/lib/infect.c:876): Can't rmap memfd for parasite blob
```

`diagnose.sh` shows the call CRIU makes inside the AOT process. Read-execute (`prot: 5`) succeeds on x64; read-write-execute (`prot: 7`) fails on arm64 with -13, `EACCES`:

```
x64:   sys_mmap(addr: 0, len: 95799c0, prot: 5, flags: 1, fd: 7, off: 0)
       sys_mmap -> 0x7f38174f2000
arm64: sys_mmap(addr: 0, len: 0x9578980, prot: 7, flags: 1, fd: 7, off: 0)
       sys_mmap -> 0xfffffffffffffff3
```

The AOT executable turns on MDWE at startup (`strace -f -e prctl`, x64):

```
prctl(PR_GET_MDWE, 0, 0, 0, 0)    = 0
prctl(PR_SET_MDWE, PR_MDWE_REFUSE_EXEC_GAIN|PR_MDWE_NO_INHERIT, 0, 0, 0) = 0
```

## Where the protection comes from

CRIU's [`compel_map_exchange`](https://github.com/checkpoint-restore/criu/blob/v4.3/compel/src/lib/infect.c#L957) maps the parasite `PROT_READ | PROT_EXEC` when the parasite blob has a separate data section (`hdr.data_off`), and `PROT_READ | PROT_WRITE | PROT_EXEC` when it doesn't. The trace above shows which one each architecture gets.

[`remote_mmap`](https://github.com/checkpoint-restore/criu/blob/v4.3/compel/arch/aarch64/src/lib/infect.c#L201) doesn't log the error, and CRIU then segfaults.
