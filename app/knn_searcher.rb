# frozen_string_literal: true

module KnnSearcher
  K = 5

  def self.call(query_vec)
    indices, _distances = DatasetLoader.hnsw_index.search_knn(query_vec.to_a, K)
    DatasetLoader.labels.values_at(*indices)
  end
end
