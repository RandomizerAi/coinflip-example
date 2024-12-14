// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const CoinFlip = await hre.ethers.getContractFactory("CoinFlip");
  // const coinFlip = await CoinFlip.deploy(process.env.RANDOMIZER_ADDRESS);

  const coinFlip = CoinFlip.attach(process.env.COINFLIP_ADDRESS);

  coinFlip.on("FlipResult", (player, id, seed, prediction, result) => {
    console.log({ player, id, seed, prediction, result });
  });

  await coinFlip.flip(1, { value: ethers.utils.parseEther("0.01") });

  console.log("flipped");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
