import { io } from "socket.io-client";
let socket;

const urls = {
  421613: "wss://arb-goerli.vrf.sh",
}

const connect = (chainId) => {
  if (urls[chainId] === undefined) throw new Error(`Randomizer Sequencer: Chain ID ${chainId} not supported`)
  socket = io(urls[chainId]);
  return socket;
}

export const listenForPreview = async (/** @type {Number} */ id, /** @type {Number} */ chainId) => {
  return new Promise((resolve, reject) => {
    if (!socket) socket = connect(chainId);
    socket.on("connect", () => {
      console.log("connected");
    });

    socket.emit("listenForPreview", id);
    socket.on("complete", (data) => {
      if (data.id === id) {
        resolve(data.result);
      }
    });
  });
}