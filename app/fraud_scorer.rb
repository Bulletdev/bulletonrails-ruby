# frozen_string_literal: true

module FraudScorer
  THRESHOLD = 0.6

  def self.call(payload)
    query_vec   = VectorNormalizer.call(payload)
    neighbors   = KnnSearcher.call(query_vec)
    fraud_count = neighbors.count { |l| l == 'fraud' }
    fraud_score = fraud_count.to_f / KnnSearcher::K

    { 'approved' => fraud_score < THRESHOLD, 'fraud_score' => fraud_score }
  end
end
