
```
>          ██████╗ ██╗   ██╗██╗     ██╗     ██████╗████████╗ 
>          ██╔══██╗██║   ██║██║     ██║     ██╔═══╝╚══██╔══╝
>          ██████╔╝██║   ██║██║     ██║     █████╗    ██║  
>          ██╔══██╗██║   ██║██║     ██║     ██╔══╝    ██║  
>          ██████╔╝╚██████╔╝██████╗ ██████╗ ██████╗   ██║  
>          ╚═════╝  ╚═════╝ ╚═════╝ ╚═════╝ ╚═════╝   ╚═╝  
              on Rails - Rinha de Backend 2026
```

<div align="center">
  
[![Auto-merge participant submission](https://github.com/zanfranceschi/rinha-de-backend-2026/actions/workflows/auto-merge-participant.yml/badge.svg)](https://github.com/zanfranceschi/rinha-de-backend-2026/actions/workflows/auto-merge-participant.yml)

  
[![Ruby Version](https://img.shields.io/badge/ruby-3.4-CC342D?logo=ruby)](https://www.ruby-lang.org/)
[![Roda](https://img.shields.io/badge/roda-3.103-CC342D)](http://roda.jeremyevans.net/)
[![Iodine](https://img.shields.io/badge/iodine-0.7.58-CC342D)](https://github.com/boazsegev/iodine)
[![Docker](https://img.shields.io/badge/docker-compose-2496ED?logo=docker)](https://docs.docker.com/compose/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

</div>

---

```
╔═════════════════════════════════════════════════════════════════╗
║  bulletonrails-ruby - Rinha de Backend 2026                     ║
╠═════════════════════════════════════════════════════════════════╣
║  Fraud detection API using IVF approximate KNN - Ruby/Roda      ║
║  Roda + Iodine + Numo + FAISS · 1 CPU / 350 MB · 2 instances    ║
╚═════════════════════════════════════════════════════════════════╝
```

---

```
┌─────────────────────────────────────────────────────────────────┐
│  01 · What is this                                              |
│  02 · How it works                                              │
│  03 · Tech stack                                                │
│  04 · Architecture                                              │
│  05 · Quick start                                               │
│  06 · Validation                                                │
│  07 · Benchmark results                                         │
│  08 · Submission                                                │
└─────────────────────────────────────────────────────────────────┘
```

---

## 01 · What is this

Submission for [Rinha de Backend 2026](https://github.com/zanfranceschi/rinha-de-backend-2026) - a competition to build a fraud detection API under extreme resource constraints.

The challenge: build an API that receives a card transaction and decides - in real time - whether it is fraudulent, using vector similarity search against 100k labeled reference transactions.

This submission proves that **Ruby can compete** in performance-sensitive scenarios when you pick the right tools. No Rails. No ActiveRecord. No framework overhead. Just Roda, Iodine, Numo::NArray for vectorized math, and hnswlib for O(log N) approximate nearest neighbor search.

---

## 02 · How it works

```
POST /fraud-score
        │
        ▼
  VectorNormalizer
  ─────────────────
  Transform 14 fields from the payload into a normalized
  Numo::SFloat vector using formulas from the spec.
  Sentinel -1 for absent last_transaction.
        │
        ▼
  KnnSearcher (IVF)
  ─────────────────
  Approximate KNN via FAISS IndexIVFFlat (nlist=64, nprobe=16).
  Sequential cluster scan → SIMD-friendly, 0 false negatives.
  index.freeze → no_gvl path → GVL released during C search.
        │
        ▼
  FraudScorer
  ─────────────────
  fraud_score = fraud_neighbors / 5
  approved    = fraud_score < 0.6
        │
        ▼
  { "approved": bool, "fraud_score": float }
```

### The 14 dimensions

| idx | field | formula |
|-----|-------------------------|------------------------------------------|
|  0  | `amount`                | `clamp(amount / 10_000)`                 |
|  1  | `installments`          | `clamp(installments / 12)`               |
|  2  | `amount_vs_avg`         | `clamp((amount / avg_amount) / 10)`      |
|  3  | `hour_of_day`           | `utc_hour / 23`                          |
|  4  | `day_of_week`           | `(wday + 6) % 7 / 6` - Mon=0, Sun=6      |
|  5  | `minutes_since_last_tx` | `clamp(minutes / 1440)` or `-1` if null  |
|  6  | `km_from_last_tx`       | `clamp(km / 1000)` or `-1` if null       |
|  7  | `km_from_home`          | `clamp(km_from_home / 1000)`             |
|  8  | `tx_count_24h`          | `clamp(tx_count / 20)`                   |
|  9  | `is_online`             | `1.0` or `0.0`                           |
| 10  | `card_present`          | `1.0` or `0.0`                           |
| 11  | `unknown_merchant`      | `0.0` if known, `1.0` if not             |
| 12  | `mcc_risk`              | lookup from `mcc_risk.json` (default 0.5)|
| 13  | `merchant_avg_amount`   | `clamp(merchant_avg / 10_000)`           |

The reference dataset (100k vectors) is loaded once at startup as a `Numo::SFloat[100_000, 14]` matrix and an IVF index is built from it. Both live in C heap - never touched by the Ruby GC on the hot path.

---

## 03 · Tech stack

```
╔══════════════════════╦════════════════════════════════════════════════════╗
║  LAYER               ║  CHOICE                                            ║
╠══════════════════════╬════════════════════════════════════════════════════╣
║  Language            ║  Ruby 3.4                                          ║
║  HTTP framework      ║  Roda 3.103 - tree routing, ~0.1ms overhead        ║
║  HTTP server         ║  Iodine 0.7.58 - facil.io epoll, 1w x 4t           ║
║  KNN search          ║  FAISS 0.6.0 - IVF nlist=64 nprobe=16, no_gvl      ║
║  Numeric core        ║  numo-narray-alt 0.10 - C++-compat fork, Float32   ║
║  JSON                ║  Oj 3.17 - 3-5x faster than stdlib JSON            ║
║  Load balancer       ║  nginx 1.27-alpine - round-robin, keepalive 32     ║
║  Container           ║  Docker Compose - bridge network, linux/amd64      ║
╚══════════════════════╩════════════════════════════════════════════════════╝
```

**Why not Rails?**
Rails consumes 150-200 MB per instance. With 2 instances + nginx, that exceeds the 350 MB total
budget. Roda runs in ~60 MB per instance and adds zero overhead for 2 static endpoints.

**Why Iodine instead of Puma?**
Iodine is built on facil.io, a C event loop using epoll. It handles accept/read/write
asynchronously, overlapping I/O with computation. At 650 req/s, this reduces per-request
overhead vs Puma's threaded model: p99 dropped from 5.87ms to 4.62ms.

**Why FAISS IVF instead of HNSW?**
HNSW has a structural floor: graph traversal with random memory access costs ~2.5ms
(~17 node visits, constant cache misses). IVF (Inverted File Index) replaces graph traversal
with sequential cluster scan: quantize the query to the nearest centroid, then scan only
1/nlist of the vectors in sequential memory — SIMD-friendly and cache-coherent.
Result: single-query p99 drops from ~2.5ms to ~341 µs (7x) with FP=0 FN=0 at nlist=64 nprobe=16.
The FAISS gem releases the GVL when the index is frozen (Rice `no_gvl` path), enabling
true thread parallelism identical to the previous hnswlib behavior.

---

## 04 · Architecture

```
                          :9999
  k6 / test engine ──── nginx (LB)
                           │   round-robin
              ┌────────────┴────────────┐
              ▼                         ▼
         [ api 1 ]                  [ api 2 ]
       Roda + Iodine             Roda + Iodine
      1 worker, 4 threads       1 worker, 4 threads
              │                         │
     Numo::SFloat[100k,14]    Numo::SFloat[100k,14]
     IVF index (C heap)       IVF index (C heap)
     LABELS[100k]             LABELS[100k]
     (loaded at startup)      (loaded at startup)
```

### Resource allocation

```
╔══════════════╦══════════╦════════════╗
║  Service     ║  CPUs    ║  Memory    ║
╠══════════════╬══════════╬════════════╣
║  nginx       ║  0.10    ║  20 MB     ║
║  api1        ║  0.45    ║  160 MB    ║
║  api2        ║  0.45    ║  160 MB    ║
╠══════════════╬══════════╬════════════╣
║  TOTAL       ║  1.00    ║  340 MB    ║
╚══════════════╩══════════╩════════════╝
```

Limit: 1 CPU / 350 MB. Used: 1.00 CPU / 340 MB.

---

## 05 · Quick start
<details>
<summary><kbd>▶ see details (click to expand)</kbd></summary>

```bash
# Clone
git clone https://github.com/bulletdev/bulletonrails-ruby
cd bulletonrails-ruby

# Build and run (HNSW index builds at startup, ~60s)
docker compose up --build -d

# Wait for ready (port 9999 opens only after index build completes)
until curl -sf http://localhost:9999/ready; do sleep 3; done && echo "ready"

# Test a legitimate transaction
curl -s -X POST http://localhost:9999/fraud-score \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "tx-1329056812",
    "transaction":      { "amount": 41.12, "installments": 2, "requested_at": "2026-03-11T18:45:53Z" },
    "customer":         { "avg_amount": 82.24, "tx_count_24h": 3, "known_merchants": ["MERC-003", "MERC-016"] },
    "merchant":         { "id": "MERC-016", "mcc": "5411", "avg_amount": 60.25 },
    "terminal":         { "is_online": false, "card_present": true, "km_from_home": 29.23 },
    "last_transaction": null
  }'
# Expected: {"approved":true,"fraud_score":0.0}

# Test a fraudulent transaction
curl -s -X POST http://localhost:9999/fraud-score \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "tx-3330991687",
    "transaction":      { "amount": 9505.97, "installments": 10, "requested_at": "2026-03-14T05:15:12Z" },
    "customer":         { "avg_amount": 81.28, "tx_count_24h": 20, "known_merchants": ["MERC-008", "MERC-007", "MERC-005"] },
    "merchant":         { "id": "MERC-068", "mcc": "7802", "avg_amount": 54.86 },
    "terminal":         { "is_online": false, "card_present": true, "km_from_home": 952.27 },
    "last_transaction": null
  }'
# Expected: {"approved":false,"fraud_score":1.0}
```
</details>

---

## 06 · Validation

Validate vectors against the spec via the live endpoint (the container runs at ~132 MB; spawning
a second Ruby process with `docker compose exec` would exceed the 160 MB limit):

<details>
<summary><kbd>▶ see details (click to expand)</kbd></summary>


```bash
# legit - expected: {"approved":true,"fraud_score":0.0}
curl -s -X POST http://localhost:9999/fraud-score \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "tx-1329056812",
    "transaction":      { "amount": 41.12, "installments": 2, "requested_at": "2026-03-11T18:45:53Z" },
    "customer":         { "avg_amount": 82.24, "tx_count_24h": 3, "known_merchants": ["MERC-003", "MERC-016"] },
    "merchant":         { "id": "MERC-016", "mcc": "5411", "avg_amount": 60.25 },
    "terminal":         { "is_online": false, "card_present": true, "km_from_home": 29.23 },
    "last_transaction": null
  }'

# fraud - expected: {"approved":false,"fraud_score":1.0}
curl -s -X POST http://localhost:9999/fraud-score \
  -H 'Content-Type: application/json' \
  -d '{
    "id": "tx-3330991687",
    "transaction":      { "amount": 9505.97, "installments": 10, "requested_at": "2026-03-14T05:15:12Z" },
    "customer":         { "avg_amount": 81.28, "tx_count_24h": 20, "known_merchants": ["MERC-008", "MERC-007", "MERC-005"] },
    "merchant":         { "id": "MERC-068", "mcc": "7802", "avg_amount": 54.86 },
    "terminal":         { "is_online": false, "card_present": true, "km_from_home": 952.27 },
    "last_transaction": null
  }'
```

Expected output:

```
{"approved":true,"fraud_score":0.0}
{"approved":false,"fraud_score":1.0}
```

The `scripts/validate.rb` script exists for offline use (e.g. in a container with extra memory
headroom). Expected output when run outside resource constraints:

```
Dataset loaded: 100000 vectors

--- legit tx-1329056812 ---
  vector:  OK [0.0041, 0.1667, 0.05, 0.7826, 0.3333, -1.0, -1.0, 0.0292, 0.15, 0.0, 1.0, 0.0, 0.15, 0.006]
  result:  OK approved=true, fraud_score=0.0

--- fraud tx-3330991687 ---
  vector:  OK [0.9506, 0.8333, 1.0, 0.2174, 0.8333, -1.0, -1.0, 0.9523, 1.0, 0.0, 1.0, 1.0, 0.75, 0.0055]
  result:  OK approved=false, fraud_score=1.0

========================================
ALL VALIDATIONS PASSED
```
</details>
---

## 07 · Benchmark results

Score formula: `final = score_p99 + score_det`

`score_p99 = max(-3000, min(3000, 1000 * log10(1000ms / p99)))`

```
╔═════════════════════════════════════════════════════════════════════════════╗
║  EVOLUTION                                                                  ║
╠══════════╦═══════════╦══════════════╦═══════════════╦═══════════════════════╣
║  Run     ║  Server   ║  p99         ║  p99_score    ║  final_score          ║
╠══════════╬═══════════╬══════════════╬═══════════════╬═══════════════════════╣
║  1       ║  Puma     ║  OOM kill    ║  -            ║  -705.91              ║
║  2       ║  Puma     ║  14600ms     ║  -3000 (cut)  ║  -1327.89             ║
║  3       ║  Puma     ║  12704ms     ║  -3000 (cut)  ║  -1335.93             ║
║  4 HNSW  ║  Puma     ║  5.87ms      ║  +2231.50     ║  +4977.97             ║
║  5 HNSW  ║  Iodine   ║  4.62ms      ║  +2335.67     ║  +5082.14             ║
║  6 ef200 ║  Iodine   ║  5.43ms      ║  +2264.83     ║  +5264.83             ║
║  7 stable║  Iodine   ║  5.54ms      ║  +2256.75     ║  +5256.75             ║
║  8 gc    ║  Iodine   ║  6.34ms      ║  +2198.08     ║  +5198.08             ║
║  9 yjit  ║  Iodine   ║  ~3.7ms      ║  +2427        ║  +5427                ║
║ 10 resp  ║  Iodine   ║  ~3.7ms      ║  ~2427        ║  ~5427                ║
║ 11 faiss ║  Iodine   ║  ~1.5ms est  ║  ~2825 est    ║  ~5825 est (current)  ║
╚══════════╩═══════════╩══════════════╩═══════════════╩═══════════════════════╝
```

**Best benchmark - Run 11 (FAISS IVF nlist=64 nprobe=16 — estimated)**

```
╔═══════════════════════════════════════════════════════╗
║  IVF search p99 (spike)  341 µs  (HNSW: ~2500 µs)     ║
║  p99 total (estimate)    ~1.5 ms                      ║
║  p99_score (estimate)    ~2825   (max 3000)           ║
║  detection_score         3000.00  (max 3000)  PERFECT ║
║  final_score (estimate)  ~5825  /  6000 max  (97.1%)  ║
╠═══════════════════════════════════════════════════════╣
║  IVF nlist=64 nprobe=16 vs exact search:              ║
║  false_positives   0                                  ║
║  false_negatives   0                                  ║
║  GVL released      yes (index.freeze → no_gvl)        ║
║  RSS (spike proc)  ~100 MB / 160 MB limit             ║
╚═══════════════════════════════════════════════════════╝

Run 9 (last official run):
╔═══════════════════════════════════════════════════════╗
║  p99 (best run)        3.27 ms                        ║
║  p99 (median 10 runs)  3.78 ms                        ║
║  p99_score (median)    ~2427  (max 3000)              ║
║  detection_score       3000.00  (max 3000)  PERFECT   ║
║  final_score (best)    5485.57  /  6000 max  (91.4%)  ║
║  final_score (median)  ~5427   /  6000 max  (90.5%)   ║
╚═══════════════════════════════════════════════════════╝
```

**Run 8 changes - GC compaction**

- `config.ru`: added `GC.compact` after `DatasetLoader.load!`; compacts the Ruby heap
  after the 100k-record JSON parse before Iodine starts threads; eliminates GC pressure
  spike that caused p99=20ms regression under peak load on api2
- Serving RSS: api1=134MB, api2=136MB, both well within 160MB limit

**Run 9 changes - YJIT + hot-path allocation reduction**

```
╔═══════════════════════════════════════════════════════╗
║  p99 improvement       ~40% vs baseline               ║
║  score improvement     +229 pts (median) vs Run 8     ║
║  detection             still perfect (0 FP, 0 FN)     ║
╚═══════════════════════════════════════════════════════╝
```

- `Dockerfile`: `--yjit --yjit-exec-mem-size=8` — YJIT enabled with 8 MB code cache;
  default 48 MB was competing with GC for the 26 MB headroom under the 160 MB limit,
  causing GC pressure spikes. 8 MB is enough to JIT the hot paths (VectorNormalizer,
  Roda routing, FraudScorer) without bloating RSS.
- `Dockerfile`: `ENV MALLOC_ARENA_MAX=2` — limits glibc malloc arenas, reduces
  allocator fragmentation under multi-threaded load.
- `DatasetLoader`: labels stored as integers (1 = fraud, 0 = legit) instead of strings;
  eliminates per-request string comparison and block overhead in FraudScorer.
- `VectorNormalizer`: `NORM['...']` hash lookups extracted to frozen Float constants
  (`MAX_AMOUNT`, `MAX_KM`, etc.); eliminates 9 Hash#[] calls per request on the hot path.

**Run 10 changes - pre-mounted HTTP responses**

- `FraudScorer`: `RESPONSES` array built at startup with `K+1` pre-serialized JSON strings;
  since `fraud_score = fraud_count / K` has exactly `K+1` possible values, every response
  is known at boot time. Eliminates Hash allocation + Oj serialization on every request.
  Built dynamically from `K` and `THRESHOLD` — safe if the spec changes values.
  Gain is below p99 noise floor on this setup (~sub-µs per request); included for
  architectural correctness (same pattern used by the top C implementation).

**Run 11 changes - FAISS IVF replaces hnswlib HNSW**

- `KnnSearcher`: hnswlib HNSW (ef=200, m=16, ~2.5ms floor) replaced with FAISS
  `IndexIVFFlat` (nlist=64, nprobe=16). IVF clusters the 100k vectors into 64 groups;
  each query scans the 16 closest clusters sequentially (~25k vectors). Sequential
  memory access is SIMD-friendly and avoids the random cache-miss pattern of graph traversal.
- `DatasetLoader`: quantizer stored as `@quantizer` ivar — `IndexIVFFlat` holds a
  non-owning C pointer to the quantizer; without the ivar, Ruby GC would collect it
  and cause a segfault. Calling `index.freeze` enables Rice's `no_gvl` path, releasing
  the GVL during search (same behavior as hnswlib).
- `Gemfile`: `hnswlib` + `numo-narray` → `faiss` + `numo-narray-alt` (C++-compatible
  fork required by Rice/FAISS binding; same `Numo::SFloat` API, no changes to
  VectorNormalizer).
- `Dockerfile`: builder adds `libblas-dev liblapack-dev cmake libgomp1`; runtime adds
  `libblas3 liblapack3 libgomp1`. System `libfaiss-dev` is NOT installed — its headers
  conflict with the gem's bundled FAISS source (`vendor/faiss/`); gem compiles from
  bundled source instead.
- Spike results: nlist=64 nprobe=16 gives FP=0 FN=0 vs exact IndexFlatL2 search across
  all 100k training vectors. Single-query p99: 341 µs.

**Optimization path**

```
Brute-force Numo KNN      →  p99 12-14s, score  -1335
+ BLAS identity trick     →  alloc 11MB → 800KB per request
+ HNSW O(log N) ef=50     →  p99  5.87ms, score +4977  (breakthrough)
+ Iodine epoll 4t         →  p99  4.62ms, score +5082  (+104 pts)
+ HNSW ef=200             →  detect 3000/3000, score +5264  (+182 pts)
+ alloc reduction R7      →  Sakamoto DOW, NIL_DIMS const, removed dead @norms_sq
+ GC.compact R8           →  api2 RSS -19MB, eliminates GC spike under load
+ YJIT exec-mem=8 R9      →  p99 ~3.7ms stable, score ~5427 avg (+229 pts)
+ pre-mounted responses R10→  eliminates Hash + Oj per request; gain within noise floor
+ FAISS IVF nlist=64 R11  →  IVF p99 341µs (7x vs HNSW), est final ~5825  (+398 pts)
```

The dominant gain came from HNSW: O(N)=100k comparisons → O(log N)≈17 node visits.
Raising ef from 50 to 200 pushed detection accuracy to perfect (0 FP, 0 FN). Run 7
reduces per-request GVL hold time via Sakamoto DOW (no Time allocation on null last_tx
path). Run 8 adds GC.compact after dataset load. Run 9 enables YJIT with a constrained
8 MB code cache — the default 48 MB caused GC pressure by eating into the 26 MB headroom
between serving RSS (~134 MB) and the container limit (160 MB). With exec-mem=8, YJIT
JITs only the hot paths and stabilizes at p99 ~3.7ms across 9/10 benchmark runs.
Run 11 breaks through the HNSW structural floor by replacing graph traversal with
sequential IVF cluster scan: 341 µs IVF search p99 vs ~2500 µs HNSW (7x improvement).

---

## 08 · Submission

```
╔════════════════════════════════════════════════════════════╗
║  GitHub user:      bulletdev                               ║
║  Repo:             bulletonrails-ruby                      ║
║  Submission ID:    bulletdev-ruby                          ║
║  branch main:      source code                             ║
║  branch submission: docker-compose.yml at root             ║
╚════════════════════════════════════════════════════════════╝
```

To trigger the official test: open an issue with `rinha/test` in the description.

---

<div align="center">

▓▒░ · Ruby is fast enough · ░▒▓

</div>
