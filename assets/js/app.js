import ("regenerator-runtime/runtime");
import "../css/app.scss";

import "phoenix_html";
import { Socket, Presence } from "phoenix";
import NProgress from "nprogress";
import { LiveSocket } from "phoenix_live_view";
import { Scene } from "3d-css-scene";

import BroadcastMovementHook from "./hooks/movement";
import VideoPlayingHook from "./hooks/video-playing";

const scene = new Scene();
const room = scene.createRoom("room", 3600, 1080, 3000);

// This element should be captured and inserted before any side-effect during
// liveview hooks. For some reason, an appended element bugs the DOM whenever
// it's being manipulated during a hook life-cycle.
const playerContainer = document.getElementById("player-container");
playerContainer && room.north.insert(playerContainer);

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)

let users = {}

function addUserConnection(userUuid) {
  if (users[userUuid] === undefined) {
    users[userUuid] = {
      peerConnection: null
    }
  }

  return users
}

function removeUserConnection(userUuid) {
  delete users[userUuid]

  return users
}

let localStream

function initStream() {
  try {
    // Gets our local media from the browser and stores it as a const, stream.
    navigator.mediaDevices.getUserMedia({audio: true, video: true, width: "1280"})
    .then(stream => {
      // Stores our stream in the global constant, localStream.
      localStream = stream
      // Sets our local video element to stream from the user's webcam (stream).
      document.getElementById("local-video").srcObject = stream
    })
  } catch (e) {
    console.log(e)
  }
}

// lv       - Our LiveView hook's `this` object.
// fromUser - The user to create the peer connection with.
// offer    - Stores an SDP offer if it was passed to the function.
function createPeerConnection(lv, fromUser, offer) {
  // Creates a variable for our peer connection to reference within
  // this function's scope.
  let newPeerConnection = new RTCPeerConnection({
    iceServers: [
      // We're going to get into STUN servers later, but for now, you
      // may use ours for this portion of development.
      { urls: "stun:127.0.0.1:3478" }
    ]
  })

  console.log('::: NEW PEER CONNECTION ::: ', newPeerConnection)

  // Add this new peer connection to our `users` object.
  users[fromUser].peerConnection = newPeerConnection;

  // Add each local track to the RTCPeerConnection.
  localStream.getTracks().forEach(track => newPeerConnection.addTrack(track, localStream))

  // If creating an answer, rather than an initial offer.
  if (offer !== undefined) {
    newPeerConnection.setRemoteDescription({type: "offer", sdp: offer})
    newPeerConnection.createAnswer()
      .then((answer) => {
        newPeerConnection.setLocalDescription(answer)
        console.log("Sending this ANSWER to the requester:", answer)
        lv.pushEvent("new_answer", {toUser: fromUser, description: answer})
      })
      .catch((err) => console.log(err))
  }

  newPeerConnection.onicecandidate = async ({candidate}) => {
    // fromUser is the new value for toUser because we're sending this data back
    // to the sender
    lv.pushEvent("new_ice_candidate", {toUser: fromUser, candidate})
  }

  // Don't add the `onnegotiationneeded` callback when creating an answer due to
  // a bug in Chrome's implementation of WebRTC.
  if (offer === undefined) {
    newPeerConnection.onnegotiationneeded = async () => {
      try {
        newPeerConnection.createOffer()
          .then((offer) => {
            newPeerConnection.setLocalDescription(offer)
            console.log("Sending this OFFER to the requester:", offer)
            lv.pushEvent("new_sdp_offer", {toUser: fromUser, description: offer})
          })
          .catch((err) => console.log(err))
      }
      catch (error) {
        console.log(error)
      }
    }
  }

  // When the data is ready to flow, add it to the correct video.
  newPeerConnection.ontrack = async (event) => {
    console.log("Track received:", event)
    document.getElementById(`video-remote-${fromUser}`).srcObject = event.streams[0]
  }

  return newPeerConnection;
}

let Hooks = {
  BroadcastMovement: BroadcastMovementHook(scene),
  VideoPlaying: VideoPlayingHook(playerContainer),
  JoinCall: {
    mounted() {
      initStream()
    }
  },
  InitUser: {
    mounted () {
      addUserConnection(this.el.dataset.userUuid)
    },
    destroyed () {
      removeUserConnection(this.el.dataset.userUuid)
    }
  },
  HandleOfferRequest: {
    mounted () {
      console.log("new offer request from", this.el.dataset.fromUserUuid)
      let fromUser = this.el.dataset.fromUserUuid
      createPeerConnection(this, fromUser)
    }
  },
  HandleIceCandidateOffer: {
    mounted () {
      let data = this.el.dataset
      let fromUser = data.fromUserUuid
      let iceCandidate = JSON.parse(data.iceCandidate)
      let peerConnection = users[fromUser].peerConnection
  
      console.log("new ice candidate from", fromUser, iceCandidate)
  
      peerConnection.addIceCandidate(iceCandidate)
    }
  },
  HandleSdpOffer: {
    mounted () {
      let data = this.el.dataset
      let fromUser = data.fromUserUuid
      let sdp = data.sdp
      console.log('::: HandleSdpOffer ::: ', data)
      if (sdp != "") {
        console.log("new sdp OFFER from", data.fromUserUuid, data.sdp)
  
        createPeerConnection(this, fromUser, sdp)
      }
    }
  },
  HandleAnswer: {
    mounted () {
      let data = this.el.dataset
      let fromUser = data.fromUserUuid
      let sdp = data.sdp
      let peerConnection = users[fromUser].peerConnection
  
      if (sdp != "") {
        console.log("new sdp ANSWER from", fromUser, sdp)
        peerConnection.setRemoteDescription({type: "answer", sdp: sdp})
      }
    }
  }
};


const liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  params: { _csrf_token: csrfToken },
});

liveSocket.connect();
window.liveSocket = liveSocket;

room.translateZ(-200);
room.update();
