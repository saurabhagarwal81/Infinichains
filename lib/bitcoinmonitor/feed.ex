defmodule Bitcoinmonitor.Feed do
  alias Bitcoinmonitor.Trade
  use WebSockex
  require Logger

  def start_link(tickers) do
    aggregation_map =
      tickers
      |> Enum.map(&{&1, {%Trade{side: "buy"}, %Trade{side: "sell"}}})
      |> Enum.into(%{})
    {:ok, pid} = WebSockex.start_link("wss://ws-feed.pro.coinbase.com", __MODULE__, %{
                                                                                      :tickers => tickers,
                                                                                      :last_published => DateTime.utc_now,
                                                                                      :aggregated_trade => aggregation_map
                                                                                    })
    subscribe_channel(pid, tickers)
    {:ok, pid}
  end

  defp subscribe_channel(pid, tickers) do
    payload = Poison.encode!( %{type: "subscribe", product_ids: tickers, channels: ["full"] } )
    WebSockex.send_frame(pid, {:text, payload})
  end

  defp unsubscribe_channel(pid) do
    payload = Poison.encode!( %{type: "unsubscribe", channels: ["full"] } )
    WebSockex.send_frame(pid, {:text, payload})
  end

  def handle_connect(_conn, state) do
    Logger.debug("Connected to the feed !")
    {:ok, state}
  end

  def handle_disconnect(_conn, state) do
    Logger.debug("Disconnected from the feed !")
    {:ok, state}
  end

  def handle_frame({_type, msg}, state) do
    process(Poison.decode!(msg), state)
  end

  defp process(%{
                  "type" => "received",
                  "price" => price,
                  "product_id" => product_id,
                  "side" => side,
                  "size" => size,
                  "time" => time
                  } , state) do
    {:ok, received_at, _} = DateTime.from_iso8601(time)
    received_trade = %Trade{ price: String.to_float(price), product_id: product_id, side: side, size: String.to_float(size), received_at: received_at}
    aggregate(received_trade, state)
  end

  defp process(%{"type" => "subscriptions"}, state) do
    {:ok, state}
  end

  defp process(%{"type" => "error", "message" => message}, _state) do
    Logger.error("Error: #{message} ")
  end

  defp process(%{"type" => _type}, state) do
     {:ok, state}
  end

  def aggregate(received_trade, %{:last_published => last_published, :aggregated_trade => aggregation_map} = state) do
    now_utc = DateTime.utc_now

    {buy_trade, sell_trade} = aggregation_map[received_trade.product_id]
    {buy_trade, sell_trade} = case received_trade.side
                                do
                                  "buy"   -> {%Trade{side: "buy", price: received_trade.price + buy_trade.price, count: buy_trade.count + 1}, sell_trade}
                                  "sell"  -> {buy_trade, %Trade{side: "sell", price: received_trade.price + sell_trade.price, count: sell_trade.count + 1}}
                                end
    aggregation_map = Map.put(aggregation_map, received_trade.product_id, {buy_trade, sell_trade})
    diff_secs = DateTime.diff(now_utc, last_published,:second)


    state = if diff_secs >=5 do
      publish(state.tickers, aggregation_map, now_utc)
      empty_aggregation_map = state.tickers
          |> Enum.map(&{&1, {%Trade{side: "buy"}, %Trade{side: "sell"}}})
          |> Enum.into(%{})
      %{:tickers => state.tickers, :last_published => now_utc, :aggregated_trade => empty_aggregation_map}
    else
       %{:tickers => state.tickers, :last_published => last_published, :aggregated_trade => aggregation_map}
    end
  {:ok, state}
  end

  defp publish(tickers, aggregation_map,timestamp) do
    IO.puts("Time: #{format_timestamp(timestamp)}")
     Enum.each(tickers , fn x ->
        {buy_trade, sell_trade} = aggregation_map[x]
        IO.puts("Ticker: #{x}, Buy: #{get_average_price(buy_trade)} Sell: #{get_average_price(sell_trade)}")
    end)
    IO.puts("")
  end

  defp format_timestamp(timestamp) do
    timestamp
    |> Timex.to_datetime("Asia/Calcutta")
    |> Timex.format!("{RFC1123}")
  end

  defp get_average_price(trade) do
    avg_price = if(trade.count > 0) do
      trade.price/trade.count
    else
      0.0
    end
  avg_price |> Float.round(2) |> Float.to_string
  end
end