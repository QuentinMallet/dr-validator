defmodule DrValidator.WallabySmokeTest do
  use ExUnit.Case, async: false
  use Wallaby.Feature

  # Wallaby.Browser.visit/2 only accepts http/https URLs (uri.host must be non-nil
  # for the path to pass through unchanged). data: URIs have uri.host == nil, so
  # we inject content via execute_script instead — this proves session + DOM
  # interaction both work in the nix dev shell.
  feature "Wallaby + chromedriver can interact with a page", %{session: session} do
    session
    |> execute_script("""
      document.open();
      document.write('<html><body><h1>hello</h1></body></html>');
      document.close();
    """)
    |> assert_text("hello")
  end
end
