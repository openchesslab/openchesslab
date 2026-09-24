defmodule PositionDB.PropertyIndex do
  @moduledoc """
  Logical property index backed by a configurable storage backend.

  The default backend is the in-memory implementation.

  The result-oriented functions are used by storage-aware code.
  The convenience functions preserve the original in-memory API.
  """

  alias PositionDB.PropertyIndex.Memory

  @type property :: {atom(), term()}
  @type position_id :: pos_integer()

  @type t :: %__MODULE__{
          backend_module: module(),
          backend: term()
        }

  defstruct [
    :backend_module,
    :backend
  ]

  @spec new() :: t()
  def new do
    new(
      Memory,
      Memory.new()
    )
  end

  @spec new(module(), term()) :: t()
  def new(
        backend_module,
        backend
      )
      when is_atom(backend_module) do
    %__MODULE__{
      backend_module: backend_module,
      backend: backend
    }
  end

  @spec add(
          t(),
          property(),
          position_id()
        ) ::
          t()
          | {:error, term()}
  def add(
        %__MODULE__{} = index,
        property,
        position_id
      ) do
    case add_result(
           index,
           property,
           position_id
         ) do
      {:ok, index} ->
        index

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec add_result(
          t(),
          property(),
          position_id()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def add_result(
        %__MODULE__{
          backend_module: backend_module,
          backend: backend
        } = index,
        property,
        position_id
      ) do
    case backend_module.add(
           backend,
           property,
           position_id
         ) do
      {:ok, next_backend} ->
        {:ok,
         %{
           index
           | backend: next_backend
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec advance_result(
          t(),
          position_id()
        ) ::
          {:ok, t()}
          | {:error, term()}
  def advance_result(
        %__MODULE__{
          backend_module: backend_module,
          backend: backend
        } = index,
        position_id
      ) do
    case backend_module.advance(
           backend,
           position_id
         ) do
      {:ok, next_backend} ->
        {:ok,
         %{
           index
           | backend: next_backend
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec lookup(
          t(),
          property()
        ) ::
          MapSet.t(position_id())
          | {:error, term()}
  def lookup(
        %__MODULE__{} = index,
        property
      ) do
    case lookup_ids(
           index,
           property
         ) do
      {:ok, position_ids} ->
        MapSet.new(position_ids)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec lookup_ids(
          t(),
          property()
        ) ::
          {:ok, [position_id()]}
          | {:error, term()}
  def lookup_ids(
        %__MODULE__{
          backend_module: backend_module,
          backend: backend
        },
        property
      ) do
    backend_module.lookup(
      backend,
      property
    )
  end

  @spec cardinality(
          t(),
          property()
        ) ::
          non_neg_integer()
          | {:error, term()}
  def cardinality(
        %__MODULE__{} = index,
        property
      ) do
    case cardinality_result(
           index,
           property
         ) do
      {:ok, count} ->
        count

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec cardinality_result(
          t(),
          property()
        ) ::
          {:ok, non_neg_integer()}
          | {:error, term()}
  def cardinality_result(
        %__MODULE__{
          backend_module: backend_module,
          backend: backend
        },
        property
      ) do
    backend_module.cardinality(
      backend,
      property
    )
  end
end
