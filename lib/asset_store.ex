defmodule AssetStore do
  use GenServer
  alias Exqlite.Sqlite3NIF
  require SqliteStore

  @version 0

  @creations %{
    "account" => SQL.readFile!("lib/sql/wallet.sql"),
    "assets" => SQL.readFile!("lib/sql/token.sql") ++ SQL.readFile!("lib/sql/domain.sql"),
    "blockchain" => SQL.readFile!("lib/sql/block.sql"),
    "dns" => SQL.readFile!("lib/sql/dns.sql"),
    "main" => SQL.readFile!("lib/sql/env.sql")
  }

  @statements SQL.readFileStmt!("lib/sql/assets.stmt.sql")

  # SQL.readFileStmt!("lib/sql/assets_alter.stmt.sql")
  @alter []

  # databases
  @attaches %{
    "account" => "accounts.db",
    "assets" => "assets.db",
    "dns" => "dns.db",
    "blockchain" => "blockchain.db"
  }

  @name "main"
  @filename "main.db"

  def start_link(basepath) do
    GenServer.start_link(__MODULE__, basepath, name: __MODULE__)
  end

  @impl true
  def init(basepath) do
    filename = Path.join(basepath, @filename)

    {:ok, conn} = SqliteStore.open_setup(@name, filename, @creations, @attaches)
    # execute alter tables if exists new version
    :ok = SqliteStore.check_version(conn, @alter, @version)
    # prepare statements
    {:ok, stmts} = SqliteStore.prepare_statements(conn, @statements)
    SqliteStore.begin(conn)
    # put in global conn and statements
    :persistent_term.put(:asset_conn, conn)
    :persistent_term.put(:asset_stmt, stmts)

    {:ok, %{}, :hibernate}
  end

  def commit(conn) do
    :gen_server.call(__MODULE__, {:commit, conn}, :infinity)
  end

  @impl true
  def handle_call({:commit, conn}, _from, state) do
    SqliteStore.commit(conn)
    SqliteStore.begin(conn)
    {:reply, :ok, state, :hibernate}
  end

  @impl true
  def terminate(_reason, _state) do
    conn = :persistent_term.get(:asset_conn)
    stmts = :persistent_term.get(:asset_stmt)
    SqliteStore.release_statements(conn, stmts)
    Sqlite3NIF.close(conn)
    :persistent_term.erase(:asset_stmt)
    :persistent_term.erase(:asset_conn)
    :ok
  end
end
