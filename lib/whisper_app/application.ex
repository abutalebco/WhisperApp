defmodule WhisperApp.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WhisperAppWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:whisper_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: WhisperApp.PubSub},
      {Nx.Serving,
       serving: whisper_serving(),
       name: WhisperServing,
       batch_size: 4,
       batch_timeout: 100},
      WhisperAppWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: WhisperApp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp whisper_serving do
    repo = {:hf, "openai/whisper-tiny"}

    {:ok, model} = Bumblebee.load_model(repo)
    {:ok, featurizer} = Bumblebee.load_featurizer(repo)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, gen_config} = Bumblebee.load_generation_config(repo)

    Bumblebee.Audio.speech_to_text_whisper(model, featurizer, tokenizer, gen_config,
      chunk_num_seconds: 30,
      defn_options: [compiler: EXLA]
    )
  end

  @impl true
  def config_change(changed, _new, removed) do
    WhisperAppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
