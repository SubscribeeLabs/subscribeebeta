// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./SubscribeeV1.sol";

contract BeehiveV1 is Ownable {

  mapping(string => contractInfo) public slugs;
  uint256 public Adminfund;
  uint256 public Deployfee;
  uint256 public Slugfee;
  bool public Frozen = false;

  event NewContract(
    address newSubscribeeContract,
    uint timeDeployed
  );

  event slugChanged(
    address contractAddress,
    uint timeDeployed,
    string oldSlug,
    string newSlug
  );

  struct contractInfo {
    address contractAddress;
    uint timeDeployed;
  }

  constructor(uint fee, uint slugfee){
    Deployfee = fee;
    Slugfee = slugfee;
  }

  function toggleFreeze() external onlyOwner{
    if(Frozen == false){
      Frozen = true;
    }else{
      Frozen = false;
    }
  }

  function setDeployFee(uint deployfee, uint slugfee) external onlyOwner{
    Deployfee = deployfee;
    Slugfee = slugfee;
  }

  function getDeployFeeFunds(address toAddress) external onlyOwner{
    payable(toAddress).transfer(Adminfund);
    Adminfund = 0;
  }

  function getERC20Funds(address toAddress, address tokenAddress) external onlyOwner {
    IERC20 token = IERC20(tokenAddress);
    uint256 tokenAmount = token.balanceOf(address(this));
    token.transferFrom(address(this), toAddress, tokenAmount);
  }


  function changeSlug(string memory oldslug, string memory newslug) external payable{
    Subscribee subscribeeContract = Subscribee(slugs[oldslug].contractAddress);
    uint timeCreated = slugs[oldslug].timeDeployed;
    require(!Frozen, 'Beehive is currently frozen...');
    require(subscribeeContract.owner() == msg.sender, 'Only the Owner of the contract can do this');
    require(slugs[newslug].contractAddress == address(0), 'Slug has been taken');
    require(msg.value == Slugfee, 'Please pay the appropiate amount...');

    Adminfund += msg.value;
    slugs[newslug] = contractInfo(slugs[oldslug].contractAddress, timeCreated);
    emit slugChanged(slugs[oldslug].contractAddress, timeCreated, oldslug, newslug);
    delete slugs[oldslug];
  }


  function deploySubscribeeContract(address operatorAddress, string memory title, string memory slug, string memory image) external payable{
    require(slugs[slug].contractAddress == address(0), 'Slug has been taken');
    require(!Frozen, 'Beehive is currently frozen...');
    require(msg.value == Deployfee, 'Please pay the appropiate amount...');

    Adminfund += msg.value;

    Subscribee subscribeeContract = new Subscribee(address(this), operatorAddress, title, slug, image);
    subscribeeContract.transferOwnership(msg.sender);

    address subscribeeContractAddress = address(subscribeeContract);
    slugs[slug] = contractInfo(subscribeeContractAddress, block.timestamp);

    emit NewContract(subscribeeContractAddress, block.timestamp);
    return;
  }



}
