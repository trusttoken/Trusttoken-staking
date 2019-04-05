pragma solidity ^0.4.25;

// File: contracts/Utils/IERC20.sol

/**
 * @title ERC20 interface
 * @dev see https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: contracts/Utils/SafeMath.sol

/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error.
 */
library SafeMath {
    /**
     * @dev Multiplies two unsigned integers, reverts on overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b);

        return c;
    }

    /**
     * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Adds two unsigned integers, reverts on overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);

        return c;
    }

    /**
     * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
     * reverts when dividing by zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
    }
}

// File: contracts/Utils/ProxyStorage.sol

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

// File: contracts/Utils/HasOwner.sol

/**
 * @title HasOwner
 * @dev The HasOwner contract is a copy of Claimable Contract by Zeppelin. 
 and provides basic authorization control functions. Inherits storage layout of 
 ProxyStorage.
 */
contract HasOwner is ProxyStorage {

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
    * @dev sets the original `owner` of the contract to the sender
    * at construction. Must then be reinitialized 
    */
    constructor() public {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    /**
    * @dev Throws if called by any account other than the owner.
    */
    modifier onlyOwner() {
        require(msg.sender == owner, "only Owner");
        _;
    }

    /**
    * @dev Modifier throws if called by any account other than the pendingOwner.
    */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner);
        _;
    }

    /**
    * @dev Allows the current owner to set the pendingOwner address.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    /**
    * @dev Allows the pendingOwner address to finalize the transfer.
    */
    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}

// File: contracts/CoreStaking.sol

contract TrusttokenStaking is HasOwner {
    using SafeMath for uint;
    
    uint BIGNUMBER = 10**18;
    uint DECIMAL = 10**3;
    

    modifier isValidToken(address _tokenAddr){
        require(allowedTokens[_tokenAddr]);
        _;
    }

    modifier isMediator(address _tokenAddr){
        require(Mediator[_tokenAddr] == msg.sender);
        _;
    }
    
    function initialize(address _tokenAddr) public {
        require(!initialized, "Already initialized");
        StakeTokenAddr = _tokenAddr;
        owner = msg.sender;
        initialized = true;
    }
    
    event Claimed(uint indexed amount, address indexed receiver);
    event TokenAdded(address token);
    event TokenRemoved(address token);
    
    /**
    * @dev add approved token address to the mapping 
    */
    
    function addToken(address _tokenAddr) external onlyOwner {
        allowedTokens[_tokenAddr] = true;
        emit TokenAdded(_tokenAddr);
    }
    
    /**
    * @dev remove approved token address from the mapping 
    */
    function removeToken(address _tokenAddr) external onlyOwner {
        allowedTokens[_tokenAddr] = false;
        emit TokenRemoved(_tokenAddr);
    }

    /**
    * @dev stake a specific amount to a token
    * @param _amount the amount to be staked
    * @param _tokenAddr the token the user wish to stake on
    */
    
    function stake(uint _amount, address _tokenAddr) external isValidToken(_tokenAddr) returns (bool) {
        require(_amount != 0);
        require(IERC20(StakeTokenAddr).transferFrom(msg.sender, this, _amount));
        
        if (StakeMap[_tokenAddr][msg.sender].amount == 0){
            StakeMap[_tokenAddr][msg.sender].amount = _amount;
            userCummRewardPerStake[_tokenAddr][msg.sender] = tokenCummRewardPerStake[_tokenAddr];
        } else {
            claim(_tokenAddr, msg.sender);
            StakeMap[_tokenAddr][msg.sender].amount = StakeMap[_tokenAddr][msg.sender].amount.add(_amount);
        }
        tokenTotalStaked[_tokenAddr] = tokenTotalStaked[_tokenAddr].add(_amount);
        return true;
    }
    
    
    /**
    * @dev pay out dividends to stakers, update how much per token each staker can claim
    * @param _reward the aggregate amount to be send to all stakers
    */
    function distribute(uint _reward, address _tokenAddress) isValidToken(_tokenAddress) external onlyOwner returns (bool){
        require(tokenTotalStaked[msg.sender] != 0);
        uint reward = _reward.mul(BIGNUMBER);
        tokenCummRewardPerStake[_tokenAddress] += reward.div(tokenTotalStaked[_tokenAddress]);
        return true;
    } 
    
    
    /**
    * @dev claim dividends for a particular token that user has stake in
    * @param _tokenAddr the token that the claim is made on
    * @param _receiver the address which the claim is paid to
    */
    function claim(address _tokenAddr, address _receiver) isValidToken(_tokenAddr) public returns (uint) {
        uint stakedAmount = StakeMap[_tokenAddr][msg.sender].amount;
        //the amount per token for this user for this claim
        uint amountOwedPerToken = tokenCummRewardPerStake[_tokenAddr].sub(userCummRewardPerStake[_tokenAddr][msg.sender]);
        uint claimableAmount = stakedAmount.mul(amountOwedPerToken); //total amoun that can be claimed by this user
        claimableAmount = claimableAmount.mul(DECIMAL); //simulate floating point operations
        claimableAmount = claimableAmount.div(BIGNUMBER); //simulate floating point operations
        userCummRewardPerStake[_tokenAddr][msg.sender] = tokenCummRewardPerStake[_tokenAddr];
        if (_receiver == address(0)){
            require(IERC20(_tokenAddr).transfer(msg.sender,claimableAmount));
        }else{
            require(IERC20(_tokenAddr).transfer(_receiver,claimableAmount));
        }
        emit Claimed(claimableAmount, _receiver);
        return claimableAmount;
    }
    
    
    /**
    * @dev request to withdraw stake from a particular token, must wait 4 weeks
    */
    function initWithdraw(address _tokenAddr) isValidToken(_tokenAddr)  external returns (bool){
        require(StakeMap[_tokenAddr][msg.sender].amount >0 );
        require(!StakeMap[_tokenAddr][msg.sender].requested );
        StakeMap[_tokenAddr][msg.sender].releaseDate = now + 4 weeks;
        return true;
    }
    
    
    /**
    * @dev finalize withdraw of stake
    */
    function finalizeWithdraw(uint _amount, address _tokenAddr) isValidToken(_tokenAddr)  external returns(bool){
        require(StakeMap[_tokenAddr][msg.sender].amount >0);
        require(StakeMap[_tokenAddr][msg.sender].requested);
        require(now > StakeMap[_tokenAddr][msg.sender].releaseDate );
        claim(_tokenAddr, msg.sender);
        require(IERC20(_tokenAddr).transfer(msg.sender,_amount));
        tokenTotalStaked[_tokenAddr] = tokenTotalStaked[_tokenAddr].sub(_amount);
        StakeMap[_tokenAddr][msg.sender].requested = false;
        return true;
    }
    
    function releaseStake(address _tokenAddr, address[] _stakers, uint[] _amounts,address _dest) isMediator(_tokenAddr) isValidToken(_tokenAddr) external returns (bool){
        require(_stakers.length == _amounts.length);
        for (uint i =0; i< _stakers.length; i++){
            require(IERC20(_tokenAddr).transfer(_dest,_amounts[i]));
            StakeMap[_tokenAddr][_stakers[i]].amount -= _amounts[i];
        }
        return true;      
    }
}
