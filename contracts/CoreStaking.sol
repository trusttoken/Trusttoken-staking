pragma solidity ^0.4.25;

import "./Utils/IERC20.sol";
import "./Utils/SafeMath.sol";
import "./Utils/HasOwner.sol";

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
