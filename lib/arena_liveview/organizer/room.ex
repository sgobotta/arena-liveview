defmodule ArenaLiveview.Organizer.Room do
  @moduledoc """
  Schema for creating video chat rooms.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "rooms" do
    field :title, :string
    field :slug, :string
    field :video_id, :string

    timestamps()
  end

  @fields [:title, :slug, :video_id]

  def changeset(room, attrs) do
    room
    |> cast(attrs, @fields)
    |> validate_required([:title, :slug])
    |> format_slug()
    |> unique_constraint(:slug)
  end

  defp format_slug(%Ecto.Changeset{changes: %{slug: _}} = changeset) do
    changeset
    |> update_change(:slug, fn slug ->
      slug
      |> String.downcase()
      |> String.replace(" ", "-")
    end)
  end
  defp format_slug(changeset), do: changeset
end
