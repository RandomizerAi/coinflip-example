// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// You can also run a script with `npx hardhat run <script>`. If you do that, Hardhat
// will compile your contracts, add the Hardhat Runtime Environment's members to the
// global scope, and execute the script.
require("dotenv").config();
const hre = require("hardhat");

async function main() {
  const randomizer = await hre.ethers.getContractAt("IRandomizerDeposit", process.env.RANDOMIZER_ADDRESS);

  const deposit = await randomizer.clientDeposit(process.env.COINFLIP_ADDRESS, { value: ethers.utils.parseEther("0.2") });
  await deposit.wait();
  console.log("deposited");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
