# frozen_string_literal: true

module VectorNormalizer
  RESOURCES_PATH = File.join(__dir__, '..', 'resources').freeze

  NORM     = Oj.load(File.read(File.join(RESOURCES_PATH, 'normalization.json')), mode: :compat).freeze
  MCC_RISK = Oj.load(File.read(File.join(RESOURCES_PATH, 'mcc_risk.json')),      mode: :compat).freeze

  DOW_TABLE = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4].freeze
  NIL_DIMS  = [-1.0, -1.0].freeze

  MAX_AMOUNT              = NORM['max_amount'].to_f
  MAX_INSTALLMENTS        = NORM['max_installments'].to_f
  AMOUNT_VS_AVG_RATIO     = NORM['amount_vs_avg_ratio'].to_f
  MAX_KM                  = NORM['max_km'].to_f
  MAX_TX_COUNT_24H        = NORM['max_tx_count_24h'].to_f
  MAX_MINUTES             = NORM['max_minutes'].to_f
  MAX_MERCHANT_AVG_AMOUNT = NORM['max_merchant_avg_amount'].to_f

  def self.call(payload)
    tx       = payload['transaction']
    customer = payload['customer']
    merchant = payload['merchant']
    terminal = payload['terminal']
    last_tx  = payload['last_transaction']

    ts     = tx['requested_at']
    hour   = ts[11, 2].to_i
    year   = ts[0, 4].to_i
    mon    = ts[5, 2].to_i
    dom    = ts[8, 2].to_i
    adj_y  = mon < 3 ? year - 1 : year
    wday   = (adj_y + (adj_y / 4) - (adj_y / 100) + (adj_y / 400) + DOW_TABLE[mon - 1] + dom) % 7
    day    = (wday + 6) % 7

    amount     = tx['amount'].to_f
    avg_amount = customer['avg_amount'].to_f

    dim5, dim6 = last_tx_dimensions(last_tx, ts)

    known_merchants = customer['known_merchants'] || []

    Numo::SFloat[
      clamp(amount / MAX_AMOUNT),
      clamp(tx['installments'].to_f / MAX_INSTALLMENTS),
      avg_amount.zero? ? 0.0 : clamp((amount / avg_amount) / AMOUNT_VS_AVG_RATIO),
      hour.to_f / 23.0,
      day.to_f / 6.0,
      dim5,
      dim6,
      clamp(terminal['km_from_home'].to_f / MAX_KM),
      clamp(customer['tx_count_24h'].to_f / MAX_TX_COUNT_24H),
      terminal['is_online']    ? 1.0 : 0.0,
      terminal['card_present'] ? 1.0 : 0.0,
      known_merchants.include?(merchant['id']) ? 0.0 : 1.0,
      MCC_RISK.fetch(merchant['mcc'], 0.5).to_f,
      clamp(merchant['avg_amount'].to_f / MAX_MERCHANT_AVG_AMOUNT)
    ]
  end

  def self.last_tx_dimensions(last_tx, requested_at_str)
    return NIL_DIMS if last_tx.nil?

    requested_at = Time.iso8601(requested_at_str).utc
    last_time    = Time.iso8601(last_tx['timestamp']).utc
    minutes_diff = (requested_at - last_time) / 60.0

    [
      clamp(minutes_diff / MAX_MINUTES),
      clamp(last_tx['km_from_current'].to_f / MAX_KM)
    ]
  end
  private_class_method :last_tx_dimensions

  def self.clamp(val)
    return 0.0 if val < 0.0
    return 1.0 if val > 1.0

    val.to_f
  end
  private_class_method :clamp
end
