# frozen_string_literal: true

require 'zlib'
require 'time'
require 'oj'
require 'numo/narray'
require 'iodine'

Iodine.threads = 4
Iodine.workers = 1

require_relative 'app/dataset_loader'
require_relative 'app/vector_normalizer'
require_relative 'app/knn_searcher'
require_relative 'app/fraud_scorer'
require_relative 'app/app'

DatasetLoader.load!
GC.compact

run App.freeze.app
