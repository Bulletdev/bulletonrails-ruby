# frozen_string_literal: true
# Calibrates IVF nlist/nprobe using the real test-data.json queries.
# The previous spike was flawed: it tested training vectors against themselves,
# which always gives perfect recall (every vector is its own nearest neighbor).
# This script tests NEW queries from the competition test set.
#
# Run:
#   docker run --rm \
#     -v $(pwd)/resources:/app/resources \
#     -v $(pwd)/scripts:/app/scripts \
#     -v /path/to/rinha/test:/app/testdata \
#     ruby:3.4-slim bash -c "
#       apt-get update -qq && apt-get install -y build-essential libblas-dev liblapack-dev cmake libgomp1 &&
#       gem install numo-narray-alt faiss oj --no-document &&
#       ruby /app/scripts/calibrate_ivf.rb
#     "

require 'oj'
require 'zlib'
require 'numo/narray'
require 'faiss'
require 'time'

K         = 5
THRESHOLD = 0.6
DIM       = 14

RESOURCES_PATH = '/app/resources'
TEST_DATA_PATH = '/app/testdata/test-data.json'

# ---- VectorNormalizer (inline) ----
NORM     = Oj.load(File.read(File.join(RESOURCES_PATH, 'normalization.json')), mode: :compat).freeze
MCC_RISK = Oj.load(File.read(File.join(RESOURCES_PATH, 'mcc_risk.json')),      mode: :compat).freeze

MAX_AMOUNT              = NORM['max_amount'].to_f
MAX_INSTALLMENTS        = NORM['max_installments'].to_f
AMOUNT_VS_AVG_RATIO     = NORM['amount_vs_avg_ratio'].to_f
MAX_KM                  = NORM['max_km'].to_f
MAX_TX_COUNT_24H        = NORM['max_tx_count_24h'].to_f
MAX_MINUTES             = NORM['max_minutes'].to_f
MAX_MERCHANT_AVG_AMOUNT = NORM['max_merchant_avg_amount'].to_f

DOW_TABLE = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4].freeze

def clamp(val)
  return 0.0 if val < 0.0
  return 1.0 if val > 1.0
  val.to_f
end

def normalize(payload)
  tx       = payload['transaction']
  customer = payload['customer']
  merchant = payload['merchant']
  terminal = payload['terminal']
  last_tx  = payload['last_transaction']

  ts    = tx['requested_at']
  hour  = ts[11, 2].to_i
  year  = ts[0, 4].to_i
  mon   = ts[5, 2].to_i
  dom   = ts[8, 2].to_i
  adj_y = mon < 3 ? year - 1 : year
  wday  = (adj_y + (adj_y / 4) - (adj_y / 100) + (adj_y / 400) + DOW_TABLE[mon - 1] + dom) % 7
  day   = (wday + 6) % 7

  amount     = tx['amount'].to_f
  avg_amount = customer['avg_amount'].to_f

  if last_tx.nil?
    dim5, dim6 = -1.0, -1.0
  else
    requested_at = Time.iso8601(ts).utc
    last_time    = Time.iso8601(last_tx['timestamp']).utc
    minutes_diff = (requested_at - last_time) / 60.0
    dim5 = clamp(minutes_diff / MAX_MINUTES)
    dim6 = clamp(last_tx['km_from_current'].to_f / MAX_KM)
  end

  known_merchants = customer['known_merchants'] || []

  Numo::SFloat[
    clamp(amount / MAX_AMOUNT),
    clamp(tx['installments'].to_f / MAX_INSTALLMENTS),
    avg_amount.zero? ? 0.0 : clamp((amount / avg_amount) / AMOUNT_VS_AVG_RATIO),
    hour.to_f / 23.0,
    day.to_f / 6.0,
    dim5,
    dim6,
    clamp(terminal['km_from_home'].to_f / MAX_KM),
    clamp(customer['tx_count_24h'].to_f / MAX_TX_COUNT_24H),
    terminal['is_online']    ? 1.0 : 0.0,
    terminal['card_present'] ? 1.0 : 0.0,
    known_merchants.include?(merchant['id']) ? 0.0 : 1.0,
    MCC_RISK.fetch(merchant['mcc'], 0.5).to_f,
    clamp(merchant['avg_amount'].to_f / MAX_MERCHANT_AVG_AMOUNT)
  ]
