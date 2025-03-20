### [H-#] Can Stole tokens by calling deposit instead of repay or direct transfer when flash loaninng

**Description:**

**Impact:**

**Proof of Concept:**

**Recommended Mitigation:**

################

### [H-#] Erorneous function `ThunderLoan::deposit` has `updateExchangeRate` function call which blocks redeem function and protocol thinks it has more funds that it is and update exchange rate to wrong value

**Description:**
updateExchangerate called by not fees collected
**Impact:**

1. block reddem
2. incorrect rate
   **Proof of Concept:**

```solidity
    function testRedeemAfterFlashLoan() public setAllowedToken hasDeposits {
        uint256 amountToBorrow = AMOUNT * 10;
        uint256 calculatedFee = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);

        vm.startPrank(user);
        tokenA.mint(address(mockFlashLoanReceiver), AMOUNT);
        thunderLoan.flashloan(address(mockFlashLoanReceiver), tokenA, amountToBorrow, "");
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        uint256 redeemAmountByLiq = type(uint256).max;
        thunderLoan.redeem(tokenA, redeemAmountByLiq);
        // redeem amount 1003300900000000000000 1003e18
        // deposited amount  //1000e18
        //fee 0.3e18
        //amount expected to reddem => 1000.3e18; but get 1003e18
        vm.stopPrank();
    }
```

**Recommended Mitigation:**

```diff

 function deposit(IERC20 token, uint256 amount) external revertIfZero(amount) revertIfNotAllowedToken(token) {
        AssetToken assetToken = s_tokenToAssetToken[token];
        uint256 exchangeRate = assetToken.getExchangeRate();
        uint256 mintAmount = (amount * assetToken.EXCHANGE_RATE_PRECISION()) / exchangeRate;
        emit Deposit(msg.sender, token, amount);
        assetToken.mint(msg.sender, mintAmount);
-         uint256 calculatedFee = getCalculatedFee(token, amount);
        // @audit-high shouldnt updateRate here
-  assetToken.updateExchangeRate(calculatedFee);
        // e underlying tokens are transferd to assettoken contract
        token.safeTransferFrom(msg.sender, address(assetToken), amount);
    }
```
