<script>
  import { listenForPreview } from "@randomizer.ai/sequencer-client"
  import { defaultEvmStores, chainId, signerAddress, connected, contracts } from "svelte-ethers-store"
  import Web3Modal from "web3modal"
  import { onMount } from "svelte"
  import { ethers } from "ethers"
  import abi from "./abi/coinflip.json"
  import randomizerAbi from "./abi/randomizer.json"
  import { SvelteToast } from "@zerodevx/svelte-toast"
  import { toast } from "@zerodevx/svelte-toast"

  let web3Modal
  let results = []
  let balance
  let displayedResults = []

  onMount(async () => {
    // Initialize web3modal
    web3Modal = new Web3Modal({
      theme: "dark",
    })
    const provider = await web3Modal.connect()
    await defaultEvmStores.setProvider(provider)

    // Attach contracts
    if (import.meta.env["VITE_CONTRACT"]) {
      await defaultEvmStores.attachContract(
        "coinflip",
        //@ts-ignore
        import.meta.env["VITE_CONTRACT"],
        JSON.stringify(abi)
      )

      await defaultEvmStores.attachContract(
        "randomizer",
        //@ts-ignore
        import.meta.env["VITE_CONTRACT_RANDOMIZER"],
        JSON.stringify(randomizerAbi)
      )

      // Get saved results from localStorage
      const storedResults = localStorage.getItem("results." + $chainId)
      if (storedResults) {
        results = JSON.parse(storedResults)
      }

      // This contract uses a fake balance. Real smart contract games should have on-chain balances.
      const storedBalance = Number(localStorage.getItem("balance"))
      if (storedBalance && storedBalance > 0) {
        balance = storedBalance
      } else {
        balance = 100
        localStorage.setItem("balance", String(100))
      }
    }

    // Listen for FlipResult contract event and update the stored result
    // A real game should refresh the player's on-chain parameters (e.g. token balance) here as well
    $contracts.coinflip.on("FlipResult", async (player, id, seed, prediction, headsOrTails) => {
      if (results.length) {
        id = ethers.BigNumber.from(id).toNumber()
        console.log("FlipResult", player, id, seed, prediction, headsOrTails)
        console.log(player)
        console.log($signerAddress)
        console.log(results[id])
        if (player == $signerAddress) {
          console.log(results[id])
          if (results[id] && !Object.keys(results[id]).includes("realSeed")) {
            toast.push("Callback verified on-chain", {
              theme: {
                "--toastBackground": "#48BB78",
                "--toastBarBackground": "#2F855A",
              },
            })

            const previewSeed = Object.keys(Object(results[id])).includes("previewSeed") ? results[id].previewSeed : ""
            results[id] = {
              previewSeed,
              realSeed: ethers.BigNumber.from(seed).toString(),
              prediction: prediction ? "tails" : "heads",
              result: headsOrTails ? "tails" : "heads",
            }
            localStorage.setItem("results." + $chainId, JSON.stringify(results))
          }
        }
      }
    })
  })

  // Have displayedResults only be the 5 most recent results
  $: if (results) {
    // displayedResults should be the the 5 latest results
    if (results.length > 5) {
      displayedResults = results.slice(Math.max(results.length - 5, 0))
    } else {
      displayedResults = results
    }
  }

  let error
  $: if ($chainId != 421613) {
    error = "Please connect to Arbitrum Nitro Goerli Testnet"
  } else {
    error = undefined
  }

  // Update any contract state values here that belong to the connected wallet
  const updateContractVars = async () => {
    if (web3Modal) {
      const provider = await web3Modal.connect()
      await defaultEvmStores.setProvider(provider)
    }
  }

  // Update app "provider" state when user changes wallet or network
  $: if (abi && $connected && $signerAddress) {
    updateContractVars()
  }

  let coin
  let status
  let heads
  let tails

  let headsCount = 0
  let tailsCount = 0

  let coinClass = ""

  let flipping = false
  let lastResult = "heads"

  // Update the balance based on the result of the last flip
  function processResult(result, prediction) {
    if (result === "heads") {
      headsCount++
      heads.innerText = headsCount
    } else {
      tailsCount++
      tails.innerText = tailsCount
    }
    // Check if prediction is correct and update balance
    if (result === prediction) {
      balance += 1
    } else {
      balance -= 1
    }
    localStorage.setItem("balance", String(balance))
    lastResult = result
  }

  // Flips the coin, awaits the real-time result from Randomizer's Sequencer, and then processes it
  const flipCoin = async (prediction) => {
    if (!flipping) {
      try {
        const tx = await $contracts.coinflip.flip(prediction, { gasLimit: 2000000 })
        toast.push("Sending transaction")
        tx.wait().then((receipt) => {
          toast.push("Transaction confirmed")
        })

        flipping = true
        if (lastResult === "tails") coinClass = "animate-from-tails"
        else coinClass = "animate"

        const receipt = await tx.wait()
        const requestId = parseInt(
          receipt.events.find((e) => e.address == import.meta.env["VITE_CONTRACT_RANDOMIZER"]).topics[1]
        )

        // for (const event of receipt.events) {
        //   if (event.address === import.meta.env["VITE_CONTRACT_RANDOMIZER"]) {
        //     // Convert event.args[0] hex to number
        //     requestId = parseInt(event.topics[1])
        //   }
        // }
        const random = await listenForPreview(requestId, Number($chainId))
        toast.push("Real-time result received", {
          theme: {
            "--toastBackground": "#48BB78",
            "--toastBarBackground": "#2F855A",
          },
        })
        // Convert random hex to BigNumber
        const randomSeed = ethers.BigNumber.from(random).toString()
        console.log("random", random)
        const result = (await $contracts.coinflip.previewResult(random)) ? "tails" : "heads"
        const predictionString = prediction ? "tails" : "heads"
        results[requestId] = {
          prediction: predictionString,
          previewSeed: randomSeed,
          result: result,
        }

        // Store results in localStorage
        localStorage.setItem("results." + $chainId, JSON.stringify(results))

        console.log("result", result)

        processResult(result, predictionString)
        flipping = false
        setTimeout(() => {
          coinClass = "end-" + result
          // coinClass = ""
        }, 100)
      } catch (e) {
        console.error(e)
        toast.push("Network RPC error. Try again.", {
          theme: {
            "--toastBackground": "#F56565",
            "--toastBarBackground": "#C53030",
          },
        })
        flipping = false
        coinClass = ""
      }
    }
  }