end

# ---- Load reference dataset ----
puts 'Loading reference dataset...'
content = Zlib::GzipReader.open(File.join(RESOURCES_PATH, 'references.json.gz'), &:read)
records = Oj.load(content, mode: :compat)
n       = records.size
matrix  = Numo::SFloat.cast(records.map { |r| r['vector'] })
labels  = records.map { |r| r['label'] == 'fraud' ? 1 : 0 }
puts "#{n} reference vectors loaded"

# ---- Load test queries ----
puts 'Loading test data...'
test_file = Oj.load(File.read(TEST_DATA_PATH), mode: :compat)
entries   = test_file['entries']
puts "#{entries.size} test queries"

test_vecs     = entries.map { |e| normalize(e['request']) }
test_expected = entries.map { |e| e['info']['expected_response']['approved'] ? 0 : 1 }

fraud_expected = test_expected.count(1)
legit_expected = test_expected.count(0)
puts "Expected: #{fraud_expected} fraud, #{legit_expected} legit"

# Build query matrix
query_mat = Numo::SFloat.zeros(entries.size, DIM)
test_vecs.each_with_index { |v, i| query_mat[i, true] = v }

# ---- Ground truth: exact IndexFlatL2 ----
puts "\nBuilding exact FlatL2 ground truth..."
exact = Faiss::IndexFlatL2.new(DIM)
exact.add(matrix)
exact.freeze

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
_d, exact_mat = exact.search(query_mat, K)
exact_us = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000
puts "Exact: #{(exact_us / entries.size).round(1)} us/query"

exact_preds = exact_mat.to_a.map do |row|
  labels.values_at(*row).sum >= (K * THRESHOLD).ceil ? 1 : 0
end

fp_e = 0; fn_e = 0
exact_preds.each_with_index do |pred, i|
  fp_e += 1 if test_expected[i] == 0 && pred == 1
  fn_e += 1 if test_expected[i] == 1 && pred == 0
end
puts "Exact vs expected: FP=#{fp_e} FN=#{fn_e}"

# ---- IVF calibration ----
configs = [
  { nlist: 8,   nprobe: 8   },
  { nlist: 16,  nprobe: 16  },
  { nlist: 32,  nprobe: 32  },
  { nlist: 64,  nprobe: 16  },
  { nlist: 64,  nprobe: 32  },
  { nlist: 64,  nprobe: 48  },
  { nlist: 64,  nprobe: 64  },
  { nlist: 128, nprobe: 32  },
  { nlist: 128, nprobe: 64  },
  { nlist: 128, nprobe: 96  },
  { nlist: 128, nprobe: 128 },
]

puts "\n#{'nlist'.ljust(7)} #{'nprobe'.ljust(8)} #{'FP'.ljust(6)} #{'FN'.ljust(6)} #{'us/q'.ljust(10)} result"
puts '-' * 55

configs.each do |cfg|
  nlist  = cfg[:nlist]
  nprobe = cfg[:nprobe]

  quantizer = Faiss::IndexFlatL2.new(DIM)
  ivf = Faiss::IndexIVFFlat.new(quantizer, DIM, nlist)
  ivf.train(matrix)
  ivf.add(matrix)
  ivf.nprobe = nprobe
  ivf.freeze

  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  _d, ivf_mat = ivf.search(query_mat, K)
  us_per_q = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000 / entries.size).round(2)

  fp = 0; fn = 0
  ivf_mat.to_a.each_with_index do |row, i|
    valid = row.reject { |idx| idx == -1 }
    pred  = labels.values_at(*valid).sum >= (K * THRESHOLD).ceil ? 1 : 0
    fp   += 1 if test_expected[i] == 0 && pred == 1
    fn   += 1 if test_expected[i] == 1 && pred == 0
  end

  status = (fp.zero? && fn.zero?) ? 'PERFECT' : "fp=#{fp} fn=#{fn}"
  puts "#{nlist.to_s.ljust(7)} #{nprobe.to_s.ljust(8)} #{fp.to_s.ljust(6)} #{fn.to_s.ljust(6)} #{us_per_q.to_s.ljust(10)} #{status}"
end
