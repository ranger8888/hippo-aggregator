# Onchain integration example

This sample here demonstrates how to integrate with hippo-aggregator on-chain

Sample code at end of `src/cli.ts`:

```typescript
const testSwap = async(symbolX: string, symbolY: string, xInAmt: string, targetAddress: string) => {
  const {client, account} = readConfig(program);
  const agg = await TradeAggregator.create(client);
  const xInfo = agg.registryClient.getCoinInfoBySymbol(symbolX);
  const yInfo = agg.registryClient.getCoinInfoBySymbol(symbolY);
  const quote = await agg.getBestQuote(parseFloat(xInAmt), xInfo, yInfo);
  if (!quote) {
    console.log(`No quote from ${symbolX} to ${symbolY}`);
    return;
  }
  const params = quote.route.getSwapParams(parseFloat(xInAmt), 0);
  const payload = buildPayload_swap_and_transfer(
    params.numSteps,
    params.firstDexType,
    params.firstPoolType,
    params.firstIsReversed,
    params.secondDexType,
    params.secondPoolType,
    params.secondIsReversed,
    params.thirdDexType,
    params.thirdPoolType,
    params.thirdIsReversed,
    params.inAmt,
    new HexString(targetAddress),
    params.types
  );

  await sendPayloadTxAndLog(client, account, payload);
}

```
