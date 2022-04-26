// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SubscribeeV1 is Ownable{

  uint8 public nextPlanId;
  string public title;
  string public image;

  mapping(uint8 => address[]) private subscriberLists;
  mapping(uint8 => Plan) public plans;
  mapping(uint8 => mapping(address => Subscription)) public subscriptions;

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
    uint userId;
  }

  struct UserObject {
    address subscriber;
    uint8 planId;
  }


  // Events


  event PlanCreated(
    string title,
    address token,
    uint128 amount,
    uint128 frequency
  );

  event SubscriptionCreated(
    address subscriber,
    uint8 planId,
    uint date
  );

  event SubscriptionDeleted(
    address subscriber,
    uint8 planId,
    uint date,
    string reason
  );

  event PaymentSent(
    address from,
    address to,
    uint128 amount,
    uint8 planId,
    uint date
  );

  // Modifiers

  modifier onlyOperatorOrOwner() {
    require(msg.sender == operator || msg.sender == owner(), 'Huh?');
    _;
  }

  // Constructor

  constructor(address beehiveAddress, address operatorAddress, string memory newTitle, string memory newImage) {
    beehive = beehiveAddress;
    operator = operatorAddress;
    title = newTitle;
    image = newImage;
  }


  // External Functions

  function subscribe(uint8 planId) external {
    _safeSubscribe(planId);
  }

  function stopPay(uint8 planId) external {
    _stop(planId);
  }

  function selfDelete(uint8 planId) external {
    _delete(msg.sender, planId, 'User Deleting Subscription');
  }

  function selfPay(uint8 planId) external {
    _safePay(msg.sender, planId);
  }

  function setOperator(address newOperator) external onlyOwner{
    operator = newOperator;
  }

  function setTitle(string memory newTitle) external onlyOwner{
    title = newTitle;
  }

  function setImage(string memory newImage) external onlyOwner{
    image = newImage;
  }

  function togglePlanHalt(uint8 planId) external onlyOwner{
    if(plans[planId].halted == true){
      plans[planId].halted = false;
    }else{
      plans[planId].halted = true;
    }
  }

  function createPlan(string memory planTitle, address merchant, address token, uint128 amount, uint128 frequency) external onlyOwner{
    require(token != address(0), 'address cannot be null address');
    require(amount > 0, 'amount needs to be > 0');
    require(frequency > 86400, 'frequency needs to be greater then 24 hours');

    plans[nextPlanId] = Plan(
      planTitle,
      merchant,
      token,
      amount,
      frequency,
      false
    );

    emit PlanCreated(title, token, amount, frequency);
    nextPlanId++;
  }

  function changePlanMerchant(uint8 planId, address merchant) external onlyOwner{
    Plan storage plan = plans[planId];
    plan.merchant = merchant;
  }

  function getSubscriberArray(uint8 planId) external view onlyOperatorOrOwner returns(address[] memory){
    return subscriberLists[planId];
  }

  function multiPay(UserObject[] memory users) external onlyOperatorOrOwner{
    for(uint i = 0; i < users.length; i++){
      address subscriber = users[i].subscriber;
      uint8 planId = users[i].planId;
      _safePay(subscriber, planId);
    }
  }

  function multiDelete(UserObject[] memory users) external onlyOperatorOrOwner{
    for(uint i = 0; i < users.length; i++){
      address subscriber = users[i].subscriber;
      uint8 planId = users[i].planId;
      _delete(subscriber, planId, 'Owner/Operator Deleted Subscription');
    }
  }

  // Private Functions

  function _safePay(address subscriber, uint8 planId) private {
    // call from storage
    Subscription storage subscription = subscriptions[planId][subscriber];
    Plan storage plan = plans[planId];
    IERC20 token = IERC20(plan.token);
    uint pollenFee = plan.amount / 50;

    // conditionals
    require(
       subscription.start != 0,
      'this subscription does not exist'
    );

    require(
      block.timestamp > subscription.nextPayment,
      'not due yet'
    );

    require(
      !plan.halted,
      'Plan is halted'
    );

    require(
      !subscription.stopped,
      'Subscriber opted to stop payments; delete subscription'
    );

    require(
      token.balanceOf(subscriber) >= plan.amount,
      'Subscriber has insufficent funds; delete subscription'
    );

    // send to Contract Owner & BeeHive
    token.transferFrom(subscriber, plan.merchant, plan.amount - pollenFee);
    token.transferFrom(subscriber, beehive, pollenFee);

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

  function _safeSubscribe(uint8 planId) private {
    // calls plan from storage and check if it exists
    Plan storage plan = plans[planId];
    require(plan.merchant != address(0), 'this plan does not exist');
    require(!plan.halted, 'plan is halted');

    // set token and fee
    IERC20 token = IERC20(plans[planId].token);
    uint pollenFee = plan.amount / 50;

    // send to Contract Owner & BeeHive
    token.transferFrom(msg.sender, plan.merchant, plan.amount - pollenFee);
    token.transferFrom(msg.sender, beehive, pollenFee);

    subscriberLists[planId].push(msg.sender);

    // add new subscription
    subscriptions[planId][msg.sender] = Subscription(
      block.timestamp,
      block.timestamp + plan.frequency,
      false,
      subscriberLists[planId].length - 1
    );

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

  function _delete(address user, uint8 planId, string memory reason) private {
    // Grab user subscription data & check if it exists
    Subscription storage subscription = subscriptions[planId][user];
    require(subscription.start != 0, 'this subscription does not exist');

    // delete from array
    address[] storage subscriberArray = subscriberLists[planId];
    uint userCount = subscription.userId;
    address addressToChange  = subscriberArray[subscriberArray.length - 1];
    subscriberArray[userCount] = addressToChange;
    subscriptions[planId][addressToChange].userId = userCount;
    subscriberArray.pop();

    // delete from mapping
    delete subscriptions[planId][user];

    emit SubscriptionDeleted(user, planId, block.timestamp, reason);
  }

  function _stop(uint8 planId) private {
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
