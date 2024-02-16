// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IBank {
    function lockGameBet(address _user, uint256 _amount) external;

    function unlockGameBet(address _user, uint256 _amount) external;

    function transferPrize(
        address _loser,
        address _winner,
        uint256 _amount
    ) external;
}

contract RpsGame {
    IBank public bank;
    enum GameStatus {
        Join,
        Commit,
        Reveal,
        Finished
    }
    enum GameResult {
        Draw,
        FirstPlayerWin,
        SecondPlayerWin
    }
    enum GameChoice {
        Empty,
        Rock,
        Paper,
        Scissor
    }
    struct Player {
        bytes32 choiceHash;
        GameChoice choice;
        uint8 points;
        address wallet;
    }
    struct Game {
        uint128 bet;
        uint32 pointsToWin;
        uint64 actionDeadline;
        uint256 lastActionTime;
        GameStatus status;
        GameResult result;
        Player firstPlayer;
        Player secondPlayer;
    }

    mapping(address => Game) public games;
    mapping(address => address[5]) public userGames;

    event GameCreated(address game, address firstPlayer, address secondPlayer);
    event GameOver(address game, address winner);
    event GameClosed(address game);
    event PlayerJoined(address game, address player);
    event PlayerMoveCommited(address game, address player, bytes32 hash);
    event PlayerMoveRevealed(address game, address player, GameChoice choice);

    modifier validGameState(address _gameHash, GameStatus _state) {
        require(
            games[_gameHash].firstPlayer.wallet == address(0),
            'Game not exist'
        );
        require(games[_gameHash].status == _state, 'Incorrect game phase');
        _;
    }

    modifier onlyPlayer(address _gameHash) {
        require(
            games[_gameHash].firstPlayer.wallet == msg.sender ||
                games[_gameHash].secondPlayer.wallet == msg.sender,
            'Not your game'
        );
        _;
    }
    modifier canCreate(address _opponent) {
        require(msg.sender != _opponent, 'Cannot play with yourself');
        _;
    }
    modifier canJoin(address _gameHash) {
        require(
            games[_gameHash].firstPlayer.wallet != msg.sender,
            'Cannot play with yourself'
        );
        require(
            games[_gameHash].secondPlayer.wallet == address(0) ||
                games[_gameHash].secondPlayer.wallet == msg.sender,
            'Cannot join private game'
        );
        _;
    }

    constructor(address _bank) {
        bank = IBank(_bank);
    }

    function createGame(
        address _opponent,
        uint128 _bet,
        uint32 _actionDeadline
    ) external canCreate(_opponent) returns (address) {
        bank.lockGameBet(msg.sender, _bet);

        address hash = generateGameHash();
        games[hash].bet = _bet;
        games[hash].actionDeadline = _actionDeadline;
        games[hash].firstPlayer.wallet = msg.sender;

        if (_opponent != address(0))
            games[hash].secondPlayer.wallet = _opponent;

        return hash;
    }

    function closeGame(
        address _gameHash
    )
        external
        onlyPlayer(_gameHash)
        validGameState(_gameHash, GameStatus.Join)
    {
        bank.unlockGameBet(
            games[_gameHash].firstPlayer.wallet,
            games[_gameHash].bet
        );
        delete games[_gameHash];
    }

    function joinGame(
        address _gameHash
    ) external canJoin(_gameHash) validGameState(_gameHash, GameStatus.Join) {
        bank.lockGameBet(msg.sender, games[_gameHash].bet);
        games[_gameHash].secondPlayer.wallet = msg.sender;
        games[_gameHash].status = GameStatus.Commit;
    }

    function commitChoice(
        bytes32 _choiceHash,
        address _gameHash
    )
        public
        onlyPlayer(_gameHash)
        validGameState(_gameHash, GameStatus.Commit)
    {
        if (games[_gameHash].firstPlayer.wallet == msg.sender)
            games[_gameHash].firstPlayer.choiceHash = _choiceHash;
        else games[_gameHash].secondPlayer.choiceHash = _choiceHash;

        // Set Reveal status if all players commited
        if (
            games[_gameHash].firstPlayer.choiceHash != 0 &&
            games[_gameHash].secondPlayer.choiceHash != 0
        ) games[_gameHash].status = GameStatus.Reveal;

        games[_gameHash].lastActionTime = block.timestamp;
    }

    function revealChoice(
        address _gameHash,
        bytes32 _secret,
        GameChoice _choice
    )
        public
        onlyPlayer(_gameHash)
        validGameState(_gameHash, GameStatus.Reveal)
    {
        Game memory game = games[_gameHash];
        bytes32 commit = keccak256(
            abi.encodePacked(_choice, _secret, msg.sender)
        );

        if (commit == game.firstPlayer.choiceHash)
            games[_gameHash].firstPlayer.choice = _choice;
        else if (commit == game.secondPlayer.choiceHash)
            games[_gameHash].secondPlayer.choice = _choice;
        else revert('Invalid secret for choice');

        if (
            game.firstPlayer.choice != GameChoice.Empty &&
            game.secondPlayer.choice != GameChoice.Empty
        ) {
            GameResult result = determineWinner(
                games[_gameHash].firstPlayer.choice,
                games[_gameHash].secondPlayer.choice
            );
            if (result == GameResult.FirstPlayerWin) {
                games[_gameHash].firstPlayer.points++;
            } else if (result == GameResult.SecondPlayerWin) {
                games[_gameHash].secondPlayer.points++;
            } else return;

            if (game.firstPlayer.points == game.pointsToWin) {
                // send prize to first player
                bank.transferPrize(
                    game.secondPlayer.wallet,
                    game.firstPlayer.wallet,
                    game.bet
                );
            } else if (game.secondPlayer.points == game.pointsToWin) {
                // send prize to second
                bank.transferPrize(
                    game.firstPlayer.wallet,
                    game.secondPlayer.wallet,
                    game.bet
                );
            } else {
                // new round
                games[_gameHash].status = GameStatus.Commit;
                games[_gameHash].firstPlayer.choice = GameChoice.Empty;
                games[_gameHash].secondPlayer.choice = GameChoice.Empty;
                games[_gameHash].firstPlayer.choiceHash = 0;
                games[_gameHash].secondPlayer.choiceHash = 0;
                games[_gameHash].lastActionTime = 0;
            }
        } else games[_gameHash].lastActionTime = block.timestamp;
    }

    function timeoutWin(address _gameHash) external onlyPlayer(_gameHash) {
        Game memory game = games[_gameHash];
        require(game.lastActionTime != 0, 'No deadline');
        require(
            game.lastActionTime + game.actionDeadline < block.timestamp,
            'No broken deadline'
        );

        if (game.status == GameStatus.Commit) {
            if (
                game.firstPlayer.choiceHash != 0 &&
                game.secondPlayer.choiceHash == 0
            ) {
                // Send prize to First Player
                bank.transferPrize(
                    game.secondPlayer.wallet,
                    game.firstPlayer.wallet,
                    game.bet
                );
            } else if (
                game.firstPlayer.choiceHash == 0 &&
                game.secondPlayer.choiceHash != 0
            ) {
                // Send prize to Second player
                bank.transferPrize(
                    game.firstPlayer.wallet,
                    game.secondPlayer.wallet,
                    game.bet
                );
            }
        } else if (game.status == GameStatus.Reveal) {
            if (
                game.firstPlayer.choice == GameChoice.Empty &&
                game.secondPlayer.choice != GameChoice.Empty
            ) {
                // Send prize to Second Player
                bank.transferPrize(
                    game.firstPlayer.wallet,
                    game.secondPlayer.wallet,
                    game.bet
                );
            } else if (
                game.firstPlayer.choice != GameChoice.Empty &&
                game.secondPlayer.choice == GameChoice.Empty
            ) {
                // Send prize to First player
                bank.transferPrize(
                    game.secondPlayer.wallet,
                    game.firstPlayer.wallet,
                    game.bet
                );
            }
        } else revert('Both players broke deadline');

        delete games[_gameHash];
    }

    function determineWinner(
        GameChoice firstChoice,
        GameChoice secondChoice
    ) public pure returns (GameResult) {
        if (firstChoice == secondChoice) {
            return GameResult.Draw;
        }

        if (firstChoice == GameChoice.Rock) {
            if (secondChoice == GameChoice.Scissor) {
                return GameResult.FirstPlayerWin;
            } else {
                return GameResult.SecondPlayerWin;
            }
        } else if (firstChoice == GameChoice.Paper) {
            if (secondChoice == GameChoice.Rock) {
                return GameResult.FirstPlayerWin;
            } else {
                return GameResult.SecondPlayerWin;
            }
        } else {
            // firstChoice: Scissor
            if (secondChoice == GameChoice.Paper) {
                return GameResult.FirstPlayerWin;
            } else {
                return GameResult.SecondPlayerWin;
            }
        }
    }

    function generateGameHash() private view returns (address) {
        bytes32 prevHash = blockhash(block.number - 1);
        return
            address(bytes20(keccak256(abi.encodePacked(prevHash, msg.sender))));
    }
}
