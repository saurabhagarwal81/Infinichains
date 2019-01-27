defmodule Bitcoinmonitor.Trade do

  defstruct(
    price: 0.0,
    product_id: nil,
    side: nil,
    size: 0.0,
    received_at: nil,
    count: 0
  )

end