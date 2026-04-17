defmodule Speedeel.Guides do
  @moduledoc "Lists and reads Markdown guides from a trusted directory on disk."

  @slug_re ~r/^[a-zA-Z0-9_-]+$/

  def root do
    Application.get_env(:speedeel, :guides_root) ||
      raise "guides_root not configured (set TELVM_GUIDES_ROOT or :guides_root in config)"
  end

  @doc "Returns `[%{slug: \"readme\", title: \"...\", basename: \"README.md\"}, ...]` sorted by basename."
  def list_pages do
    dir = root()

    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".md"))
        |> Enum.sort()
        |> Enum.map(fn name ->
          stem = String.replace_suffix(name, ".md", "")
          slug = String.downcase(stem)
          path = Path.join(dir, name)
          title = title_for(path, slug)
          %{slug: slug, title: title, basename: name}
        end)

      {:error, _} ->
        []
    end
  end

  defp title_for(path, slug_fallback) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", parts: 2)
        |> List.first()
        |> case do
          nil ->
            humanize(slug_fallback)

          line ->
            line = String.trim(line)

            cond do
              String.starts_with?(line, "# ") ->
                String.trim_leading(line, "# ")

              String.starts_with?(line, "#") ->
                line |> String.trim_leading("#") |> String.trim()

              true ->
                humanize(slug_fallback)
            end
        end

      {:error, _} ->
        humanize(slug_fallback)
    end
  end

  defp humanize(slug) do
    slug
    |> String.replace("-", " ")
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  @doc "Reads the `.md` file whose basename matches `slug` case-insensitively (e.g. `readme` → `README.md`)."
  def read_markdown(slug) when is_binary(slug) do
    if Regex.match?(@slug_re, slug) do
      dir = root()

      case File.ls(dir) do
        {:ok, names} ->
          match =
            Enum.find(names, fn n ->
              String.ends_with?(n, ".md") &&
                (n |> String.replace_suffix(".md", "") |> String.downcase()) == slug
            end)

          case match do
            nil ->
              {:error, :not_found}

            basename ->
              path = Path.join(dir, basename)
              resolved = Path.expand(path)
              root_exp = Path.expand(dir)

              if String.starts_with?(resolved, root_exp) and File.regular?(resolved) do
                File.read(resolved)
              else
                {:error, :not_found}
              end
          end

        {:error, _} ->
          {:error, :not_found}
      end
    else
      {:error, :invalid_slug}
    end
  end

  def render_html(markdown) when is_binary(markdown) do
    Earmark.as_html!(markdown, %Earmark.Options{gfm: true, breaks: true})
  end
end
