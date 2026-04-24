# frozen_string_literal: true
#
# Runs once during `docker build`. Pre-computes the HNSW index and labels
# from references.json.gz and saves them as binary files so the container
# startup only needs to mmap two small files instead of parsing 100k JSON
# records and rebuilding the graph.

require 'zlib'
require 'oj'
require 'numo/narray'
require 'hnswlib'

RESOURCES = File.expand_path('../resources', __dir__)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

path    = File.join(RESOURCES, 'references.json.gz')
content = Zlib::GzipReader.open(path, &:read)
records = Oj.load(content, mode: :compat)

matrix = Numo::SFloat.cast(records.map { |r| r['vector'] })
labels = records.map { |r| r['label'] }
n      = matrix.shape[0]

index = Hnswlib::HierarchicalNSW.new(space: 'l2', dim: 14)
index.init_index(max_elements: n, m: 16, ef_construction: 200, random_seed: 42)
n.times { |i| index.add_point(matrix[i, true].to_a, i) }
index.set_ef(200)

hnsw_path   = File.join(RESOURCES, 'hnsw.bin')
labels_path = File.join(RESOURCES, 'labels.bin')

index.save_index(hnsw_path)
File.binwrite(labels_path, Marshal.dump(labels))

elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
puts format('build_index: %d vectors, hnsw=%dKB labels=%dKB in %.1fs',
            n,
            File.size(hnsw_path) / 1024,
            File.size(labels_path) / 1024,
            elapsed)
