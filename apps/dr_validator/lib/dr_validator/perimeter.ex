defmodule DrValidator.Perimeter do
  @moduledoc """
  A named set of apps that must be validated together as a DR perimeter.

  This struct is the canonical in-memory representation. PerimeterLoader
  (task .5) is responsible for deserialising JSON/YAML sources into this shape.
  """

  @enforce_keys [:id, :apps]
  defstruct [:id, apps: []]

  @type t :: %__MODULE__{
          id: String.t(),
          apps: [String.t()]
        }
end
