// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SubscribeeV1.sol";

contract BeehiveV1 is Ownable {

  mapping(string => address) public slugs;
  mapping(address => bool) public verifiedSubscribeeContract;

  address public honeyPot;
  uint256 public adminFund;
  uint256 public deployFee;
  uint256 public slugFee;

  event NewContract(
    address contractAddress,
    string slug,
    uint256 time
  );

  event slugChanged(
    address contractAddress,
    string oldSlug,
    string newSlug
  );

  event honeySent(
    string token,
    uint256 tokenAmount,
    uint256 time
  );

  event adminFundsCollected(
    address toAddress,
    uint256 amount,
    uint256 time
  );

  constructor(address honeyPotAddress, uint256 fee, uint256 slugfee){
    honeyPot = honeyPotAddress;
    deployFee = fee;
    slugFee = slugfee;
  }

  function harvestHoney(address tokenAddress) external {
    IERC20Metadata token = IERC20Metadata(tokenAddress);
    uint256 honey = token.balanceOf(address(this));
    token.transferFrom(address(this), honeyPot, honey);
    emit honeySent(token.name(), honey, block.timestamp);
  }

  function setAdminFees(uint256 deployfee, uint256 slugfee) external onlyOwner{
    deployFee = deployfee;
    slugFee = slugfee;
  }

  function collectAdminFees(address toAddress) external onlyOwner{
    payable(toAddress).transfer(adminFund);
    emit adminFundsCollected(toAddress, adminFund, block.timestamp);
    adminFund = 0;
  }


  function changeSlug(string memory oldslug, string memory newslug) external payable{
    SubscribeeV1 subscribeeContract = SubscribeeV1(slugs[oldslug]);
    require(subscribeeContract.owner() == msg.sender, 'Only the Owner of the contract can do this');
    require(slugs[newslug] == address(0), 'Slug has been taken');
    require(msg.value == slugFee || msg.sender == owner(), 'Please pay the appropiate amount...');

    adminFund += msg.value;
    slugs[newslug] = slugs[oldslug];
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
    verifiedSubscribeeContract[contractAddress] = true;

    emit NewContract(contractAddress, slug, block.timestamp);
  }



}
