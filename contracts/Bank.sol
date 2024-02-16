// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

contract Bank {
    uint8 public penaltyPercentage = 10;
    uint32 public lockPeriod = 7 days;
    address public owner;

    struct Balance {
        uint256 amount;
        uint256 lockedInGames;
        uint256 lockedPrize;
        uint256 lockedUntil;
    }

    mapping(address => Balance) public balances;
    mapping(address => bool) public games;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount, uint256 penalty);
    event UserLockedPrizeDateUpdated(address indexed user);
    event UserLockedPrizeAmountUpdated(address indexed user, uint256 indexed amount);

    modifier onlyOwner() {
        require(msg.sender == owner, 'Not contract owner');
        _;
    }

    modifier onlyGame() {
        require(games[msg.sender], 'Not an allowed game contract');
        _;
    }

    modifier canWithdraw(address _user, uint256 _amount) {
        uint lockedPrize = balances[_user].lockedUntil > block.timestamp ? balances[_user].lockedPrize : 0;
        require(
            balances[_user].amount - (balances[_user].lockedInGames + lockedPrize) >= _amount,
            'Insufficient balance'
        );
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setLockPeriod(uint32 _period) external onlyOwner {
        lockPeriod = _period;
    }

    function setPenaltyPercentage(uint8 _penaltyPercentage) external onlyOwner {
        require(_penaltyPercentage <= 50, 'Too greedy');
        penaltyPercentage = _penaltyPercentage;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function addGame(address _game) external onlyOwner {
        games[_game] = true;
    }

    function removeGame(address _game) external onlyOwner {
        delete games[_game];
    }

    /**
     * Manage balances by games
     * lockGameBet - lock amount when user starts game
     * unlockGameBet - unlock amount when user close game
     * transferPrize - send prize from loser to winner and locks prize for lockPeriod
     */

    function lockGameBet(address _user, uint256 _amount) external onlyGame {
        require(balances[_user].amount - balances[_user].lockedInGames >= _amount, 'Insufficient balance');

        balances[_user].lockedInGames += _amount;
    }

    function unlockGameBet(address _user, uint256 _amount) external onlyGame {
        balances[_user].lockedInGames -= _amount;
    }

    function transferPrize(address _loser, address _winner, uint256 _amount) external onlyGame {
        // update lockedPrize and lockedPrizeUntil time
        if (balances[_winner].lockedUntil < block.timestamp) {
            balances[_winner].lockedPrize = _amount;
        } else {
            balances[_winner].lockedPrize += _amount;
        }

        uint newLockedUntil = block.timestamp + lockPeriod;
        balances[_winner].lockedUntil = newLockedUntil;

        emit UserLockedPrizeDateUpdated(_winner);
        emit UserLockedPrizeAmountUpdated(_winner, _amount);

        // send amount from loser to winner and unlock game amount
        balances[_loser].amount -= _amount;
        balances[_winner].amount += _amount;
        balances[_loser].lockedInGames -= _amount;
        balances[_winner].lockedInGames -= _amount;
    }

    function withdraw(uint256 _amount) external canWithdraw(msg.sender, _amount) {
        balances[msg.sender].amount -= _amount;
        if (balances[msg.sender].amount == 0) delete balances[msg.sender];

        payable(msg.sender).transfer(_amount);
        emit Withdrawal(msg.sender, _amount, 0);
    }

    function withdrawWithPenalty(uint256 _amount) external {
        require(balances[msg.sender].amount - (balances[msg.sender].lockedInGames) >= _amount, 'Insufficient balance');
        uint256 penaltyAmount = _amount - (balances[msg.sender].amount - balances[msg.sender].lockedPrize);
        require(penaltyAmount > 0, 'No penalty');
        uint256 penalty = (penaltyAmount * penaltyPercentage) / 100;
        uint256 withdrawAmount = _amount - penalty;

        balances[msg.sender].amount -= _amount;
        balances[owner].amount += penalty;
        if (balances[msg.sender].amount == 0) delete balances[msg.sender];

        payable(msg.sender).transfer(withdrawAmount);
        emit Withdrawal(msg.sender, withdrawAmount, penalty);
    }

    receive() external payable {
        require(msg.value > 0, 'Incorrect amount');
        balances[msg.sender].amount += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function getBalance(address _user) public view returns (uint, uint, uint, uint) {
        Balance memory b = balances[_user];
        return (b.amount, b.lockedInGames, b.lockedPrize, b.lockedUntil);
    }

    function isGame(address _game) public view returns (bool) {
        return games[_game];
    }
}
