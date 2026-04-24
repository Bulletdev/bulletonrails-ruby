# frozen_string_literal: true

require 'hnswlib'

module DatasetLoader
  RESOURCES_PATH = File.join(__dir__, '..', 'resources').freeze

  class << self
    attr_reader :matrix, :labels, :hnsw_index

    def load!
      path    = File.join(RESOURCES_PATH, 'references.json.gz')
      content = Zlib::GzipReader.open(path, &:read)
      records = Oj.load(content, mode: :compat)

      @matrix     = Numo::SFloat.cast(records.map { |r| r['vector'] })
      @labels     = records.map { |r| r['label'] }.freeze
      @hnsw_index = build_hnsw_index
    end

    def loaded?
      !@matrix.nil?
    end

    private

    def build_hnsw_index
      n     = @matrix.shape[0]
      index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 14)
      index.init_index(max_elements: n, m: 16, ef_construction: 200, random_seed: 42)
      n.times { |i| index.add_point(@matrix[i, true].to_a, i) }
      index.set_ef(200)
      index
    end
  end
end
