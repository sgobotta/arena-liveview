defmodule ArenaLiveviewWeb.Room.ShowLive do
  @moduledoc """
  A LiveView for creating and joining chat rooms.
  """
  use ArenaLiveviewWeb, :live_view
  alias ArenaLiveview.Organizer
  alias ArenaLiveview.ConnectedUser
  alias ArenaLiveviewWeb.Presence
  alias Phoenix.Socket.Broadcast

  @impl true
  def render(assigns) do
    ~L"""
    <div class="overlay" id="1" phx-hook="BroadcastMovement" data-user="<%= @user.uuid %>" data-users="<%= inspect @connected_users %>">
      <p <%= if @hide_info do "class=hide" end %> >
        <span class="blink">|> </span>
        Room: <span><b><%= @room.title %></b><span>
      </p>
      <p <%= if @hide_info do "class=hide" end %> > <span class="blink">|> </span>
        Live Users: <%= Enum.count(@connected_users) %>
      </p>
      <ul <%= if @hide_info do "class=hide" end %> >
        <%= if @connected_users != [] do %>
          <%= for uuid <- @connected_users do %>
            <li><img src="<%= ArenaLiveviewWeb.Endpoint.static_url() %>/images/avatars/<%= uuid %>.png" alt="<%= uuid %> avatar" /></li>
          <% end %>
        <% else %>
          <div class="loader">Loading...</div>
        <% end %>
      </ul>
      <button id="join-call"
        phx-hook="JoinCall"
        phx-click="join_call"
        <%= if @hide_info do "class=hide" end %>
      >
        Join with webcam
      </button>
      <%= content_tag :div, id: 'video-player', 'phx-hook': "VideoPlaying", data: [video_id: @room.video_id, video_time: @room.video_time] do %>
      <% end %>
      <div >
      <p>
        <span class="blink toggle-pipe <%= if @hide_info do 'down' end %>" phx-click="toggle_overlay"> |> </span>
         <%= if @hide_info do @room.title end %>
      </p>
      </div>
    </div>
    <div class="streams">
      <video id="local-video" playsinline autoplay muted width="150"></video>
      <%= for uuid <- @connected_peers do %>
        <video id="video-remote-<%= uuid %>"
          data-user-uuid="<%= uuid %>"
          playsinline
          autoplay
          phx-hook="InitUser"
          width="150"
        ></video>
      <% end %>
    </div>

    <div id="offer-requests">
      <%= for request <- @offer_requests do %>
      <span id="handle-offer-request"
        phx-hook="HandleOfferRequest"
        data-from-user-uuid="<%= request.from_user.uuid %>"
        data-stun-server-address="<%= @stun_address %>"
      />
      <% end %>
    </div>

    <div id="sdp-offers">
      <%= for sdp_offer <- @sdp_offers do %>
      <span id="handle-sdp-offer"
        phx-hook="HandleSdpOffer"
        data-from-user-uuid="<%= sdp_offer["from_user"] %>"
        data-sdp="<%= sdp_offer["description"]["sdp"] %>"
        data-stun-server-address="<%= @stun_address %>"
      />
      <% end %>
    </div>

    <div id="sdp-answers">
      <%= for answer <- @answers do %>
      <span id="handle-answer" phx-hook="HandleAnswer" data-from-user-uuid="<%= answer["from_user"] %>" data-sdp="<%= answer["description"]["sdp"] %>"></span>
      <% end %>
    </div>

    <div id="ice-candidates">
      <%= for ice_candidate_offer <- @ice_candidate_offers do %>
      <span id="handle-ice-candidate-offer" phx-hook="HandleIceCandidateOffer" data-from-user-uuid="<%= ice_candidate_offer["from_user"] %>" data-ice-candidate="<%= Jason.encode!(ice_candidate_offer["candidate"]) %>"></span>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    with uuid <- UUID.uuid4(),
         :ok <- ConnectedUser.create_user_avatar(uuid),
         user <- ConnectedUser.create_connected_user(uuid, slug) do

      connected_users = ConnectedUser.list_connected_users(slug)
      other_connected_users = Enum.filter(connected_users, fn uuid -> uuid != user.uuid end)

      Phoenix.PubSub.subscribe(ArenaLiveview.PubSub, "room:" <> slug <> ":" <> uuid)

    case Organizer.get_room(slug) do
      nil ->
        {:ok,
          socket
          |> put_flash(:error, "That room does not exist.")
          |> push_redirect(to: Routes.new_path(socket, :new))
        }
      room ->
        {:ok,
          socket
          |> assign(:user, user)
          |> assign(:slug, slug)
          |> assign(:connected_users, IO.inspect other_connected_users)
          |> assign_room(room)
          |> assign(:hide_info, false)
          |> assign(:connected_peers, [])
          |> assign(:offer_requests, [])
          |> assign(:ice_candidate_offers, [])
          |> assign(:sdp_offers, [])
          |> assign(:answers, [])
          |> assign(:stun_address, "stun:" <> System.get_env("APP_HOST") <> System.get_env("STUN_PORT"))
        }
      end
    end
  end

  # This event comes from .js and its being broadcasted to the room
  @impl true
  def handle_event("move", params, %{assigns: %{slug: slug}} = socket) do
    ConnectedUser.broadcast_movement(slug, params)
    {:noreply, socket}
  end

  @impl true
  def handle_event("video-time-sync", current_time, socket) do
    slug = socket.assigns.room.slug
    room = Organizer.get_room(slug)
    current_user = socket.assigns.user.uuid

    case current_user == room.video_tracker do
      true ->
        {:ok, _updated_room} = Organizer.update_room(room, %{video_time: current_time})
        {:noreply, socket}
      false ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_overlay", _params, socket) do
    {:noreply, assign(socket, :hide_info, !socket.assigns.hide_info)}
  end

  @impl true
  def handle_event("join_call", _params, socket) do
    IO.inspect "::: Handling join call event..."
    for user <- socket.assigns.connected_peers do
      send_direct_message(
        socket.assigns.slug,
        user,
        "request_offers",
        %{
          from_user: socket.assigns.user
        }
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("new_ice_candidate", payload, socket) do
    payload = Map.merge(payload, %{"from_user" => socket.assigns.user.uuid})

    send_direct_message(socket.assigns.slug, payload["toUser"], "new_ice_candidate", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_sdp_offer", payload, socket) do
    payload = Map.merge(payload, %{"from_user" => socket.assigns.user.uuid})

    send_direct_message(socket.assigns.slug, payload["toUser"], "new_sdp_offer", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_event("new_answer", payload, socket) do
    payload = Map.merge(payload, %{"from_user" => socket.assigns.user.uuid})

    send_direct_message(socket.assigns.slug, payload["toUser"], "new_answer", payload)
    {:noreply, socket}
  end

  # We get moves from every connected user and send them back to .js
  def handle_info({:move, params}, socket) do
    {:noreply,
     socket
     |> push_event("move", %{movement: params})}
  end

  @impl true
  def handle_info(
        %Broadcast{event: "presence_diff", payload: payload},
        %{assigns: %{slug: slug, user: user}} = socket
      ) do
    presence = ConnectedUser.list_connected_users(slug)

    handle_video_tracker_activity(slug, presence, payload)

    {:noreply,
     socket
     |> assign(:connected_users, presence)
     |> assign(:connected_peers, presence)
     |> push_event("presence-changed", %{
       presence_diff: payload,
       presence: presence,
       uuid: user.uuid
     })}
  end


  @impl true
  def handle_info(%Broadcast{event: "new_ice_candidate", payload: payload}, socket) do
    {:noreply,
      socket
      |> assign(:ice_candidate_offers, socket.assigns.ice_candidate_offers ++ [payload])
    }
  end

  @impl true
  def handle_info(%Broadcast{event: "new_sdp_offer", payload: payload}, socket) do
    {:noreply,
      socket
      |> assign(:sdp_offers, socket.assigns.ice_candidate_offers ++ [payload])
    }
  end

  @impl true
  def handle_info(%Broadcast{event: "new_answer", payload: payload}, socket) do
    {:noreply,
      socket
      |> assign(:answers, socket.assigns.answers ++ [payload])
    }
  end

  @impl true
  @doc """
  When an offer request has been received, add it to the `@offer_requests` list.
  """
  def handle_info(%Broadcast{event: "request_offers", payload: request}, socket) do
    {:noreply,
      socket
      |> assign(:offer_requests, socket.assigns.offer_requests ++ [request])
    }
  end

  defp handle_video_tracker_activity(slug, presence, %{leaves: leaves}) do
    room = Organizer.get_room(slug)
    video_tracker = room.video_tracker

    case video_tracker in leaves do
      false -> nil
      case presence do
        [] -> nil
        presences ->
          first_presence = hd presences
          IO.inspect "::: First Presence :::"
          IO.inspect video_tracker
          Organizer.update_room(room, %{video_tracker: first_presence})
      end
    end
  end

  defp assign_room(socket, room) do
    presences = list_present(socket)
    user = socket.assigns.user
    filtered_presences = Enum.filter(presences, fn uuid -> uuid != user.uuid end)

    case filtered_presences do
      [] ->
        {:ok, updated_room} = Organizer.update_room(room, %{video_time: 0, video_tracker: user.uuid})
        socket
        |> assign(:room, updated_room)
      _xs ->
        socket
        |> assign(:room, room)
    end
  end

  defp list_present(socket) do
    Presence.list("room:" <> socket.assigns.slug)
    # Check extra metadata needed from Presence
    |> Enum.map(fn {k, _} -> k end)
  end

  defp send_direct_message(slug, to_user, event, payload) do
    ArenaLiveviewWeb.Endpoint.broadcast_from(
      self(),
      "room:" <> slug <> ":" <> to_user,
      event,
      payload
    )
  end
end
