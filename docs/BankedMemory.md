# Banked memory

`BankedMemory.bsv` presents independent memory banks as one address range shared by several clients.
Bank count `N`, ports per bank `P`, client count `C` and backend read latency `L` are compile-time
parameters. A conflict-free request reaches a physical port in the cycle the client calls
`request()`. Storage is used only for conflicts and late response consumption.

## Interfaces

| Type | Role |
| --- | --- |
| `BankedMemoryAccessor_ifc#(C, ...)` | Client request and response ports |
| `BankedMemoryPort_ifc#(P, L, ...)` | One physical bank and its latency |
| `BankedMemoryPhysicalRWPort_ifc` | Technology adapter boundary |
| `BankedMemoryConfig_t` | Address range, bank depth and mapping mode |

`request_ready()` reports whether a physical port accepts work this cycle. `request()` returns a
`Maybe#(Bit#(dw))`.

- With `L=0` a read returns `tagged Valid data` from `request()` in the same cycle, a write returns
  `tagged Invalid`
- With `L>0` `request()` returns `tagged Invalid` and the read data appears on `response()` exactly `L`
  cycles later

The winning client travels with a delayed read through an `L`-stage metadata pipeline. Variable
latency memories need an adapter to a fixed latency outside the router.

## Arbitration

Each client has a live request wire and one pending conflict register, with no request FIFO. Every
cycle the router

1. takes each client's pending request, otherwise its live request
2. maps addresses to bank and local address
3. selects up to `P` clients per bank
4. calls the selected physical ports directly
5. captures live requests that lost

Each bank has a round-robin pointer that advances past its last winner, so fully contended clients get
about one grant per `ceil(C/P)` rounds. A client stays back-pressured while its pending register is
full, so its requests cannot overtake each other. There is no fixed `client % P` port assignment and
no separate architecture for `C > P`. Requests to different banks issue independently.

## Responses and ordering

Each client has at most one read in flight and one response skid register, which a simultaneous
`response()` call bypasses. There is no response FIFO. Writes stay eligible during an outstanding read
when no older request is pending, and a later read waits in the pending register. Issue order and read
response order are preserved per client.

With `L=0` decode, arbitration, memory read and response mux are combinational. A caller that wants
the response in the same cycle puts `request()` and `response()` in separate rules so the scheduler
can order them. An unconsumed response goes to the skid register.

## Address mapping

Both modes start from `offset = address - address_base`.

```text
interleaved   bank = offset % N            local_address = offset / N
contiguous    bank = offset / bank_depth   local_address = offset % bank_depth
```

Interleaving spreads adjacent accesses over banks, while contiguous mapping gives each bank its own region
for ping-pong buffers. Power-of-two divisors reduce to bit selection. `in_range(address)` checks
`[address_base, address_base + memory_size)`, and callers must not submit addresses outside it.

Elaboration checks that `address_base` is non-negative, `memory_size` and `bank_depth` are positive,
the range fits `aw`, `bank_depth` fits the bank address width and `memory_size <= N * bank_depth`.

## Backends

| Constructor | Ports | Read latency | Write mask |
| --- | ---: | ---: | --- |
| `mkBankedMemoryLUTRAM1Port` | 1 | 0 | No |
| `mkBankedMemoryLUTRAM1PortBE` | 1 | 0 | Yes |
| `mkBankedMemoryBRAM1Port` | 1 | 1 | No |
| `mkBankedMemoryBRAM1PortBE` | 1 | 1 | Yes |
| `mkBankedMemoryBRAM2Port` | 2 | 1 | No |
| `mkBankedMemoryBRAM2PortBE` | 2 | 1 | Yes |

`mkBankedMemoryPortAdapter` attaches a latency to custom physical ports, for example an SRAM macro.
`mkBankedMemoryBRAM2Accessor` is the single-bank, two-client constructor used by the tiler.

## Collisions

The router arbitrates ports, not addresses. Simultaneous accesses to one local address return whatever
the backend defines for read and read, read and write, or write and write. Deterministic behaviour
must come from the backend adapter or from avoiding the collision.

## Example

Four dual-port banks shared by five clients.

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