</script>

<SvelteToast />

<main>
  {#if error}
    <div class="error">
      {error}
    </div>
  {:else}
    <div class="container">
      <p>Coinflip with randomizer on Arbitrum Nitro Testnet</p>

      <p style="margin:-10px; font-size:0.8em;">{$signerAddress ? $signerAddress : ""}</p>

      <p style=" font-size:0.8em; margin-bottom: -20px;">
        <a
          href="https://twitter.com/intent/tweet?text=ok%20I%20need%20@arbitrum%20to%20give%20me%20Nitro%20testnet%20gas.%20like%20VERY%20SOON.%20I%20cant%20take%20this,%20I%E2%80%99ve%20been%20waiting%20for%20@nitro_devnet%20release.%20I%20just%20want%20to%20start%20developing.%20but%20I%20need%20the%20gas%20IN%20MY%20WALLET%20NOW.%20can%20devs%20DO%20SOMETHING??%20%20SEND%20HERE:%200xAddA0B73Fe69a6E3e7c1072Bb9523105753e08f8"
          style="color: #b7c6cc;">Request testnet ETH</a
        >
      </p>

      <!-- The flippable coin -->
      <div id="coin" bind:this={coin} class={coinClass}>
        <div id="heads" class="heads" />
        <div id="tails" class="tails" />
      </div>

      <!-- Buttons -->
      <div style="display: flex; justify-content: space-between;">
        <button id="flip" on:click={() => flipCoin(false)} style="margin: 6px;">Heads</button>
        <button id="flip" on:click={() => flipCoin(true)} style="margin: 6px;;">Tails</button>
        <div id="status" bind:this={status} />
      </div>

      <!-- Game data -->
      <p>Balance: {balance}</p>
      <p>Heads: <span id="headsCount" bind:this={heads}>0</span> Tails: <span id="tailsCount" bind:this={tails}>0</span></p>
      <p><span bind:this={status} id="status" /></p>
    </div>

    <!-- Show 5 most recent games -->
    <div>
      <h2 style="margin-bottom: 20px; text-align: left; margin-left: 5px;">Recent games</h2>
      <table>
        <thead>
          <tr>
            <th>#</th>
            <th>Win</th>
            <th>Preview Seed</th>
            <th>On-chain Seed</th>
            <th>Match</th>
          </tr>
        </thead>
        <tbody>
          {#each displayedResults as result, i}
            {#if result && Object.keys(result).length}
              <tr>
                <td>{results.indexOf(result)}</td>
                <td>{result.prediction == result.result ? "🥇" : "💩"}</td>
                <td>{result.previewSeed ? "..." + String(result.previewSeed).substr(-5) : ""}</td>
                <td>{result.realSeed ? "..." + String(result.realSeed).substr(-5) : "⏱"}</td>
                {#if result.previewSeed && result.realSeed}
                  <td>{result.previewSeed === result.realSeed ? "✅" : "❌"}</td>
                {:else if result.previewSeed}
                  <td>🔍</td>
                {:else if result.realSeed}
                  <td>📜</td>
                {/if}
              </tr>
            {/if}
          {/each}
        </tbody>
      </table>
      <p>
        <small
          >Preview seed is sent by randomizer's sequencer to the player when the result is determined for instant feedback.</small
        >
      </p>
    </div>
  {/if}
</main>

<style>
  h2 {
    margin: 0.25rem;
  }

  div.container {
    margin: auto;
    display: flex;
    flex-direction: column;
    align-items: center;
  }

  button {
    padding: 1rem;
    background-color: #4685f9;
  }

  #coin {
    position: relative;
    width: 15rem;
    height: 15rem;
    margin: 2rem 0rem;
    transform-style: preserve-3d;
  }

  #coin div {
    width: 100%;
    height: 100%;
    border: 2px solid black;
    border-radius: 50%;
    backface-visibility: hidden;
    background-size: contain;
    position: absolute;
  }

  .heads {
    background-image: url("/heads.png");
    background-repeat: no-repeat;
    background-size: 1000px 1000px;
  }

  .animate {
    animation: flipHeads 0.5s linear infinite;
    animation-fill-mode: forwards;
  }

  .animate-from-tails {
    animation: flipFromTails 0.5s linear infinite;
    animation-fill-mode: forwards;
  }

  .end-heads {
    animation: flipHeads 0.5s;
    animation-fill-mode: forwards;
  }

  .end-tails {
    animation: flipTails 0.5s;
    animation-fill-mode: forwards;
  }

  .end-heads-from-tails {
    animation: flipFromTails 0.5s;
    animation-fill-mode: forwards;
  }

  .end-tails-from-tails {
    animation: flipFromTails 0.5s;
    animation-fill-mode: forwards;
  }

  @keyframes flipHeads {
    from {
      transform: rotateY(0deg);
    }
    to {
      transform: rotateY(360deg);
    }
  }

  @keyframes flipTails {
    from {
      transform: rotateY(0deg);
    }
    to {
      transform: rotateY(180deg);
    }
  }

  @keyframes flipFromTails {
    from {
      transform: rotateY(180deg);
    }
    to {
      transform: rotateY(540deg);
    }
  }

  .tails {
    background-image: url("/tails.jpg");
    background-repeat: no-repeat;
    background-position: center;
    background-size: 300%;
    transform: rotateY(-180deg);
  }

  /* Make table look nice with space */
  table {
    border-collapse: collapse;
    width: 100%;
  }
</style>
