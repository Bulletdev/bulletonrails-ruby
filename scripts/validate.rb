# frozen_string_literal: true

require 'zlib'
require 'time'
require 'oj'
require 'numo/narray'

$LOAD_PATH.unshift File.join(__dir__, '../app')

require 'dataset_loader'
require 'vector_normalizer'
require 'knn_searcher'
require 'fraud_scorer'

DatasetLoader.load!
puts "Dataset loaded: #{DatasetLoader.labels.size} vectors"

EXAMPLES = [
  {
    name: 'legit tx-1329056812',
    payload: {
      'id' => 'tx-1329056812',
      'transaction'      => { 'amount' => 41.12, 'installments' => 2, 'requested_at' => '2026-03-11T18:45:53Z' },
      'customer'         => { 'avg_amount' => 82.24, 'tx_count_24h' => 3, 'known_merchants' => ['MERC-003', 'MERC-016'] },
      'merchant'         => { 'id' => 'MERC-016', 'mcc' => '5411', 'avg_amount' => 60.25 },
      'terminal'         => { 'is_online' => false, 'card_present' => true, 'km_from_home' => 29.23 },
      'last_transaction' => nil
    },
    expected_vec:   [0.0041, 0.1667, 0.05, 0.7826, 0.3333, -1, -1, 0.0292, 0.15, 0, 1, 0, 0.15, 0.006],
    expected_result: { 'approved' => true, 'fraud_score' => 0.0 }
  },
  {
    name: 'fraud tx-3330991687',
    payload: {
      'id' => 'tx-3330991687',
      'transaction'      => { 'amount' => 9505.97, 'installments' => 10, 'requested_at' => '2026-03-14T05:15:12Z' },
      'customer'         => { 'avg_amount' => 81.28, 'tx_count_24h' => 20, 'known_merchants' => ['MERC-008', 'MERC-007', 'MERC-005'] },
      'merchant'         => { 'id' => 'MERC-068', 'mcc' => '7802', 'avg_amount' => 54.86 },
      'terminal'         => { 'is_online' => false, 'card_present' => true, 'km_from_home' => 952.27 },
      'last_transaction' => nil
    },
    expected_vec:   [0.9506, 0.8333, 1.0, 0.2174, 0.8333, -1, -1, 0.9523, 1.0, 0, 1, 1, 0.75, 0.0055],
    expected_result: { 'approved' => false, 'fraud_score' => 1.0 }
  }
].freeze

TOLERANCE = 0.0001
all_passed = true

EXAMPLES.each do |ex|
  puts "\n--- #{ex[:name]} ---"

  vec    = VectorNormalizer.call(ex[:payload])
  result = FraudScorer.call(ex[:payload])

  vec_ok = ex[:expected_vec].each_with_index.all? do |expected, i|
    (vec[i] - expected).abs < TOLERANCE
  end

  result_ok = result['approved'] == ex[:expected_result]['approved'] &&
              (result['fraud_score'] - ex[:expected_result]['fraud_score']).abs < TOLERANCE

  if vec_ok
    puts "  vector:  OK #{vec.to_a.map { |v| v.round(4) }.inspect}"
  else
    puts "  vector:  FAIL"
    ex[:expected_vec].each_with_index do |expected, i|
      actual = vec[i]
      diff   = (actual - expected).abs
      status = diff < TOLERANCE ? 'ok' : "MISMATCH (expected=#{expected}, got=#{actual.round(6)})"
      puts "    dim#{i}: #{status}"
    end
    all_passed = false
  end

  if result_ok
    puts "  result:  OK approved=#{result['approved']}, fraud_score=#{result['fraud_score']}"
  else
    puts "  result:  FAIL expected=#{ex[:expected_result].inspect}, got=#{result.inspect}"
    all_passed = false
  end
end

puts "\n#{'=' * 40}"
puts all_passed ? 'ALL VALIDATIONS PASSED' : 'VALIDATIONS FAILED — fix before benchmarking'
exit(all_passed ? 0 : 1)
