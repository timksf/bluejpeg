# Banked memory

`BankedMemory.bsv` presents several physical memory banks as one address range
with multiple logical request ports. The number of logical clients, the number
of banks, and the number of physical ports on each bank are independent.

In particular, having fewer clients than banks does not prevent two clients
from selecting the same bank. With two clients and four banks, both clients may
access bank 2 in the same cycle. A single-port bank queues and serializes those
requests; a dual-port bank can issue both together.

## Structure

The main types have distinct roles:

| Type or parameter | Meaning |
| --- | --- |
| `BankedMemoryAccessor_ifc#(n_clients, ...)` | Logical request/response ports used by clients |
| `Vector#(n_banks, ...)` | Independently accessible physical banks |
| `BankedMemoryPort_ifc#(n_memory_ports, ...)` | Physical read/write ports available on every bank |
| `BankedMemoryConfig_t` | Address range, mapping mode, bank capacity, and queue depth |

For a contended configuration, a request follows this path:

```text
logical port -> per-client FIFO -> address mapper
             -> per-bank/per-physical-port FIFO -> round-robin arbiter
             -> physical bank port
```

Each logical port has its own input FIFO, so different logical ports can call
`request()` in the same cycle even when all addresses map to one bank. Each
physical port of each bank has an independent round-robin arbiter. A logical
port that remains queued therefore cannot be starved by another continuously
requesting logical port in the same arbitration group.

When `n_clients <= n_memory_ports`, no sharing is required: logical port `i`
uses physical port `i` directly. This preserves the low-latency path used by
the image tiler. In a contended configuration, logical port `i` is assigned to
physical port `i % n_memory_ports`; clients assigned to the same physical port
are scheduled round-robin. Different banks always arbitrate independently.

Read responses are returned through the logical port that issued the read and
remain in that port's request order, including when consecutive reads select
different banks. Writes do not produce responses.

## Address mapping

Both mappings first calculate:

```text
offset = address - address_base
```

For `BANK_MAP_INTERLEAVED`:

```text
bank          = offset % n_banks
local_address = offset / n_banks
```

For `BANK_MAP_CONTIGUOUS`:

```text
bank          = offset / bank_depth
local_address = offset % bank_depth
```

For four banks of depth four, with `address_base = 0` and
`memory_size = 16`, the mappings are:

| Global address | Interleaved `(bank, local)` | Contiguous `(bank, local)` |
| ---: | ---: | ---: |
| 0 | `(0, 0)` | `(0, 0)` |
| 1 | `(1, 0)` | `(0, 1)` |
| 2 | `(2, 0)` | `(0, 2)` |
| 3 | `(3, 0)` | `(0, 3)` |
| 4 | `(0, 1)` | `(1, 0)` |
| 8 | `(0, 2)` | `(2, 0)` |
| 12 | `(0, 3)` | `(3, 0)` |
| 15 | `(3, 3)` | `(3, 3)` |

Interleaving is useful when adjacent logical addresses should spread across
banks. Contiguous mapping is useful when each bank should own one consecutive
address region.

`in_range(address)` reports whether an address is in
`[address_base, address_base + memory_size)`. The accessor does not reject an
out-of-range request automatically; the caller must check when that is needed.

## Single-port banks: two clients, four banks

This interleaved configuration has four banks, one physical port per bank, and
two logical clients. Each bank stores four words.

```bsv
BRAM_Configure bram_cfg = defaultValue;
bram_cfg.memorySize = 4;

BankedMemoryConfig_t cfg = BankedMemoryConfig_t {
    address_base     : 0,
    memory_size      : 16,
    bank_depth       : 4,
    outstanding_reads: 4,
    mapping          : BANK_MAP_INTERLEAVED
};

Vector#(4, BankedMemoryPort_ifc#(1, 2, 32, 4)) banks <-
    replicateM(mkBankedMemoryBRAM1PortBE(bram_cfg));
BankedMemoryAccessor_ifc#(2, 4, 32, 4) memory <-
    mkBankedMemoryAccessor(banks, cfg);
```

Addresses 0 and 4 both map to bank 0 (`(0, 0)` and `(0, 1)`). These calls may
therefore occur together:

