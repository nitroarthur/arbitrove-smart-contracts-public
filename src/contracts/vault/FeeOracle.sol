// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@vault/IVault.sol";
import "@structs/structs.sol";

/// Fee oracle contract that provides deposit and withdrawal fees to be used by vault contract
/// Find the formulas here: https://docs.google.com/spreadsheets/d/1K-x2kDNVfSKCEjaOtOS_gbQu5PcrkRccioJP1UBuLhs/edit#gid=0
/// The fees are based on the current weight of a coin in the vault compared to its target
contract FeeOracle is OwnableUpgradeable {
    /// targets
    CoinWeight[50] public targets;
    /// length of coin weight targets
    uint256 public targetsLength;
    /// max fee
    uint256 public maxFee;
    /// max bonus
    uint256 public maxBonus;
    /// weight denominator for weight calculation
    uint256 public weightDenominator;

    event SET_TARGETS(CoinWeight[]);

    constructor() {
        _disableInitializers();
    }

    function init(uint256 _maxFee, uint256 _maxBonus) external initializer {
        require(_maxFee <= 100, "_maxFee can't greater than 100");
        require(_maxBonus <= 100, "_maxFee can't greater than 100");

        __Ownable_init();
        maxFee = _maxFee;
        maxBonus = _maxBonus;
        weightDenominator = 100;
    }

    function setMaxFee(uint256 _maxFee) external onlyOwner {
        maxFee = _maxFee;
    }

    function setMaxBonus(uint256 _maxBonus) external onlyOwner {
        maxBonus = _maxBonus;
    }

    /// @notice Set target coin weights
    /// @param weights Coin weightes to set
    function setTargets(CoinWeight[] memory weights) external onlyOwner {
        targetsLength = weights.length;
        for (uint8 i; i < weights.length; ) {
            targets[i] = weights[i];
            unchecked {
                ++i;
            }
        }
        isNormalizedWeightArray(weights);
        emit SET_TARGETS(weights);
    }

    function isInTarget(address coin) public view returns (bool) {
        for (uint8 i; i < targetsLength; ) {
            if (targets[i].coin == coin) return true;
            unchecked {
                ++i;
            }
        }
        return false;
    }

    /// @notice Get deposit fee
    /// @param params Deposit fee params
    /// @return fee Deposit fee
    /// @return weights Latest coin weights for vault before deposit
    /// @return tvlUSD1e18X Latest tvl for vault before deposit
    function getDepositFee(
        DepositFeeParams memory params
    )
        external
        view
        returns (int256 fee, CoinWeight[] memory weights, uint256 tvlUSD1e18X)
    {
        CoinWeightsParams memory coinWeightParams = CoinWeightsParams({
            cpu: params.cpu,
            vault: params.vault,
            expireTimestamp: params.expireTimestamp
        });
        (weights, tvlUSD1e18X) = getCoinWeights(coinWeightParams);
        CoinWeight memory target = targets[params.position];
        CoinWeight memory currentCoinWeight = weights[params.position];
        uint256 __decimals = target.coin == address(0)
            ? 18
            : IERC20Metadata(target.coin).decimals();

        /// new weight calc
        /// formula: depositValue = depositAmount * depositPrice / 10**decimals
        uint256 depositValueUSD1e18X = (params.amount *
            params.cpu[params.position].price) / 10 ** __decimals;

        /// formula: currentCoinValue = currentCoinWeight * tvl / weightDenominator
        uint256 currentCoinValue = (currentCoinWeight.weight * tvlUSD1e18X) /
            weightDenominator;

        /// formula: newWeight = (currentCoinValue + depositValue) * weightDenominator / (tvl + depositValue)
        uint256 newWeight = ((currentCoinValue + depositValueUSD1e18X) *
            weightDenominator) / (tvlUSD1e18X + depositValueUSD1e18X);

        /// calculate distance
        /// calculate original distance
        /// formula: originalDistance = abs(currentWeight - targetWeight) / targetWeight
        uint256 originalDistance = getDistance(
            target.weight,
            currentCoinWeight.weight
        );
        /// calculate new distance
        /// formula: newDistance = abs(newWeight - targetWeight) / targetWeight
        uint256 newDistance = getDistance(target.weight, newWeight);
        require(newDistance < weightDenominator, "Too far away from target");
        if (originalDistance > newDistance) {
            // bonus
            uint256 improvement = originalDistance - newDistance;
            fee =
                (int256(improvement * maxBonus) * -1) /
                int256(weightDenominator);
        } else {
            // penalty
            uint256 deterioration = newDistance - originalDistance;
            fee = int256(deterioration * maxFee) / int256(weightDenominator);
        }
    }

    /// @notice Get withdrawal fee
    /// @param params Withdrawal fee params
    /// @return fee Withdrawal fee
    /// @return weights Latest coin weight for vault before withdraw
    /// @return tvlUSD1e18X Latest tvl for vault before withdraw
    function getWithdrawalFee(
        WithdrawalFeeParams memory params
    )
        external
        view
        returns (int256 fee, CoinWeight[] memory weights, uint256 tvlUSD1e18X)
    {
        CoinWeightsParams memory coinWeightParams = CoinWeightsParams({
            cpu: params.cpu,
            vault: params.vault,
            expireTimestamp: params.expireTimestamp
        });
        (weights, tvlUSD1e18X) = getCoinWeights(coinWeightParams);
        CoinWeight memory target = targets[params.position];
        CoinWeight memory currentCoinWeight = weights[params.position];
        uint256 __decimals = target.coin == address(0)
            ? 18
            : IERC20Metadata(target.coin).decimals();

        /// new weight calc
        /// formula: withdrawalValue = withdrawalAmount * withdrawalPrice / 10**decimals
        uint256 withdrawalValueUSD1e18X = (params.amount *
            params.cpu[params.position].price) / 10 ** __decimals;

        /// formula: currentCoinValue = currentCoinWeight * tvl / weightDenominator
        uint256 currentCoinValue = (currentCoinWeight.weight * tvlUSD1e18X) /
            weightDenominator;

        /// formula: newWeight = (currentCoinValue - withdrawalValue) * weightDenominator / (tvl - withdrawalValue)
        uint256 newWeight = ((currentCoinValue - withdrawalValueUSD1e18X) *
            weightDenominator) / (tvlUSD1e18X - withdrawalValueUSD1e18X);

        // calculate distance
        /// calculate original distance
        /// formula: originalDistance = abs(currentWeight - targetWeight) / targetWeight
        uint256 originalDistance = getDistance(
            target.weight,
            currentCoinWeight.weight
        );
        /// calculate new distance
        /// formula: newDistance = abs(newWeight - targetWeight) / targetWeight
        uint256 newDistance = getDistance(target.weight, newWeight);
        require(newDistance < weightDenominator, "Too far away from target");
        if (originalDistance > newDistance) {
            // bonus
            uint256 improvement = originalDistance - newDistance;
            fee = int256(improvement * maxBonus) / int256(weightDenominator);
        } else {
            // penalty
            uint256 deterioration = newDistance - originalDistance;
            fee =
                (int256(deterioration * maxFee) * -1) /
                int256(weightDenominator);
        }
    }

    /// @notice Get targets
    /// @return targets coin weights
    function getTargets() external view returns (CoinWeight[] memory) {
        CoinWeight[] memory _targets = new CoinWeight[](targetsLength);
        for (uint8 i; i < targetsLength; ) {
            _targets[i] = targets[i];
            unchecked {
                ++i;
            }
        }
        return _targets;
    }

    /// @notice Get current coin weights and tvl for given params
    /// @param params CoinWeightsPrams for get coin weights
    /// @return weights Current coin weights for given params
    /// @return tvlUSD1e18X TVL for given vault
    function getCoinWeights(
        CoinWeightsParams memory params
    ) public view returns (CoinWeight[] memory weights, uint256 tvlUSD1e18X) {
        weights = new CoinWeight[](targetsLength);
        require(
            block.timestamp < params.expireTimestamp,
            "Execution window passed"
        );
        // verify signature
        require(params.cpu.length == targetsLength, "Oracle length error");
        CoinWeight[50] memory _targets = targets;
        uint256 _targetsLength = targetsLength;
        for (uint8 i; i < _targetsLength; ) {
            require(
                params.cpu[i].coin == _targets[i].coin,
                "Oracle order error"
            );
            /// Get available amount of coin for the vault per every coin
            /// formula: coinVaultAmount + coinStrategiesAmount - coinDebtAmount
            uint256 amount = params.vault.getAmountAcrossStrategies(
                _targets[i].coin
            ) - params.vault.debt(_targets[i].coin);
            /// Initialize coinWeight with available amount of coin
            weights[i] = CoinWeight(params.cpu[i].coin, amount);
            unchecked {
                i++;
            }
        }

        /// Calc tvl
        uint8[] memory __decimals = new uint8[](_targetsLength);
        for (uint8 i; i < _targetsLength; ) {
            __decimals[i] = _targets[i].coin == address(0)
                ? 18
                : IERC20Metadata(_targets[i].coin).decimals();
            /// Calculate tvl over the coin weights
            /// Set weight with every coin value
            /// formula: coinValue = coinAmount * coinPirceUSD / 10**coinDecimal
            weights[i].weight =
                (weights[i].weight * params.cpu[i].price) /
                10 ** __decimals[i];
            /// formula: tvl += coinValue
            tvlUSD1e18X += weights[i].weight;
            unchecked {
                i++;
            }
        }

        /// Normalize
        for (uint8 i; i < _targetsLength; ) {
            /// Normalize coin weights
            /// formula: weight = coinValue * weightDenominator / tvl
            weights[i].weight =
                (weights[i].weight * weightDenominator) /
                tvlUSD1e18X;
            unchecked {
                i++;
            }
        }
        isNormalizedWeightArray(weights);
    }

    /// @notice Check if weights array is normalized or not
    /// @param weights Coin weight array that needs to be checked
    function isNormalizedWeightArray(
        CoinWeight[] memory weights
    ) internal pure {
        uint256 totalWeight = 0;
        uint8 j;
        for (uint8 i; i < weights.length; ) {
            totalWeight += weights[i].weight;
            unchecked {
                i++;
            }
            unchecked {
                j++;
            }
        }
        // compensate for rounding errors
        require(totalWeight >= 100 - j, "Weight error");
        require(totalWeight <= 100, "Weight error 2");
    }

    /// @notice Get distance between two weights. The "distance" is calculated as a percentage change of the new weight compared to the target weight.
    /// @param targetWeight Standard weight that calculate distance
    /// @param comparedWeight Compared weight that calculate distance
    /// @return disatnce
    function getDistance(
        uint256 targetWeight,
        uint256 comparedWeight
    ) internal view returns (uint256) {
        /// formula: distance = abs(targetWeight - comparedWeight) * weightDenominator / targetWeight
        return
            targetWeight >= comparedWeight
                ? ((targetWeight - comparedWeight) * weightDenominator) /
                    targetWeight
                : ((comparedWeight - targetWeight) * weightDenominator) /
                    targetWeight;
    }
}
