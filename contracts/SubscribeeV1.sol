// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SubscribeeV1 is Ownable{

  uint64 public nextPlanId;
  bool public suspended = false;
  string public title;
  string public slug;
  string public image;

  mapping(uint64 => address[]) private luSubscriptions;
  mapping(uint64 => Plan) public plans;
  mapping(uint64 => mapping(address => Subscription)) public subscriptions;

  address public beehive;
  address public operator;

  // Structs

  struct Plan {
    string title;
    address merchant;
    address token;
    uint128 amount;
    uint128 frequency;
    bool halted;
  }

  struct Subscription {
    uint start;
    uint nextPayment;
    bool stopped;
  }

  struct UserObject {
    address subscriber;
    uint64 planId;
  }


  // Events


  event PlanCreated(
    address merchant,
    uint64 planId,
    uint date,
    uint64 terms
  );

  event SubscriptionCreated(
    address subscriber,
    uint64 planId,
    uint date
  );

  event SubscriptionDeleted(
    address subscriber,
    uint64 planId,
    uint date,
    string reason
  );

  event PaymentSent(
    address from,
    address to,
    uint128 amount,
    uint64 planId,
    uint date
  );

  // Modifiers

  modifier onlyOperatorOrOwner() {
    require(msg.sender == operator || msg.sender == owner(), 'Huh?');
    _;
  }



  // Constructor

  constructor(address beehiveAddress, address operatorAddress, string memory newTitle, string memory newSlug, string memory newImage) {
    beehive = beehiveAddress;
    operator = operatorAddress;
    slug = newSlug;
    title = newTitle;
    image = newImage;
  }


  // Functions

  function setOperator(address newOperator) external onlyOwner{
    operator = newOperator;
  }

  function toggleSuspend() external onlyOwner{
    if(suspended == true){
      suspended = false;
    }else{
      suspended = true;
    }
  }

  function getSubscriberArray(uint64 planId) external view onlyOperatorOrOwner returns(address[] memory){
    return luSubscriptions[planId];
  }

  function setTitle(string memory newTitle) external onlyOperatorOrOwner{
    title = newTitle;
  }

  function setImage(string memory newImage) external onlyOperatorOrOwner{
    image = newImage;
  }

  function togglePlanHalt(uint64 planId) external onlyOperatorOrOwner{
    if(plans[planId].halted == true){
      plans[planId].halted = false;
    }else{
      plans[planId].halted = true;
    }
  }

  function createPlan(string memory planTitle, address merchant, address token, uint128 amount, uint128 frequency) external onlyOperatorOrOwner{
    require(token != address(0), 'address cannot be null address');
    require(amount > 0, 'amount needs to be > 0');
    require(frequency > 0, 'frequency needs to be greater then 24 hours');

    plans[nextPlanId] = Plan(
      planTitle,
      merchant,
      token,
      amount,
      frequency,
      false
    );
    nextPlanId++;
  }

  function subscribe(uint64 planId) external {
    require(!suspended, 'contract is suspended');
    require(!plans[planId].halted, 'plan is halted');
    _safeSubscribe(planId);
  }

  function stopPay(uint64 planId) external {
    _safeStop(planId);
  }

  function selfDelete(uint64 planId) external {
    _delete(msg.sender, planId, 'User Deleting Subscription');
  }

  function selfPay(uint64 planId) external {
    require(!suspended, 'contract is suspended');
    _safePay(msg.sender, planId);
  }

  function multiPay(UserObject[] memory users) external onlyOperatorOrOwner{
    for(uint i = 0; i < users.length; i++){
      address subscriber = users[i].subscriber;
      uint64 planId = users[i].planId;
      _safePay(subscriber, planId);
    }
  }

  function multiDelete(UserObject[] memory users) external onlyOperatorOrOwner{
    for(uint i = 0; i < users.length; i++){
      address subscriber = users[i].subscriber;
      uint64 planId = users[i].planId;
      _delete(subscriber, planId, 'Owner/Operator Deleted Subscription');
    }
  }

  // Internal Functions


  function _safePay(address subscriber, uint64 planId) internal {
    // call from storage
    Subscription storage subscription = subscriptions[planId][subscriber];
    Plan storage plan = plans[planId];
    IERC20 token = IERC20(plan.token);
    uint PollenFee = plan.amount / 100;

    // conditionals for storage
    require(
       subscriber != address(0),
      'this subscription does not exist'
    );

    require(
      block.timestamp > subscription.nextPayment,
      'not due yet'
    );

    // check for stopped subscription, will delete here due to the previous check of being past the timestamp
    if(subscription.stopped){
      _delete(subscriber, planId, 'past due & stopped, subscription deleted');
      return;
    }

    // Will check if user has funds, if not will delete subscription
    if(token.balanceOf(subscriber) < plan.amount){
      _delete(subscriber, planId, 'insufficent funds, subscription deleted');
      return;
    }

    // send to Contract Owner & BeeHive
    token.transferFrom(subscriber, plan.merchant, plan.amount - PollenFee);
    token.transferFrom(subscriber, beehive, PollenFee);

    // set next payment
    subscription.nextPayment = subscription.nextPayment + plan.frequency;

    // emit event
      emit PaymentSent(
        subscriber,
        plan.merchant,
        plan.amount,
        planId,
        block.timestamp
      );
    }

  function _safeSubscribe(uint64 planId) internal {
    // calls plan from storage and check if it exists
    Plan storage plan = plans[planId];
    require(plan.merchant != address(0), 'this plan does not exist');

    // set token and fee
    IERC20 token = IERC20(plans[planId].token);
    uint PollenFee = plan.amount / 100;

    // send to Contract Owner & BeeHive
    token.transferFrom(msg.sender, plan.merchant, plan.amount - PollenFee);
    token.transferFrom(msg.sender, beehive, PollenFee);

    // add new subscription
    subscriptions[planId][msg.sender] = Subscription(
      block.timestamp,
      block.timestamp + plan.frequency,
      false
    );

    // add user to lookup array
    address[] storage subscriptionUsers = luSubscriptions[planId];
    subscriptionUsers.push(msg.sender);

    // emit Subscription and Payment events
    emit SubscriptionCreated(address(msg.sender), planId, block.timestamp);

    emit PaymentSent(
      msg.sender,
      plan.merchant,
      plan.amount,
      planId,
      block.timestamp
    );

  }

  function _delete(address user, uint64 planId, string memory reason) internal {
    // Grab user subscription data & check if it exists
    Subscription storage subscription = subscriptions[planId][user];
    require(subscription.start != 0, 'this subscription does not exist');

    // delete from mapping
    delete subscriptions[planId][user];

    // delete from arrayLookup
    address[] storage subscriptionUsers = luSubscriptions[planId];
    for(uint i = 0; i < subscriptionUsers.length; i++){
      if(subscriptionUsers[i] == msg.sender){
          delete subscriptionUsers[i];
      }
    }

    emit SubscriptionDeleted(user, planId, block.timestamp, reason);
  }

  function _safeStop(uint64 planId) internal {
    // Grab user subscription data & check if it exists
    Subscription storage subscription = subscriptions[planId][msg.sender];
    require(subscription.start != 0, 'this subscription does not exist');

    // Check if user owes funds and is trying to stop, will delete
    if(subscription.nextPayment < block.timestamp){
      _delete(msg.sender, planId, 'You cannot stop subscription after funds are owed, subscription deleted');
      return;
    }

    // If user does not have to pay yet, stop subscription
    subscription.stopped = true;
  }
}
