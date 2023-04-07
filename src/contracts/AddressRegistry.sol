// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@strategy/IStrategy.sol";
import "@vault/FeeOracle.sol";

contract AddressRegistry is OwnableUpgradeable {
    FeeOracle public feeOracle;
    address public router;
    mapping(address => IStrategy[]) public coinToStrategy;
    mapping(IStrategy => uint256) public strategyWhitelist;
    mapping(address => uint256) public rebalancerWhitelist;
    address[] public supportedCoinAddresses;

    event SET_ROUTER(address);
    event ADD_STRATEGY(IStrategy, address[]);
    event ADD_REBALANCER(address);
    event REMOVE_STRATEGY(IStrategy);
    event REMOVE_REBALANCER(address);

    constructor() {
        _disableInitializers();
    }

    function init(FeeOracle _feeOracle, address _router) external initializer {
        require(
            address(_feeOracle) != address(0),
            "_feeOracle address can't be zero"
        );
        require(_router != address(0), "_router address can't be zero");

        __Ownable_init();
        feeOracle = _feeOracle;
        router = _router;
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "_router address can't be zero");
        router = _router;

        emit SET_ROUTER(_router);
    } 

    function addStrategy(
        IStrategy strategy,
        address[] calldata coins
    ) external onlyOwner {
        require(strategyWhitelist[strategy] == 0, "Strategy already whitelisted");
        for (uint256 i; i < coins.length; ) {
            IStrategy[] memory strategiesForCoin = coinToStrategy[coins[i]];
            uint256 j;
            /// check strategy is already registered for the coin
            for (; j < strategiesForCoin.length; j++) {
                if (address(strategiesForCoin[j]) == address(strategy)) break;
            }
            /// add strategy if it's not registered
            if (j == strategiesForCoin.length) {
                coinToStrategy[coins[i]].push(strategy);
            }
            unchecked {
                i++;
            }
        }
        strategyWhitelist[strategy] = block.timestamp + 1 days;

        emit ADD_STRATEGY(strategy, coins);
    }

    function addRebalancer(address rebalancer) external onlyOwner {
        require(
            rebalancerWhitelist[rebalancer] == 0,
            "Rebalancer already whitelisted"
        );
        rebalancerWhitelist[rebalancer] = block.timestamp + 1 days;

        emit ADD_REBALANCER(rebalancer);
    }

    function removeStrategy(IStrategy strategy) external onlyOwner {
        require(strategyWhitelist[strategy] != 0, "Strategy not whitelisted");
        strategyWhitelist[strategy] = 0;

        emit REMOVE_STRATEGY(strategy);
    }

    function removeRebalancer(address rebalancer) external onlyOwner {
        require(
            rebalancerWhitelist[rebalancer] != 0,
            "Rebalancer not whitelisted"
        );
        rebalancerWhitelist[rebalancer] = 0;

        emit REMOVE_REBALANCER(rebalancer);
    }

    function getCoinToStrategy(
        address coin
    ) external view returns (IStrategy[] memory strategies) {
      uint256 activeStrategies = 0;
      // count active strategies
      for(uint256 i; i < coinToStrategy[coin].length; i++) {
        if(strategyWhitelist[coinToStrategy[coin][i]] < block.timestamp && strategyWhitelist[coinToStrategy[coin][i]] != 0) {
          activeStrategies++;
        }
      }
      // create array of active strategies
      uint j = 0;
      strategies = new IStrategy[](activeStrategies);
      for(uint256 i; i < coinToStrategy[coin].length; i++) {
        if(strategyWhitelist[coinToStrategy[coin][i]] < block.timestamp && strategyWhitelist[coinToStrategy[coin][i]] != 0) {
          strategies[j] = coinToStrategy[coin][i];
          j++;
        }
      }
    }

    function getWhitelistedStrategies(
        IStrategy strategy
    ) external view returns (bool) {
        return block.timestamp >= strategyWhitelist[strategy] && strategyWhitelist[strategy] != 0;
    }

    function getWhitelistedRebalancer(
        address rebalancer
    ) external view returns (bool) {
        return block.timestamp >= rebalancerWhitelist[rebalancer] && rebalancerWhitelist[rebalancer] != 0;
    }
}