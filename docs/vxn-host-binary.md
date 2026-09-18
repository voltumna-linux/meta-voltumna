# Running a host binary inside a vxn DomU

vxn's `run-host` mode takes an ordinary binary off the host, gathers its
runtime dependency closure, and executes it inside a Xen DomU. The DomU
gets the binary + every shared library it needs + the ELF interpreter,
laid out as a mini-rootfs the guest mounts directly. This gives you
VM-strength isolation for a workload you did not necessarily produce as
an OCI image.

Concrete demo target: pick up a large interactive CLI (say a Node-based
agent, or a native-code compiler / linter) from the host and run it as
one process inside a DomU with its own kernel and memory limits.

## The problem

A host binary is normally dynamically linked against:

1. **An ELF interpreter** (`/lib64/ld-linux-x86-64.so.2` on x86_64 glibc).
2. **The host's glibc + shared library closure.**
3. **Runtime files** — CA certs, `/etc/resolv.conf`, an `$HOME`, and any
   secrets or config the workload reads.

To run that binary in an arbitrary DomU rootfs (say an Alpine/musl base),
you need to satisfy those three yourself, and the DomU base cannot be
trusted to have a compatible libc. `arch(binary)` must match `arch(DomU)`
... an x86_64 binary needs an x86_64 DomU.

## The approach

Three plausible ways to get a binary into a DomU:

| Approach | What | Fits |
|---|---|---|
| A. static / self-contained | one file, stage + exec | Go static, Node SEA, AppImage |
| B. dependency-closure carry | binary + `ldd` closure + interpreter; exec via the *carried* loader | any dynamically-linked host binary; DomU base irrelevant |
| C. bake an OCI image | build image on host with binary+deps, `vxn run` it | clean packaging, per-binary build step |

**B is the answer.** Because the host's own glibc + loader are carried
into the guest and the host and DomU arch match, execution is
self-consistent regardless of what the DomU rootfs contains.
(This is the same approach the `exodus` tool uses.)

## What vxn already provides

`vxn-init.sh`'s `find_container_rootfs` has a **direct-mount branch**:
if the input disk contains `bin/` or `usr/` at the top level, it is used
as the container rootfs directly — no OCI extraction. So a dependency
closure laid out as `{bin/, lib/, lib64/, usr/lib/...}` is already a
valid vxn container without any image build.

| Need | Existing vxn mechanism |
|------|------------------------|
| get files into the DomU | input disk (direct-rootfs) or `-v` volume or a read-only 9p share |
| overlay files into the container rootfs pre-exec | `vxn-init.sh install_domu_ca_certs` hook (same spot) |
| interactive I/O | `vxn -it` over `ssh -tt` to dom0 |
| outbound network + TLS | dom0 NAT + DomU-inherits-dom0-CA |
| env / workdir | `-e` / `-w` already parsed |

The new work is: (1) host-side closure gathering, (2) staging the mini-
rootfs, (3) a writable workspace so the workload's file writes make it
back to the host.

## Command surface

```bash
vxn run-host -it -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
             -v "$PWD:/work" -w /work \
             "$(command -v claude)"
```

Under the hood:

1. **Host** — resolve `<binary>` to its real executable (follow wrappers).
   Compute its closure via `ldd` (the `.so` list + the interpreter). Lay
   out as a mini-rootfs preserving the host paths:

   ```
   /bin/<name>                         (the binary)
   /lib/, /lib64/, /usr/lib/...        (the .so closure)
   /lib64/ld-linux-x86-64.so.2         (the interpreter)
   /etc/{resolv.conf,nsswitch.conf}    (minimal)
   ```

2. Hand that directory to vxn as the direct-mount input.
3. **DomU** — `exec /bin/<name>` (paths are preserved, so the carried
   loader at its canonical location resolves the carried libs).
4. Compose with `-it` for interactive, `-e KEY=val` for secrets, and a
   read-write `-v` mount so the workload's file writes persist to the host.

## Caveats

- **`dlopen` beyond `ldd`.** NSS (`libnss_*`), `libgcc_s`, locale data,
  plugins do not appear in `ldd` output. Mitigation: also carry
  `libnss_files` / `libnss_dns` and ship a files+dns `nsswitch.conf`;
  carry `libgcc_s.so.1`. This is the classic `exodus`-style gap.

- **Interpreted / packaged binaries.** If `<binary>` is a shim launching
  `node <bundle>` (Node.js), resolve to the `node` binary and carry its
  closure plus the JS bundle directory. `file $(command -v <binary>)`
  will tell you script-vs-ELF.

- **Writable workspace + HOME.** Agent workloads write files and expect
  `$HOME`. Mount a rw 9p share (host workdir ↔ DomU `/work`) so results
  persist back to the host; point `$HOME` at a tmpfs or the workspace.

- **Secrets.** API keys or configuration via `-e` env or a file in the
  workspace, never baked into the closure image.

- **Closure caching.** A glibc closure is a few MB; cache per-binary so
  repeat runs skip re-gathering.

- **Interactive + volumes on vdkr/vpdmn.** vxn's own path handles this:
  the closure is baked into the container rootfs (Xen cannot mix an
  ephemeral `xl create -c` interactive session with hot-plugged volumes,
  so volumes are not used on the vxn interactive path). vdkr/vpdmn's
  interactive+volume path is more constrained; when driving `run-host`
  through vdkr/vpdmn, non-interactive execution is expected to work,
  interactive is best-effort. Use `vxn` (default) for the reliable
  interactive experience.

## Related

- The interactive `-it` path: routes over `ssh -tt` to dom0's native vxn.
  The SDK's ed25519 keypair is injected into dom0's `authorized_keys`
  over the 9p transport at boot.
- Injection reuse: the same rootfs-hook mechanism installs the dom0
  CA cert into the DomU rootfs, so TLS in the guest just works.
