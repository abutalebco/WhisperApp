defmodule WhisperAppWeb.TranscribeLive do
  use WhisperAppWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(transcript: nil, loading: false)
     |> allow_upload(:audio,
       accept: ~w(.mp3 .wav .m4a .ogg .flac),
       max_entries: 1,
       max_file_size: 50_000_000
     )}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("save", _params, socket) do
    paths =
      consume_uploaded_entries(socket, :audio, fn %{path: tmp}, entry ->
        dest = Path.join(System.tmp_dir!(), "#{entry.uuid}-#{entry.client_name}")
        File.cp!(tmp, dest)
        {:ok, dest}
      end)

    case paths do
      [path] ->
        {:noreply,
         socket
         |> assign(loading: true, transcript: nil)
         |> start_async(:transcribe, fn ->
           result = Nx.Serving.batched_run(WhisperServing, {:file, path})
           File.rm(path)
           result
         end)}

      _ ->
        {:noreply, put_flash(socket, :error, "Choose a file first")}
    end
  end

  def handle_event("cancel", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :audio, ref)}
  end

  defp error_to_string(:too_large), do: "File is too large (max 50 MB)"
  defp error_to_string(:not_accepted), do: "Unsupported file type"
  defp error_to_string(:too_many_files), do: "Only one file at a time"
  defp error_to_string(_), do: "Upload error"

  def handle_async(:transcribe, {:ok, %{chunks: chunks}}, socket) do
    text = chunks |> Enum.map_join(" ", & &1.text) |> String.trim()
    {:noreply, assign(socket, transcript: text, loading: false)}
  end

  def handle_async(:transcribe, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(loading: false)
     |> put_flash(:error, "Failed: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mx-auto max-w-2xl space-y-6 py-10">
        <div class="text-center">
          <h1 class="text-3xl font-bold">Audio Transcriber</h1>
          <p class="mt-1 text-base-content/70">Upload audio, get text. Powered by Whisper.</p>
        </div>

        <form id="upload-form" phx-submit="save" phx-change="validate" class="space-y-4">
          <label
            for={@uploads.audio.ref}
            phx-drop-target={@uploads.audio.ref}
            class="flex cursor-pointer flex-col items-center justify-center gap-2 rounded-box border-2 border-dashed border-base-300 p-10 text-center transition hover:border-primary"
          >
            <.icon name="hero-microphone" class="size-10 text-primary" />
            <span class="font-medium">Drop an audio file or click to browse</span>
            <span class="text-sm text-base-content/60">MP3, WAV, OGG, FLAC, M4A · up to 50 MB</span>
            <.live_file_input upload={@uploads.audio} class="hidden" />
          </label>

          <p :for={err <- upload_errors(@uploads.audio)} class="text-sm text-error">
            {error_to_string(err)}
          </p>

          <div :for={entry <- @uploads.audio.entries} class="space-y-2 rounded-box bg-base-200 p-4">
            <div class="flex items-center justify-between">
              <span class="truncate font-medium">{entry.client_name}</span>
              <button type="button" phx-click="cancel" phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs" aria-label="Remove">✕</button>
            </div>
            <progress class="progress progress-primary w-full" value={entry.progress} max="100"></progress>
            <p :for={err <- upload_errors(@uploads.audio, entry)} class="text-sm text-error">
              {error_to_string(err)}
            </p>
          </div>

          <button type="submit" class="btn btn-primary w-full"
            disabled={@loading or @uploads.audio.entries == []}>
            <span :if={@loading} class="loading loading-spinner"></span>
            {if @loading, do: "Transcribing...", else: "Transcribe"}
          </button>
        </form>

        <div :if={@transcript} class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">Transcript</h2>
              <button type="button" class="btn btn-outline btn-sm"
                onclick="navigator.clipboard.writeText(document.getElementById('transcript').innerText)">
                Copy
              </button>
            </div>
            <p id="transcript" class="whitespace-pre-wrap leading-relaxed">{@transcript}</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
