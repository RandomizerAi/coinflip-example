const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CoinFlip", function () {
  let CoinFlip, coinFlip, Randomizer, randomizer, owner, addr1, addr2;

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    CoinFlip = await ethers.getContractFactory("CoinFlip");

    [owner, addr1, addr2, randomizer] = await ethers.getSigners();

    // Deploy Randomizer contract
    Randomizer = await ethers.getContractFactory("DummyRandomizer");
    randomizer = await Randomizer.deploy();

    // Deploy CoinFlip contract
    coinFlip = await CoinFlip.deploy(randomizer.address);
    await coinFlip.deployed();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await coinFlip.owner()).to.equal(owner.address);
    });
  });

  describe("Flip", function () {
    it("Should emit a Flip event", async function () {
      const transaction = await coinFlip
        .connect(addr1)
        .flip(true, { value: ethers.utils.parseEther("1") });
      const receipt = await transaction.wait();
      const event = receipt.events.find((event) => event.event === "Flip");
      expect(event.args[0]).to.equal(addr1.address);
    });

    it("Should refund the player if the fee paid is less than the deposit", async function () {
      this.timeout(10000);
      const flipOne = await coinFlip
        .connect(addr1)
        .flip(true, { value: ethers.utils.parseEther("1") });
      const receiptOne = await flipOne.wait();
      // Get the Flip event from flipOne and assign the first argument as flipId
      const flipId = receiptOne.events.find((event) => event.event === "Flip")
        .args[1];

      // Callback the flip
      const callbackTx = await randomizer
        .connect(owner)
        .submitRandom(flipId, ethers.utils.randomBytes(32));

      const callbackReceipt = await callbackTx.wait();

      // Parse the first event with the coinFlip contract interface
      const callbackEvent = coinFlip.interface.parseLog(
        callbackReceipt.events[0]
      );

      // Check callbackReceipt for FlipResult event
      expect(ethers.BigNumber.from(callbackEvent.args.id).eq(flipId)).to.be
        .true;

      // Flip again
      await coinFlip
        .connect(addr1)
        .flip(true, { value: ethers.utils.parseEther("1") });
      const callbackTx2 = await randomizer
        .connect(owner)
        .submitRandom(flipId, ethers.utils.randomBytes(32));
      const callbackReceipt2 = await callbackTx2.wait();

      // parseLog all events where address matches coinFlip address
      const callbackEvents = callbackReceipt2.events
        .filter((event) => event.address === coinFlip.address)
        .map((event) => coinFlip.interface.parseLog(event));

      // callbackEvent2 should be the Refund event, find it by name
      const callbackEvent2 = callbackEvents.find(
        (event) => event.name === "Refund"
      );

      // The second flip should have refunded excess fees of the first flip
      expect(callbackEvent2.name).to.eq("Refund");
      expect(callbackEvent2.args.player).to.equal(addr1.address);
      expect(ethers.BigNumber.from(callbackEvent2.args.amount).gt(0)).to.be
        .true;
      expect(
        ethers.BigNumber.from(callbackEvent2.args.amount).lt(
          ethers.utils.parseEther("1")
        )
      ).to.be.true;
      expect(
        ethers.BigNumber.from(callbackEvent2.args.refundedGame).toString()
      ).eq("1");
    });
  });
});
