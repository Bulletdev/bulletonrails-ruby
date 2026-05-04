# frozen_string_literal: true

require 'faiss'

module DatasetLoader
  RESOURCES_PATH = File.join(__dir__, '..', 'resources').freeze

  class << self
    attr_reader :matrix, :labels, :faiss_index

    def load!
      path    = File.join(RESOURCES_PATH, 'references.json.gz')
      content = Zlib::GzipReader.open(path, &:read)
      records = Oj.load(content, mode: :compat)

      @matrix      = Numo::SFloat.cast(records.map { |r| r['vector'] })
      @labels      = records.map { |r| r['label'] == 'fraud' ? 1 : 0 }.freeze
      @faiss_index = build_faiss_index
    end

    def loaded?
      !@matrix.nil?
    end

    private

    def build_faiss_index
      n   = @matrix.shape[0]
      dim = @matrix.shape[1]

      # @quantizer must be kept alive as an ivar: IndexIVFFlat holds a non-owning
      # pointer to it, so a local variable would be GC'd and cause a segfault.
      @quantizer = Faiss::IndexFlatL2.new(dim)
      index      = Faiss::IndexIVFFlat.new(@quantizer, dim, KnnSearcher::NLIST)
      index.train(@matrix)
      index.add_with_ids(@matrix, Numo::Int64.new(n).seq)
      index.nprobe = KnnSearcher::NPROBE
      index.freeze
      index
    end
  end
end
