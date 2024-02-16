import { formatEther, parseEther, parseGwei } from "viem";
import { viem } from "hardhat";

async function main() {
  const [bobWalletClient, aliceWalletClient] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();
  const bobBalance = await publicClient.getBalance({
    address: bobWalletClient.account.address,
  });

  console.log(
    `Balance of ${bobWalletClient.account.address}: ${formatEther(
      bobBalance
    )} ETH`
  );

  const bank = await viem.deployContract("Bank", []);
  const hash = await bobWalletClient.sendTransaction({
    to: bank.address,
    value: parseEther('0.1')
  })
  await publicClient.waitForTransactionReceipt({ hash })
  const balance = await bank.read.getBalance([bobWalletClient.account.address])

  console.log('Balance', balance)
  console.log(
    `Bank deployed to ${bank.address}`,
    // `RPC deployed to ${rps.address}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
