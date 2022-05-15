// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./dependencies/MintableERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";

contract HoneyJar is ERC20Capped, ERC20Mintable, ERC20Burnable, Ownable {

    mapping (address => bool) approvedPool;
    uint256 public liquidateFee;
    bool public ableToLiquidate;

    event liquidation(
      address user,
      uint amountOfHTOKBurned,
      string tokenGiven,
      uint amountOfToken,
      uint time
    );

    constructor (string memory name, string memory symbol, uint256 cap, uint256 initialBalance, uint256 fee) ERC20(name, symbol) ERC20Capped(cap) {
        _mint(_msgSender(), initialBalance);
        liquidateFee = fee; //amount to divide by
    }

    function tokenBalance(address tokenAddress) public view returns (uint256) {
        ERC20 token = ERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    function liquidateTokens(address poolAddress, uint256 amount) public{
      require(approvedPool[poolAddress] == true, 'Must be Approved Pool!');
      require(ableToLiquidate, 'Liquidation Feature Currently Shutdown');
      require(balanceOf(msg.sender) >= amount, 'you must have enough HTOK to redeem for tokens');

      IUniswapV2Pair pair = IUniswapV2Pair(poolAddress);
      ERC20 tokenToCollect = ERC20(pair.token1());
      ( uint HTKReserves, uint tokenReserves, ) = pair.getReserves();
      uint amountOfToken = ( amount * tokenReserves ) / HTKReserves; // return amount of token1 needed to buy HTK

      require(tokenToCollect.balanceOf(address(this)) >= amountOfToken);


      uint fee = amountOfToken / liquidateFee;
      burn(amount);
      tokenToCollect.transferFrom(address(this), msg.sender, amountOfToken - fee);

      emit liquidation(msg.sender, amount, tokenToCollect.name(), amountOfToken - fee, block.timestamp);
    }

    function enableLiquidateFunction() external onlyOwner{
      if(ableToLiquidate){
        ableToLiquidate = false;
      }else{
        ableToLiquidate = true;
      }
    }

    function setLiquidateFee(uint newfee) external onlyOwner{
      liquidateFee = newfee;
    }

    function setPool(address poolAddress) external onlyOwner{
      if(approvedPool[poolAddress]){
        delete approvedPool[poolAddress];
      }else{
        approvedPool[poolAddress] = true;
      }
    }

    function _mint(address account, uint256 amount) internal override(ERC20, ERC20Capped) onlyOwner {
        super._mint(account, amount);
    }

    function _finishMinting() internal override onlyOwner {
        super._finishMinting();
    }
}
