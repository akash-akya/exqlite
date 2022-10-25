defmodule Exqlite.TimeoutSegfaultTest do
  use ExUnit.Case

  @moduletag :slow_test

  alias Exqlite.Sqlite3

  setup do
    {:ok, path} = Temp.path()
    on_exit(fn -> File.rm(path) end)

    %{path: path}
  end

  test "segfault", %{path: path} do
    {:ok, conn} =
      DBConnection.start_link(Exqlite.Connection,
        busy_timeout: 50_000,
        pool_size: 50,
        timeout: 1,
        database: path,
        journal_mode: :wal
      )

    query = %Exqlite.Query{statement: "create table foo(id integer, val integer)"}
    {:ok, _, _} = DBConnection.execute(conn, query, [])

    values = for i <- 1..1000, do: "(#{i}, #{i})"
    statement = "insert into foo(id, val) values #{Enum.join(values, ",")}"
    insert_query = %Exqlite.Query{statement: statement}

    1..5000
    |> Task.async_stream(fn _ ->
      try do
        DBConnection.execute(conn, insert_query, [], timeout: 1)
      catch
        kind, reason ->
          IO.puts("Error: #{inspect(kind)} reason: #{inspect(reason)}")
      end
    end)
    |> Stream.run()
  end

  test "race condition", %{path: path} do
    {:ok, conn} = Sqlite3.open(path)
    :ok = Sqlite3.execute(conn, "create table debug(id integer)")

    spawn_link(fn ->
      Sqlite3.prepare(conn, "insert into debug(id) values (1)")
    end)

    # ensure `Sqlite3.prepare()` is executed before we attempt to close the connection
    Process.sleep(100)
    :ok = Sqlite3.close(conn)
  end
end
