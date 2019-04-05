pragma solidity ^0.4.25;

/*
Defines the storage layout of the token implementaiton contract. Any newly declared
state variables in future upgrades should be appened to the bottom. Never remove state variables
from this list
 */
contract ProxyStorage {
    
    struct stakingInfo {
        uint amount;
        bool requested;
        uint releaseDate;
    }    

    address public owner;
    address public pendingOwner;

    bool initialized;
    
        //allowed token addresses
    mapping (address => bool) public allowedTokens;
    

    mapping (address => mapping(address => stakingInfo)) public StakeMap; //tokenAddr to user to stake amount
    mapping (address => mapping(address => uint)) public userCummRewardPerStake; //tokenAddr to user to remaining claimable amount per stake
    mapping (address => uint) public tokenCummRewardPerStake; //tokenAddr to cummulative per token reward since the beginning or time
    mapping (address => uint) public tokenTotalStaked; //tokenAddr to total token claimed 
    
    mapping (address => address) public Mediator;

    address public StakeTokenAddr;

}
