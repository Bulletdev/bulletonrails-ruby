# frozen_string_literal: true

require 'roda'

class App < Roda
  plugin :json

  route do |r|
    r.get 'ready' do
      response.status = DatasetLoader.loaded? ? 200 : 503
      ''
    end

    r.post 'fraud-score' do
      payload = Oj.load(r.body.read, mode: :compat)
      FraudScorer.call(payload)
    rescue StandardError
      response.status = 200
      { 'approved' => true, 'fraud_score' => 0.0 }
    end
  end
end
