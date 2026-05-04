# frozen_string_literal: true

module FraudScorer
  THRESHOLD = 0.6

  RESPONSES = Array.new(KnnSearcher::K + 1) do |i|
    fraud_score = i.to_f / KnnSearcher::K
    approved    = fraud_score < THRESHOLD
    Oj.dump({ 'approved' => approved, 'fraud_score' => fraud_score }, mode: :compat)
  end.freeze

  def self.call(payload)
    query_vec = VectorNormalizer.call(payload)
    RESPONSES[KnnSearcher.call(query_vec).sum]
  end
end
