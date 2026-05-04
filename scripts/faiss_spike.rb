# frozen_string_literal: true

# Faiss IVF spike: test nlist/nprobe combinations against exact IndexFlatL2
# Goal: find smallest nprobe that gives FP=0, FN=0 vs exact KNN
#
# Run inside Docker:
#   docker run --rm \
#     -v $(pwd)/resources:/app/resources \
#     -v $(pwd)/scripts:/app/scripts \
#     ruby:3.4-slim bash -c "
#       apt-get update -qq && apt-get install -y build-essential libblas-dev liblapack-dev cmake libgomp1 &&
#       gem install numo-narray-alt faiss oj --no-document &&
#       ruby /app/scripts/faiss_spike.rb
#     "

require 'oj'
require 'zlib'
require 'numo/narray'
require 'faiss'

K         = 5
THRESHOLD = 0.6
DIM       = 14

puts "Loading dataset..."
path    = '/app/resources/references.json.gz'
content = Zlib::GzipReader.open(path, &:read)
records = Oj.load(content, mode: :compat)
n       = records.size
puts "Records: #{n}"

matrix = Numo::SFloat.cast(records.map { |r| r['vector'] })
labels = records.map { |r| r['label'] == 'fraud' ? 1 : 0 }

# Ground truth: exact search
puts "\nBuilding exact IndexFlatL2 ground truth..."
exact = Faiss::IndexFlatL2.new(DIM)
exact.add(matrix)
exact.freeze

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
_dist, exact_mat = exact.search(matrix, K)
exact_elapsed_us = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000
puts "Exact total: #{(exact_elapsed_us / 1000).round(1)}ms  |  per query: #{(exact_elapsed_us / n).round(2)}us"

exact_preds = exact_mat.to_a.map do |row|
  labels.values_at(*row).sum >= (K * THRESHOLD).ceil ? 1 : 0
end
puts "Fraud: #{exact_preds.count(1)}  Legit: #{exact_preds.count(0)}"

configs = [
  { nlist: 8,   nprobe: 1  },
  { nlist: 8,   nprobe: 2  },
  { nlist: 8,   nprobe: 4  },
  { nlist: 8,   nprobe: 8  },
  { nlist: 16,  nprobe: 1  },
  { nlist: 16,  nprobe: 2  },
  { nlist: 16,  nprobe: 4  },
  { nlist: 16,  nprobe: 8  },
  { nlist: 32,  nprobe: 1  },
  { nlist: 32,  nprobe: 2  },
  { nlist: 32,  nprobe: 4  },
  { nlist: 32,  nprobe: 8  },
  { nlist: 32,  nprobe: 16 },
  { nlist: 64,  nprobe: 2  },
  { nlist: 64,  nprobe: 4  },
  { nlist: 64,  nprobe: 8  },
  { nlist: 64,  nprobe: 16 },
  { nlist: 100, nprobe: 4  },
  { nlist: 100, nprobe: 8  },
  { nlist: 100, nprobe: 16 },
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
  _d, ivf_mat = ivf.search(matrix, K)
  us_per_q = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1_000_000 / n).round(2)

  fp = 0
  fn = 0
  ivf_mat.to_a.each_with_index do |row, i|
    valid  = row.reject { |idx| idx == -1 }
    pred   = labels.values_at(*valid).sum >= (K * THRESHOLD).ceil ? 1 : 0
    fp    += 1 if exact_preds[i] == 0 && pred == 1
    fn    += 1 if exact_preds[i] == 1 && pred == 0
  end

  status = (fp.zero? && fn.zero?) ? 'PERFECT' : "fp=#{fp} fn=#{fn}"
  puts "#{nlist.to_s.ljust(7)} #{nprobe.to_s.ljust(8)} #{fp.to_s.ljust(6)} #{fn.to_s.ljust(6)} #{us_per_q.to_s.ljust(10)} #{status}"
end
