
```
  ██████╗ ██╗   ██╗██╗     ██╗     ███████╗████████╗ 
  ██╔══██╗██║   ██║██║     ██║     ██╔════╝╚══██╔══╝
  ██████╔╝██║   ██║██║     ██║     █████╗     ██║  
  ██╔══██╗██║   ██║██║     ██║     ██╔══╝     ██║  
  ██████╔╝╚██████╔╝███████╗███████╗███████╗   ██║  
  ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝   ╚═╝  
              on Rails - Rinha de Backend 2026
```

<div align="center">

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
║  Fraud detection API using HNSW approximate KNN - Ruby/Roda     ║
║  Roda + Iodine + Numo + hnswlib · 1 CPU / 350 MB · 2 instances  ║
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
  KnnSearcher (HNSW)
  ─────────────────
  Approximate KNN via hnswlib HNSW index (O(log N)).
  ef=200, m=16 - high-recall search, 0 false negatives.
  GVL released during C search → threads run truly parallel.
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

The reference dataset (100k vectors) is loaded once at startup as a `Numo::SFloat[100_000, 14]` matrix and an HNSW index is built from it. Both live in C heap - never touched by the Ruby GC on the hot path.

---

## 03 · Tech stack

```
╔══════════════════════╦════════════════════════════════════════════════════╗
║  LAYER               ║  CHOICE                                            ║
╠══════════════════════╬════════════════════════════════════════════════════╣
║  Language            ║  Ruby 3.4                                          ║
║  HTTP framework      ║  Roda 3.103 - tree routing, ~0.1ms overhead        ║
║  HTTP server         ║  Iodine 0.7.58 - facil.io epoll, 1w x 4t           ║
║  KNN search          ║  hnswlib 0.9.3 - HNSW O(log N), ef=200, m=16       ║
║  Numeric core        ║  Numo::NArray 0.9 - vectorized C ops, Float32      ║
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

**Why HNSW instead of brute-force?**
Brute-force KNN allocates ~11 MB per request and costs O(N) CPU time. At 650 req/s with
0.45 CPU per instance, the queue backs up and p99 explodes to 12+ seconds. HNSW
(Hierarchical Navigable Small World) reduces search to O(log N) - ~17 node visits vs 100k.
The hnswlib C extension releases the GVL during search, enabling true thread parallelism.

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
     HNSW index (C heap)      HNSW index (C heap)
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
║  6 ef200 ║  Iodine   ║  5.43ms      ║  +2264.83     ║  +5264.83  (best)     ║
║  7 alloc ║  Iodine   ║  ~5ms est.   ║  est. +2300   ║  est. +5300           ║
╚══════════╩═══════════╩══════════════╩═══════════════╩═══════════════════════╝
```

**Best benchmark - Run 6 (Iodine + HNSW ef=200)**

```
╔═══════════════════════════════════════════════════════╗
║  p99                   5.43 ms                        ║
║  p99_score             2264.83  (max 3000)            ║
║  detection_score       3000.00  (max 3000)  PERFECT   ║
║  final_score           5264.83  /  6000 max  (87.7%)  ║
╠═══════════════════════════════════════════════════════╣
║  true_positives        4723 / 4812                    ║
║  true_negatives        9524 / 9688                    ║
║  false_positives       0                              ║
║  false_negatives       0                              ║
║  http_errors           0 / 14500                      ║
║  memory (per instance) 127 MB / 160 MB limit          ║
╚═══════════════════════════════════════════════════════╝
```

**Run 7 changes - allocation pressure reduction**

```
╔═══════════════════════════════════════════════════════╗
║  peak build RSS     146 MB  (was 159 MB, -13 MB)      ║
║  serving RSS        132 MB  (was 151 MB, -19 MB)      ║
║  VmSwap             0 kB    (was up to 13 MB)         ║
╚═══════════════════════════════════════════════════════╝
```

- `VectorNormalizer`: replaced `Time.iso8601` with Sakamoto DOW + string slice;
  saves ~9µs/request of GVL hold time and one Time allocation per null last_tx
- `VectorNormalizer`: frozen `NIL_DIMS` constant for null last_tx path
- `DatasetLoader`: removed dead `@norms_sq` (unused since HNSW replaced brute-force)
- `DatasetLoader.build_hnsw_index`: reuses one Array buffer across 100k `add_point`
  calls instead of `@matrix[i, true].to_a` per row; reduces peak build RSS by 13 MB

**Optimization path**

```
Brute-force Numo KNN   →  p99 12-14s, score  -1335
+ BLAS identity trick  →  alloc 11MB → 800KB per request
+ HNSW O(log N) ef=50  →  p99  5.87ms, score +4977  (breakthrough)
+ Iodine epoll 4t      →  p99  4.62ms, score +5082  (+104 pts)
+ HNSW ef=200          →  detect 3000/3000, score +5264  (+182 pts)
+ alloc reduction R7   →  -13MB peak build / -19MB serving RSS / 0 swap
```

The dominant gain came from HNSW: O(N)=100k comparisons → O(log N)≈17 node visits.
Raising ef from 50 to 200 pushed detection accuracy to perfect (0 FP, 0 FN). Run 7
reduces GC pressure and brings peak build memory to 146 MB, giving the build phase
14 MB of headroom vs the 160 MB limit (was only 1 MB). The remaining p99 gap is the
GVL - VectorNormalizer holds it for ~2-3ms per request.

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

```
▓▒░ · Ruby is fast enough · ░▒▓
```

</div>
