defmodule Kungfuig do
  @moduledoc """
  The behaviour defining the dynamic config provider.
  """

  @typedoc "The config map to be updated and exposed through callback"
  @type config :: %{required(atom()) => term()}

  @typedoc """
  The callback to be used for subscibing to config updates.

  Might be an anonymous function, an `{m, f}` tuple accepting a single argument,
  or a process identifier accepting `call`, `cast` or simple message (`:info`.)
  """
  @type callback ::
          {module(), atom()}
          | (config() -> :ok)
          | {GenServer.name() | pid(), {:call | :cast | :info, atom()}}

  @typedoc "The option that can be passed to `start_link/1` function"
  @type option ::
          {:callback, callback()}
          | {:interval, non_neg_integer()}
          | {:anonymous, boolean()}
          | {:start_options, [GenServer.option()]}
          | {atom(), term()}

  @typedoc "The `start_link/1` function wrapping the `GenServer.start_link/3`"
  @callback start_link(opts :: [option()]) :: GenServer.on_start()

  @doc "The actual implementation to update the config"
  @callback update_config(state :: t()) :: config()

  @doc "The config that is manages by this behaviour is a simple map"
  @type t :: %{
          __struct__: Kungfuig,
          __meta__: [option()],
          state: config()
        }

  @default_interval 1_000

  defstruct __meta__: [], state: %{}

  @doc false
  @spec __using__(opts :: [option()]) :: tuple()
  defmacro __using__(opts) do
    {anonymous, opts} = Keyword.pop(opts, :anonymous, false)

    quote location: :keep do
      use GenServer
      @behaviour Kungfuig

      @impl Kungfuig
      def start_link(opts) do
        opts = Keyword.merge(unquote(opts), opts)

        {start_options, opts} = Keyword.pop(opts, :start_options, [])

        case Keyword.get(opts, :callback) do
          nil -> :ok
          {target, {type, name}} when type in [:call, :cast, :info] and is_atom(name) -> :ok
          {m, f} when is_atom(m) and is_atom(f) -> :ok
          f when is_function(f, 1) -> :ok
          other -> raise "Expected callable, got: " <> inspect(other)
        end

        opts = Keyword.put_new(opts, :interval, unquote(@default_interval))

        start_options =
          if unquote(anonymous),
            do: Keyword.delete(start_options, :name),
            else: Keyword.put_new(start_options, :name, __MODULE__)

        GenServer.start_link(__MODULE__, %Kungfuig{__meta__: opts}, start_options)
      end

      @impl Kungfuig
      def update_config(%Kungfuig{state: state}), do: state

      defoverridable Kungfuig

      @impl GenServer
      def init(%Kungfuig{} = state),
        do: {:ok, state, {:continue, :update}}

      @impl GenServer
      def handle_info(:update, %Kungfuig{} = state),
        do: {:noreply, state, {:continue, :update}}

      @impl GenServer
      def handle_continue(:update, %Kungfuig{__meta__: opts, state: state} = config) do
        state = update_config(config)
        unless is_nil(opts[:callback]), do: send_callback(opts[:callback], state)
        Process.send_after(self(), :update, opts[:interval])
        {:noreply, %Kungfuig{config | state: state}}
      end

      @impl GenServer
      def handle_call(:state, _from, %Kungfuig{} = state),
        do: {:reply, state, state}

      @spec send_callback(Kungfuig.callback(), Kungfuig.config()) :: :ok
      defp send_callback({target, {:info, m}}, state),
        do: send(target, {m, state})

      defp send_callback({target, {type, m}}, state),
        do: apply(GenServer, type, [target, {m, state}])

      defp send_callback({m, f}, state), do: apply(m, f, [state])
      defp send_callback(f, state) when is_function(f, 1), do: f.(state)
    end
  end
end
