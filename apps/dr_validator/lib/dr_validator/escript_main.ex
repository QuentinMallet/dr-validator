defmodule DrValidator.EscriptMain do
  @moduledoc """
  Escript entry point for the `dr-validator-run` binary.

  Delegates logic to `DrValidator.CLI.main/1` (which returns an integer exit
  code) and halts the BEAM with that code so the OS sees the correct `$?`.

  Keeping the halt here rather than inside `CLI.main/1` lets tests call
  `CLI.main/1` directly and assert on the returned integer without triggering
  `System.halt/1` in the test process.
  """

  @doc """
  Escript entry — invoked by the generated `dr-validator-run` binary with
  `System.argv()`. Never returns; always calls `System.halt/1`.
  """
  @spec main([String.t()]) :: no_return()
  def main(argv) do
    # Trap EXIT signals so Task.async-linked validator processes that call
    # exit/1 surface as {:exit, reason} in Task.yield rather than killing
    # the CLI process before the yield clause can handle them.
    Process.flag(:trap_exit, true)
    System.halt(DrValidator.CLI.main(argv))
  end
end
