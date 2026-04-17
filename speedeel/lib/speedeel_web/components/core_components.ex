defmodule SpeedeelWeb.CoreComponents do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: SpeedeelWeb.Gettext

  attr :id, :string, default: "flash-group"
  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <div id={@id} class="fixed bottom-4 right-4 z-50 space-y-2 max-w-sm" aria-live="polite">
      <.flash_line kind={:info} flash={@flash} />
      <.flash_line kind={:error} flash={@flash} />
    </div>
    """
  end

  attr :id, :string, default: nil
  attr :flash, :map, required: true
  attr :kind, :atom, values: [:info, :error], required: true

  def flash_line(assigns) do
    msg = Phoenix.Flash.get(assigns.flash, assigns.kind)
    assigns = assign(assigns, :msg, msg)

    ~H"""
    <%= if @msg do %>
      <div
        id={@id || "flash-#{@kind}"}
        class={[
          "rounded-lg px-4 py-3 text-sm shadow-lg border font-mono text-[12px]",
          @kind == :info &&
            "bg-[var(--telvm-panel-bg)] border border-[var(--telvm-accent-border)] text-[var(--telvm-shell-fg)]",
          @kind == :error && "telvm-error-box"
        ]}
        role="alert"
      >
        {@msg}
      </div>
    <% end %>
    """
  end
end