```bsv
par
    memory.port[0].request(BankedMemoryRequest_t {
        address   : 0,
        data      : 'h11111111,
        write_mask: 'b1111,
        write     : True
    });
    memory.port[1].request(BankedMemoryRequest_t {
        address   : 4,
        data      : 'h22222222,
        write_mask: 'b1111,
        write     : True
    });
endpar
```

Both requests enter separate client queues. Because bank 0 is single-port, its
arbiter issues one request and then the other. Under sustained traffic the
grant sequence alternates between ports 0 and 1; neither can starve.

The same hardware can use contiguous mapping by changing only `mapping`. In
that case, addresses 8 and 9 both select bank 2 and are serialized in the same
way.

Requests to different banks do not interfere. For example, interleaved
addresses 0 and 1 select banks 0 and 1, so both single-port banks can issue in
parallel.

## Dual-port banks: four clients, four banks

Replacing each backend with `mkBankedMemoryBRAM2PortBE` gives every bank two
physical ports. The example below also exposes four logical clients, so each
physical port fairly shares two clients when all four target one bank.

```bsv
BRAM_Configure bram_cfg = defaultValue;
bram_cfg.memorySize = 4;

BankedMemoryConfig_t cfg = BankedMemoryConfig_t {
    address_base     : 32,
    memory_size      : 16,
    bank_depth       : 4,
    outstanding_reads: 4,
    mapping          : BANK_MAP_CONTIGUOUS
};

Vector#(4, BankedMemoryPort_ifc#(2, 2, 32, 4)) banks <-
    replicateM(mkBankedMemoryBRAM2PortBE(bram_cfg));
BankedMemoryAccessor_ifc#(4, 6, 32, 4) memory <-
    mkBankedMemoryAccessor(banks, cfg);
```

Global addresses 40 through 43 select bank 2. If logical ports 0 through 3
all request that range together, the expected grant pattern is:

| Arbitration round | Bank 2 physical port 0 | Bank 2 physical port 1 |
| ---: | ---: | ---: |
| 0 | logical port 0 | logical port 1 |
| 1 | logical port 2 | logical port 3 |
| 2 | logical port 0 | logical port 1 |

Thus the bank issues up to two accesses per cycle. Contention is serialized
only among clients sharing a physical port. The round-robin pointer advances
after each grant, so a continuously queued client progresses.

With only two logical clients and the same dual-port banks, both clients use
the direct path. They may select the same bank and issue simultaneously on its
two physical ports.

The mapping and backend choices are orthogonal. Using the configurations above,
the representative same-bank cases are:

| Physical bank | Mapping | Example global addresses | Result for two clients |
| --- | --- | --- | --- |
| Single-port | Interleaved, base 0 | 0 and 4 -> bank 0 | Accepted together, issued serially |
| Single-port | Contiguous, base 0 | 8 and 9 -> bank 2 | Accepted together, issued serially |
| Dual-port | Interleaved, base 0 | 0 and 4 -> bank 0 | Both can issue together |
| Dual-port | Contiguous, base 32 | 40 and 41 -> bank 2 | Both can issue together |

## Backend choices

| Constructor | Physical ports per bank | Byte enable |
| --- | ---: | --- |
| `mkBankedMemoryBRAM1Port` | 1 | No; `mask_w = 1` |
| `mkBankedMemoryBRAM1PortBE` | 1 | Yes |
| `mkBankedMemoryBRAM2Port` | 2 | No; `mask_w = 1` |
| `mkBankedMemoryBRAM2PortBE` | 2 | Yes |

`mkBankedMemoryBRAM2Accessor` is a convenience constructor for one dual-port
bank with two direct logical ports. It is the configuration used by
`ImageTilingEngine`.

## Configuration constraints and behavior

- `outstanding_reads` must be greater than zero. In a contended configuration
  it also sizes internal request, owner, and response queues.
- `bank_depth` must match the capacity of each backend bank. Ensure
  `memory_size <= n_banks * bank_depth`.
- `addr_w` must represent the configured global address range, and
  `bank_addr_w` must represent every local bank address.
- Each logical port accepts at most one request per cycle. Backpressure is
  applied when its queues or response tracking are full.
- Do not rely on backend-specific behavior for simultaneous writes to the same
  local address through both ports of a dual-port BRAM.
- The provided BRAM adapters request responses only for reads. A custom backend
  must likewise retain each read response until `response()` consumes it.
