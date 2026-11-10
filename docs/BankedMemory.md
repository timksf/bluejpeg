# Banked memory

`BankedMemory.bsv` presents independently implemented memory banks as one
address range with multiple logical clients. The bank count (`N`), physical
ports per bank (`P`), client count (`C`), and fixed backend read latency (`L`)
are independent compile-time parameters.

The router has one invariant:

> A conflict-free request reaches a physical memory port in the cycle in which
> the client calls `request()`. Storage is used only for a real conflict or
> delayed response consumption.

## Interfaces

| Type | Role |
| --- | --- |
| `BankedMemoryAccessor_ifc#(C, ...)` | Logical client request/response ports |
| `BankedMemoryPort_ifc#(P, L, ...)` | One physical bank and its latency contract |
| `BankedMemoryPhysicalRWPort_ifc` | Technology-adapter request/response boundary |
| `BankedMemoryConfig_t` | Address range, bank depth, and mapping mode |

`BankedMemoryPhysicalRWPort_ifc.request_ready()` reports whether that physical
port can accept work in the current cycle. `request()` returns a
`Maybe#(Bit#(dw))`:

- For `L=0`, a read must return `tagged Valid data` from `request()` in the same
  cycle. A write returns `tagged Invalid`.
- For `L>0`, `request()` returns `tagged Invalid` and read data must be available
  from `response()` exactly `L` cycles later.

The router tracks the winning client alongside a delayed read in an `L`-stage
metadata pipeline. Variable-latency or transactional memories must be adapted
outside this router to a fixed-latency contract.

## Request path and arbitration

Every client has a live request wire and one pending conflict register. There
is no request FIFO and no sequential stage in the uncontended path.

For every cycle, the router:

1. Uses a client's pending request, or otherwise its live request.
2. Maps all active addresses to banks and local addresses.
3. Independently selects up to `P` distinct clients for every bank.
4. Calls the selected physical bank ports directly.
5. Captures only live requests that did not win.

Each bank has one round-robin pointer. Its `P` winners are selected in rotating
priority order and the pointer advances past the final winner. Consequently,
fully contended clients receive approximately one grant per `ceil(C/P)` grant
rounds. A pending request cannot be bypassed by a later request from the same
client because that client's logical request method remains backpressured until
the pending register clears.

There is no `C <= P` versus `C > P` architecture split and no permanent
`client % P` assignment. With a two-port bank, any two requesting clients can
win together. Requests to different banks issue independently, including the
`N=2, P=1, C=2` ping-pong case.

## Response flow and ordering

Each client has at most one read in flight and one response skid register. A
return can bypass that register directly into a simultaneous `response()`
call. Otherwise it occupies the register until consumed. No response FIFO is
instantiated.

While a read response is outstanding, writes remain eligible if there is no
older pending request. A subsequent read may occupy the client's pending
request register and blocks all still-later requests. Request issue order and
read response order are therefore preserved per client.

For an `L=0` backend, address decode, bank selection, arbitration, local-address
selection, memory read, and response muxing are combinational. In BSV, a caller
that wants a same-cycle response normally places `request()` and `response()`
in separately schedulable rules so the compiler can order producer, router,
and consumer. If the response is not consumed in that cycle, the response skid
captures it.

## Address mapping

Both mappings first compute `offset = address - address_base`.

Interleaved mapping uses:

```text
bank          = offset % N
local_address = offset / N
```

Contiguous mapping uses:

```text
bank          = offset / bank_depth
local_address = offset % bank_depth
```

Interleaving spreads adjacent accesses across banks. Contiguous mapping is
suited to ping-pong and double-buffer storage where each bank owns one region.
Constant power-of-two divisors are optimized to bit selection by synthesis.

`in_range(address)` checks `[address_base, address_base + memory_size)`. Callers
must not submit out-of-range addresses.

The mapper checks these configuration properties at elaboration:

- `N`, `P`, and `C` are at least one through the module's numeric provisos.
- `address_base` is non-negative.
- `memory_size` and `bank_depth` are greater than zero.
- The configured global range fits `aw`.
- `bank_depth` fits the physical bank address width.
- `memory_size <= N * bank_depth`, so a valid mapped address cannot truncate
  to a nonexistent bank or physical location.

## Backends

| Constructor | Ports | Read latency | Write mask |
| --- | ---: | ---: | --- |
| `mkBankedMemoryLUTRAM1Port` | 1 | 0 | No (`mw=1`) |
| `mkBankedMemoryLUTRAM1PortBE` | 1 | 0 | Yes |
| `mkBankedMemoryBRAM1Port` | 1 | 1 | No (`mw=1`) |
| `mkBankedMemoryBRAM1PortBE` | 1 | 1 | Yes |
| `mkBankedMemoryBRAM2Port` | 2 | 1 | No (`mw=1`) |
| `mkBankedMemoryBRAM2PortBE` | 2 | 1 | Yes |

`mkBankedMemoryPortAdapter` attaches a chosen numeric latency to a vector of
custom physical ports, for example an asynchronous SRAM macro (`L=0`) or a
pipelined SRAM macro (`L>=1`). `mkBankedMemoryBRAM2Accessor` remains the
single-bank/two-client convenience constructor used by the image tiler.

## Collision contract

The router arbitrates ports, not individual addresses. It deliberately does
not manufacture coherence for simultaneous accesses to one local address.

- Read/read returns whatever two independent backend reads define.
- Read/write data is backend-defined (old data, new data, or undefined).
- Write/write final data is backend-defined and may be undefined.

Code requiring deterministic same-address collision behavior must provide it
in the physical backend adapter or prevent the collision before the router.

## Example

```bsv
BRAM_Configure bram_cfg = defaultValue;
bram_cfg.memorySize = 4;

BankedMemoryConfig_t cfg = BankedMemoryConfig_t {
    address_base: 0,
    memory_size : 16,
    bank_depth  : 4,
    mapping     : BANK_MAP_INTERLEAVED
};

Vector#(4, BankedMemoryPort_ifc#(2, 1, 2, 32, 4)) banks <-
    replicateM(mkBankedMemoryBRAM2PortBE(bram_cfg));
BankedMemoryAccessor_ifc#(5, 4, 32, 4) memory <-
    mkBankedMemoryAccessor(banks, cfg);
```

This is a four-bank, dual-port-per-bank, five-client router. `C=P+3` only
changes how often conflicts occur and does not select a queued architecture.
