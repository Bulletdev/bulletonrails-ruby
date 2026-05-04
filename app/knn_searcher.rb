# frozen_string_literal: true

module KnnSearcher
  K      = 5
  NLIST  = 64
  NPROBE = 16

  def self.call(query_vec)
    query_mat = query_vec.reshape(1, query_vec.size)
    _distances, indices = DatasetLoader.faiss_index.search(query_mat, K)
    DatasetLoader.labels.values_at(*indices[0].to_a)
  end
end
