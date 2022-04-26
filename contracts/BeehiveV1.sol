// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SubscribeeV1.sol";

contract BeehiveV1 is Ownable {

  mapping(string => address) public slugs;
  mapping(address => string) public slugLookup;
  uint256 public adminFund;
  uint256 public deployFee;
  uint256 public slugFee;

  event NewContract(
    address contractAddress,
    string slug,
    uint time
  );

  event slugChanged(
    address contractAddress,
    string oldSlug,
    string newSlug
  );

  constructor(uint fee, uint slugfee){
    deployFee = fee;
    slugFee = slugfee;
  }

  function setFees(uint deployfee, uint slugfee) external onlyOwner{
    deployFee = deployfee;
    slugFee = slugfee;
  }

  function getFunds(address toAddress) external onlyOwner{
    payable(toAddress).transfer(adminFund);
    adminFund = 0;
  }

  function getTokenFunds(address toAddress, address tokenAddress) external onlyOwner {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenAmount = token.balanceOf(address(this));
    token.transferFrom(address(this), toAddress, tokenAmount);
  }


  function changeSlug(string memory oldslug, string memory newslug) external payable{
    SubscribeeV1 subscribeeContract = SubscribeeV1(slugs[oldslug]);
    require(subscribeeContract.owner() == msg.sender, 'Only the Owner of the contract can do this');
    require(slugs[newslug] == address(0), 'Slug has been taken');
    require(msg.value == slugFee || msg.sender == owner(), 'Please pay the appropiate amount...');

    adminFund += msg.value;
    slugs[newslug] = slugs[oldslug];
    slugLookup[slugs[oldslug]] = newslug;
    emit slugChanged(slugs[oldslug], oldslug, newslug);
    delete slugs[oldslug];
  }


  function deploySubscribeeContract(address operatorAddress, string memory title, string memory slug, string memory image) external payable{
    require(slugs[slug] == address(0), 'Slug has been taken');
    require(msg.value == deployFee || msg.sender == owner(), 'Please pay the appropiate amount...');

    adminFund += msg.value;

    SubscribeeV1 newContract = new SubscribeeV1(address(this), operatorAddress, title, image);
    newContract.transferOwnership(msg.sender);

    address contractAddress = address(newContract);
    slugs[slug] = contractAddress;
    slugLookup[contractAddress] = slug;

    emit NewContract(contractAddress, slug, block.timestamp);
  }



}
