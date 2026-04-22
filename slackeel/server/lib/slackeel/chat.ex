defmodule Slackeel.Chat do
  @moduledoc """
  Persisted multi-conversation chat, scoped by `owner_key` (session).

  New threads get `Conversation <n>` where *n* is 1 + the current row count for that owner
  (see `default_conversation_title/1`). After the first user + assistant turn completes, a
  one-shot Ollama completion (`Slackeel.Ollama.Chat`, same model as the reply) may replace
  the title; refresh via PubSub on `chat_owner_topic/1`.
  """
  import Ecto.Query

  require Logger

  alias Slackeel.Repo
  alias Slackeel.Chat.{Conversation, Message}

  @title_max 72
  @default_conversation_re ~r/^Conversation [0-9]+$/

  @doc "Phoenix.PubSub topic to notify chat UIs when a conversation title is updated (async LLM)."
  def chat_owner_topic(owner_key) when is_binary(owner_key), do: "chat:owner:" <> owner_key

  @doc """
  Returns the next default title, e.g. "Conversation 3" when the owner has two existing threads.
  """
  def default_conversation_title(owner_key) when is_binary(owner_key) do
    n =
      from(c in Conversation,
        where: c.owner_key == ^owner_key
      )
      |> select([c], count(c.id))
      |> Repo.one!()

    "Conversation #{n + 1}"
  end

  def list_conversations(owner_key) when is_binary(owner_key) do
    from(c in Conversation,
      where: c.owner_key == ^owner_key,
      order_by: [desc: c.updated_at]
    )
    |> Repo.all()
  end

  def get_conversation(owner_key, id) when is_binary(owner_key) and is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        case Repo.get(Conversation, uuid) do
          nil ->
            {:error, :not_found}

          %Conversation{owner_key: ^owner_key} = c ->
            {:ok, c}

          _ ->
            {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  def create_conversation(owner_key, attrs \\ %{}) when is_binary(owner_key) do
    title = Map.get(attrs, :title)

    %Conversation{}
    |> Conversation.changeset(%{owner_key: owner_key, title: title})
    |> Repo.insert()
  end

  def list_messages(conversation_id) when is_binary(conversation_id) do
    case Ecto.UUID.cast(conversation_id) do
      {:ok, uuid} ->
        from(m in Message,
          where: m.conversation_id == ^uuid,
          order_by: [asc: m.inserted_at, asc: m.id]
        )
        |> Repo.all()

      :error ->
        []
    end
  end

  def messages_for_liveview(conversation_id) when is_binary(conversation_id) do
    conversation_id
    |> list_messages()
    |> Enum.map(&message_to_live_map/1)
  end

  defp message_to_live_map(%Message{} = m) do
    %{
      id: m.id |> to_string(),
      role: m.role,
      content: m.content || "",
      model: m.model
    }
  end

  def append_user_and_assistant(conversation_id, user_body, model)
      when is_binary(conversation_id) and is_binary(user_body) and is_binary(model) do
    uuid = Ecto.UUID.cast!(conversation_id)

    Repo.transaction(fn ->
      {:ok, user} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: uuid,
          role: "user",
          content: user_body,
          model: model
        })
        |> Repo.insert()

      {:ok, assistant} =
        %Message{}
        |> Message.changeset(%{
          conversation_id: uuid,
          role: "assistant",
          content: "",
          model: model
        })
        |> Repo.insert()

      touch_conversation!(uuid)

      {message_to_live_map(user), message_to_live_map(assistant)}
    end)
  end

  @doc false
  def schedule_suggest_conversation_title!(owner_key, conv_id, model)
      when is_binary(owner_key) and is_binary(conv_id) and is_binary(model) do
    _ =
      Task.Supervisor.start_child(Slackeel.Ollama.HotTaskSupervisor, fn ->
        try do
          maybe_suggest_conversation_title_llm(owner_key, conv_id, model)
        rescue
          e ->
            Logger.warning("chat: title suggest task failed: #{Exception.message(e)}")
        end
      end)

    :ok
  end

  defp default_conversation_title?(%Conversation{title: t}), do: default_conversation_title?(t)

  defp default_conversation_title?(t) when is_binary(t) do
    String.match?(t, @default_conversation_re)
  end

  defp default_conversation_title?(_), do: false

  defp maybe_suggest_conversation_title_llm(owner_key, conv_id, model) do
    with {:ok, uuid} <- Ecto.UUID.cast(conv_id),
         %Conversation{} = conv <- Repo.get(Conversation, uuid),
         true <- conv.owner_key == owner_key,
         true <- default_conversation_title?(conv),
         msgs = list_messages(conv_id),
         true <- length(msgs) == 2 do
      [u, a] = msgs

      if u.role == "user" and a.role == "assistant" do
        u_text = (u.content || "") |> String.slice(0, 2000)
        a_text = (a.content || "") |> String.slice(0, 2000)

        system =
          "You write short list titles for a multi-chat UI. Output exactly one line, at most 8 words, no surrounding quotes, summarizing the topic. If unsure, use a very short label."

        user_msg = "User said:\n#{u_text}\n\nAssistant said:\n#{a_text}"

        messages = [
          %{"role" => "system", "content" => system},
          %{"role" => "user", "content" => user_msg}
        ]

        case Slackeel.Ollama.Chat.completion(model, messages, []) do
          {:ok, text, _meta} when is_binary(text) and text != "" ->
            title =
              text
              |> first_line()
              |> String.replace(~r/[\r\n]+/u, " ")
              |> String.trim()
              |> String.slice(0, @title_max)

            if title != "" do
              _ =
                conv
                |> Conversation.changeset(%{title: title})
                |> Repo.update!()

              Phoenix.PubSub.broadcast(
                Slackeel.PubSub,
                chat_owner_topic(owner_key),
                {:chat_conversation_titled, conv_id, title}
              )
            end

          {:ok, _text, _meta} ->
            :ok

          {:error, err} ->
            Logger.warning("chat: Ollama title suggest failed: #{inspect(err)}")
        end
      else
        :ok
      end
    else
      _ -> :ok
    end
  end

  defp first_line(<<>>), do: ""

  defp first_line(bin) when is_binary(bin) do
    case String.split(bin, "\n", parts: 2) do
      [h] -> h
      [h | _] -> h
    end
  end

  defp touch_conversation!(conversation_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    from(c in Conversation, where: c.id == ^conversation_id)
    |> Repo.update_all(set: [updated_at: now])
  end

  def update_message_content!(message_id, content)
      when is_binary(message_id) and is_binary(content) do
    uuid = Ecto.UUID.cast!(message_id)

    case Repo.get(Message, uuid) do
      nil ->
        {:error, :not_found}

      msg ->
        msg
        |> Message.changeset(%{content: content})
        |> Repo.update()
    end
  end
end
