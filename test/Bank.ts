import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
import { viem } from "hardhat";
import { expect } from "chai";
import { parseEther } from "viem";

describe("Bank", async function () {
  async function deploy() {
    const [owner, user] = await viem.getWalletClients();
    const bank = await viem.deployContract("Bank", []);
    const publicClient = await viem.getPublicClient();
    return {
      bank,
      owner,
      user,
      publicClient,
    };
  }

  describe("Deployment", () => {
    it("should set right owner", async () => {
      const { bank, owner } = await loadFixture(deploy)
      const bankOwner = await bank.read.owner()
      expect(bankOwner.toLowerCase()).to.equal(owner.account.address)
    })

    it('should have lock period 7 days', async () => {
      const { bank } = await loadFixture(deploy);
      const lockPeriod = await bank.read.lockPeriod()
      expect(lockPeriod).to.eq(7 * 24 * 60 * 60)
    })

    it('should have penalty percentage 10', async () => {
      const { bank } = await loadFixture(deploy);
      const penaltyPercentage = await bank.read.penaltyPercentage()
      expect(penaltyPercentage).to.eq(10)
    })
  })

  describe('Deposit', async () => {

    it('should have right balance amount after deposit', async () => {
      const { bank, user, publicClient } = await loadFixture(deploy);
      const depositAmount = parseEther('0.5')
      const depositHash = await user.sendTransaction({
        to: bank.address,
        value: depositAmount
      })
      await publicClient.waitForTransactionReceipt({ hash: depositHash })
      const [balanceAmount] = await bank.read.getBalance([user.account.address])
      expect(balanceAmount).to.equal(depositAmount)
    })

    it('should have right balance amount after withdrawal', async () => {
      const { bank, user, publicClient } = await loadFixture(deploy);
      const withdrawAmount = parseEther('0.3')
      const expectBalance = parseEther('0.2')
      await bank.write.withdraw([withdrawAmount], { account: user.account })
      const [balanceAmount] = await bank.read.getBalance([user.account.address])
      expect(balanceAmount).to.equal(expectBalance)
    })
  })
})