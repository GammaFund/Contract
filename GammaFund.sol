pragma solidity ^0.4.8;
/**
 * Overflow aware uint math functions.
 *
 * Inspired by https://github.com/MakerDAO/maker-otc/blob/master/contracts/simple_market.sol
 */
contract SafeMath {
  //internals

  function safeMul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function safeSub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function safeAdd(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c>=a && c>=b);
    return c;
  }

  function assert(bool assertion) internal {
    if (!assertion) throw;
  }
}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract Token {

    /// @return total amount of tokens
    function totalSupply() constant returns (uint256 supply) {}

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance) {}

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success) {}

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {}

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success) {}

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {}

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

}

/**
 * ERC 20 token
 *
 * https://github.com/ethereum/EIPs/issues/20
 */
contract StandardToken is Token {

    /**
     * Reviewed:
     * - Interger overflow = OK, checked
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        //if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    mapping(address => uint256) balances;

    mapping (address => mapping (address => uint256)) allowed;

    uint256 public totalSupply;

}


contract OwnedAccount{
    address public owner;
    bool acceptDeposits = true;
    event PayOut(address msg_sender, uint msg_value, address indexed _recipient, uint _amount);

    modifier noEther() {
        require(msg.value == 0);
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function OwnedAccount(address _owner) {
        owner = _owner;
    }

    function payoutPercentage(address _recipient, uint _percent) internal onlyOwner noEther {
        payOutAmount(_recipient, (this.balance * _percent) / 100);
    }

    function payOutAmount(address _recipient, uint _amount) internal onlyOwner noEther {
        // send does not forward enough gas to see that this is a managed account call
        if (!_recipient.call.value(_amount)()){
            throw;
            // doThrow("payOut:sendFailed");
        }else{
            PayOut(msg.sender, msg.value, _recipient, _amount);
        }
    }
}

contract ReturnWallet is OwnedAccount {
    address public mgmtAddress;

    bool public inDistributionMode;
    uint public amountToDistribute;
    uint public totalTokens;
    uint public weiPerToken;

    function ReturnWallet(address _mgmtAddress) OwnedAccount(msg.sender){
        mgmtAddress = _mgmtAddress;
    }

    function payManagementBodyPercent(uint _percent) {
        // TODO
        payOutPercentage(mgmtAddress, _percent);
    }

    function switchToDistributionMode(uint _totalTokens) onlyOwner {
        inDistributionMode = true;
        acceptDeposits = false;
        totalTokens = _totalTokens;
        amountToDistribute = this.balance;
        weiPerToken = amountToDistribute / totalTokens;
    }

    function payTokenHolderBasedOnTokenCount(address _tokenHolderAddress, uint _tokens) onlyOwner {
        // TODO
        payOutAmount(_tokenHolderAddress, weiPerToken * _tokens);
    }
}

/**
 * Gamma Fund ICO contract.
 *
 * TO DO:
 * Security criteria - evaluate against http://ethereum.stackexchange.com/questions/8551/methodological-security-review-of-a-smart-contract
 *
 *
 */
contract GammaToken is StandardToken, SafeMath {

    string public name = "Gamma Token";
    string public symbol = "GAMMA";
    uint public decimals = 18;

    // Initial founder address (set in constructor)
    // All deposited ETH will be instantly forwarded to this address.
    // Address is a multisig wallet.
    address public mgmt = 0x0;

    // signer address (for clickwrap agreement)
    // see function() {} for comments
    address public signer = 0x0;

    ReturnWallet public returnWallet;

    uint public closingTime;
    uint public weiPerInitialGammaToken = 10**16;
    uint public maxBountyTokens = 80000;  /*  8 * (10**4)  */
    uint public tokensPerTier = 200000;   /*  2 * (10**5)  */
    uint public closingTimeExtensionPeriod = 30 days;
    uint public minTokensToCreate = 400000;  /*  4 * (10**5)  */
    uint public maxTokensToCreate = 4000000;  /*  4 * (10**6)  */

    uint public harvestQuorumPercent = 20;
    uint256 public supportHarvestQuorum;
    mapping (address => uint) public votedHarvest;
    bool public isHarvestEnabled;

    uint public freezeQuorumPercent = 50;
    uint256 public supportFreezeQuorum;
    mapping (address => uint) public votedFreeze;
    bool public isFreezeEnabled;

    bool public halted = false; //the management address can set this to true to halt the crowdsale due to emergency
    bool public isDayThirtyChecked;
    bool public isDaySixtyChecked;
    bool public isDistributionInProgress;
    bool public isDistributionReady;
    bool public isFundLocked;
    // bool public isFundReleased;

    uint public icoTokenSupply = 0; //this will keep track of the token supply created during the crowdsale
    uint public icoEtherRaised = 0; //this will keep track of the Ether raised during the crowdsale
    uint256 public bountyTokensCreated;

    event Buy(address indexed sender, uint eth, uint fbt);
    event Refund(address indexed sender, address to, uint eth);
    event Freeze(address indexed sender, uint eth);
    event Harvest(address indexed sender, uint eth);

    modifier notLocked() {
        require(!isFundLocked);
        _;
    }
    modifier onlyLocked() {
        require(isFundLocked);
        _;
    }
    modifier onlyDistributionNotReady() {
        require(!isDistributionReady);
        _;
    }
    modifier onlyDistributionReady() {
        require(isDistributionReady);
        _;
    }
    modifier onlyManagementBody {
        require(msg.sender == address(mgmt));
        _;
    }
    modifier onlyTokenHolders {
        require(balanceOf(msg.sender) > 0);
        _;
    }
    modifier noEther() {
        require(msg.value == 0);
        _;
    }
    modifier hasEther() {
        require(msg.value > 0);
        _;
    }
    modifier onlyCanIssueBountyToken(uint _amount) {
        require(bountyTokensCreated + _amount <= maxBountyTokens);
        _;
    }



    function GammaToken(address managementAddressInput, address signerInput) {
        mgmt = managementAddressInput;
        signer = signerInput;

        returnWallet = new ReturnWallet(mgmt);
    }

    function getCurrentTier() constant returns (uint8) {
        uint8 tier = (uint8) (totalSupply / tokensPerTier);
        return (tier > 4) ? 4 : tier;
    }

    function pricePerTokenAtCurrentTier() constant returns (uint) {

        // Quantity divisor model: based on total quantity of coins issued
        // Price ranged from 1.0 to 1.20 Ether for all Gamma Tokens with a 0.05 ETH increase for each tier

        // The number of (base unit) tokens per wei is calculated
        // as `msg.value` * 100 / `divisor`,  where divisor is `(100 + getCurrentTier() * 5)`

        return weiPerInitialGammaToken * (100 + getCurrentTier() * 5) / 100;
    }

    function mgmtMoveFund(
        address _recipientAddress,
        uint _amount
    ) noEther onlyManagementBody onlyLocked onlyDistributionNotReady {

    }

    function mgmtDistributeReturn() noEther onlyManagementBody onlyLocked onlyDistributionNotReady {

    }

    function mgmtIssueBountyToken(
        address _recipientAddress,
        uint _amount
    ) noEther onlyManagementBody onlyLocked onlyCanIssueBountyToken(_amount) returns (bool){
        // send token to the specified address
        balances[_recipientAddress] += _amount;
        bountyTokensCreated += _amount;

        // event
        // evMgmtIssueBountyToken(msg.sender, msg.value, _recipientAddress, _amount, true);

    }

    /**
     * Emergency Stop ICO.
     *
     */
    function mgmtHaltIco() onlyManagementBody{
        halted = true;
    }

    function mgmtUnhaltIco() onlyManagementBody{
        halted = false;
    }

    /**
     * Post-ICO operations
     *
     */
    function voteToFreezeFund() noEther onlyTokenHolders onlyLocked onlyDistributionNotReady {

        supportFreezeQuorum -= votedFreeze[msg.sender];
        supportFreezeQuorum += balances[msg.sender];
        votedFreeze[msg.sender] = balances[msg.sender];

        uint threshold = ((icoTokenSupply + bountyTokensCreated) * freezeQuorumPercent) / 100;
        if(supportFreezeQuorum > threshold){
            isFreezeEnabled = true;
            _executeFreezeFund();
            Freeze(msg.sender, msg.value);
        }
    }

    function _executeFreezeFund() internal onlyDistributionNotReady {
        // TODO
    }

    function voteToUnfreezeFund() noEther onlyTokenHolders onlyLocked onlyDistributionNotReady {

        supportFreezeQuorum -= votedFreeze[msg.sender];
        votedFreeze[msg.sender] = 0;
    }

    function voteToHarvest() noEther onlyTokenHolders onlyLocked onlyDistributionNotReady {

        supportHarvestQuorum -= votedHarvest[msg.sender];
        supportHarvestQuorum += balances[msg.sender];
        votedHarvest[msg.sender] = balances[msg.sender];

        uint threshold = ((icoTokenSupply + bountyTokensCreated) * harvestQuorumPercent) / 100;
        if(supportHarvestQuorum > threshold) {
            isHarvestEnabled = true;
            Harvest(msg.sender, msg.value);
        }
    }

    function harvestMyReturn() noEther onlyTokenHolders onlyLocked onlyDistributionReady {

        uint tokens = balances[msg.sender];
        balances[msg.sender] = 0;

        // TODO
        returnWallet.payTokenHolderBasedOnTokenCount(msg.sender, tokens);
    }


    // Buy entry point
    function buy(uint8 v, bytes32 r, bytes32 s) {
        buyRecipient(msg.sender, v, r, s);
    }

    /**
     * Main token buy function.
     *
     * Buy for the sender itself or buy on the behalf of somebody else (third party address).
     *
     * Security review
     *
     * - Integer math: ok - using SafeMath
     *
     * - halt flag added - ok
     *
     * Applicable tests:
     *
     * TODO - Test halting, buying, and failing
     * TODO - Test buying on behalf of a recipient
     * TODO - Test buy
     * TODO - Test unhalting, buying, and succeeding
     * TODO - Test buying after the sale ends
     *
     */
    function buyRecipient(address recipient, uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = sha256(msg.sender);
        if (ecrecover(hash,v,r,s) != signer) throw;
        if (halted) throw;
        // if (safeAdd(icoEtherRaised, msg.value) > etherCap || halted) throw;
        uint tokens = safeMul(msg.value, pricePerTokenAtCurrentTier());
        balances[recipient] = safeAdd(balances[recipient], tokens);
        totalSupply = safeAdd(totalSupply, tokens);
        icoEtherRaised = safeAdd(icoEtherRaised, msg.value);

        if (safeAdd(totalSupply, tokens) > maxTokensToCreate) throw;

        // TODO: Is there a pitfall of forwarding message value like this
        // TODO: Different address for mgmt deposits and mgmt operations (halt, unhalt)
        // as mgmt opeations might be easier to perform from normal geth account
        if (!mgmt.call.value(msg.value)()) throw; //immediately send Ether to mgmt address

        Buy(recipient, msg.value, tokens);
    }

    /**
     * Emergency Stop ICO.
     *
     *  Applicable tests:
     *
     * TODO - Test unhalting, buying, and succeeding
     */
    function halt() {
        if (msg.sender != mgmt) throw;
        halted = true;
    }

    function unhalt() {
        if (msg.sender != mgmt) throw;
        halted = false;
    }

    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     *
     * Applicable tests:
     *
     * TODO - Test restricted early transfer
     * TODO - Test transfer after restricted period
     */
    function transfer(address _to, uint256 _value) returns (bool success) {
        if (!isFundLocked && msg.sender != mgmt) throw;
        return super.transfer(_to, _value);
    }
    /**
     * ERC 20 Standard Token interface transfer function
     *
     * Prevent transfers until freeze period is over.
     */
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        if (!isFundLocked && msg.sender != mgmt) throw;
        return super.transferFrom(_from, _to, _value);
    }

    /**
     * Do not allow direct deposits.
     *
     * All crowdsale depositors must have read the legal agreement.
     * This is confirmed by having them signing the terms of service on the website.
     * The give their crowdsale Ethereum source address on the website.
     * Website signs this address using crowdsale private key (different from founders key).
     * buy() takes this signature as input and rejects all deposits that do not have
     * signature you receive after reading terms of service.
     *
     */
    function() {
        throw;
    }

}
