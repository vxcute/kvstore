'''
    SET <KEY> <VALUE>
    GET <KEY>
    HAS <KEY>
    DELETE <KEY>
'''

defmodule Kvstore do
  require Logger

  def start(port) do
    case :gen_tcp.listen(port, [:binary, reuseaddr: true, active: false]) do
      {:ok, sock} ->
        Logger.info("listening on port: #{port}")
        :ets.new(:kv_store, [:set, :public, :named_table])
        accept(sock)

      {:error, reason} ->
        Logger.error("failed to listen on port: #{port} | reason: #{reason}")
    end
  end

  def accept(sock) do
    case :gen_tcp.accept(sock) do
      {:ok, client} ->
        Logger.info("connected to new client ...")
        spawn(fn -> serve(client) end)

      {:error, reason} ->
        Logger.info("failed to connect | reason: #{reason}")
    end

    accept(sock)
  end

  def serve(client) do
    process_msg(client)
    serve(client)
  end

  def process_msg(client) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        clean = String.replace(data, "\r\n", "") |> String.split(" ")
        cmd = Enum.at(clean, 0)
        key = Enum.at(clean, 1)
        value = Enum.slice(clean, 2..-1) |> Enum.join(" ")

        case cmd do
          "SET" ->
            case :ets.insert(:kv_store, {key, value}) do
              true ->
                client |> send_msg("Now #{key} -> #{value}")
            end

          "GET" ->
            tup = :ets.lookup(:kv_store, key)

            cond do
              length(tup) == 0 ->
                client |> send_msg("Entry Doesn't Exist")

              true ->
                client |> send_msg(elem(Enum.at(tup, 0), 1))
            end

          "DELETE" ->
            case :ets.delete(:kv_store, key) do
              true ->
                client |> send_msg("Deleted #{key} entry")
            end

          "HAS" ->
            case :ets.member(:kv_store, key) do
              true ->
                client |> send_msg("True")

              false ->
                client |> send_msg("False")
            end

          true ->
            client
            |> send_msg(
              "unknown command supported commands are [SET <K>, <V>, GET <K>, DELETE <K>, HAS <K>]\n"
            )
        end

      {:error, :closed} ->
        Logger.info("connection was closed")

      {:error, reason} ->
        :gen_tcp.close(client)
        Logger.error("failed to receive data | reason: #{reason}")
    end
  end

  def send_msg(client, msg) do
    :gen_tcp.send(client, msg <> "\n")
  end
end
