// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {L_Proof} from "./L_Proof.sol";
import {TTSwapError} from "./L_Error.sol";
import {L_MarketConfigLibrary} from "./L_MarketConfig.sol";
import {L_GoodConfigLibrary} from "./L_GoodConfig.sol";

import {S_GoodState, S_GoodKey, S_ProofState, S_LoanProof} from "../interfaces/I_TTSwap_Market.sol";
import {L_TTSwapUINT256Library, toTTSwapUINT256, add, sub, addsub, subadd, lowerprice} from "./L_TTSwapUINT256.sol";

/**
 * @title L_Good Library
 * @dev A library for managing goods in a decentralized marketplace
 * @notice This library provides functions for investing, disinvesting, swapping, and fee management for goods
 */
library L_Good {
    using L_GoodConfigLibrary for uint256;
    using L_MarketConfigLibrary for uint256;
    using L_TTSwapUINT256Library for uint256;
    using L_Proof for S_ProofState;

    /**
     * @notice Update the good configuration
     * @dev Preserves the top 33 bits of the existing config and updates the rest
     * @param _self Storage pointer to the good state
     * @param _goodConfig New configuration value to be applied
     */
    function updateGoodConfig(
        S_GoodState storage _self,
        uint256 _goodConfig
    ) internal {
        // Clear the top 33 bits of the new config
        assembly {
            _goodConfig := shr(27, shl(27, _goodConfig))
        }
        // Preserve the top 33 bits of the existing config and add the new config
        _self.goodConfig = ((_self.goodConfig >> 229) << 229) + _goodConfig;
    }

    /**
     * @notice Initialize the good state
     * @dev Sets up the initial state, configuration, and owner of the good
     * @param self Storage pointer to the good state
     * @param _init Initial balance state
     * @param _goodConfig Configuration of the good
     */
    function init(
        S_GoodState storage self,
        uint256 _init,
        uint256 _goodConfig
    ) internal {
        self.currentState = _init;
        self.investState = _init;
        self.goodConfig = (_goodConfig << 27) >> 27;
        self.owner = msg.sender;
    }

    /**
     * @dev Struct to cache swap-related data
     */
    struct swapCache {
        uint128 remainQuantity; // Remaining quantity to be swapped
        uint128 outputQuantity; // Quantity received from the swap
        uint128 feeQuantity; // Fee amount for the swap
        uint128 swapvalue; // Total value of the swap
        uint256 good1currentState; // Current state of the first good
        uint256 good1config; // Configuration of the first good
        uint256 good2currentState; // Current state of the second good
        uint256 good2config; // Configuration of the second good
    }

    /**
     * @notice Compute the swap result from good1 to good2
     * @dev Implements a complex swap algorithm considering price limits, fees, and minimum swap amounts
     * @param _stepCache A cache structure containing swap state and configurations
     * @param _tradetimes tradetimes
     */
    function swapCompute1(
        swapCache memory _stepCache,
        uint128 _tradetimes
    ) internal pure {
        // Check if the current price is lower than the limit price, if not, return immediately

        uint128 minValue;
        uint128 minQuantity;

        // Calculate and deduct the sell fee
        _stepCache.feeQuantity = _stepCache.good1config.getSellFee(
            _stepCache.remainQuantity
        );
        _stepCache.remainQuantity -= _stepCache.feeQuantity;

        // Continue swapping while there's remaining quantity and price is favorable
        while (_stepCache.remainQuantity > 0 && _tradetimes > 0) {
            _tradetimes -= 1;
            // Determine the minimum swap value (take the smaller of the two goods)
            minValue = _stepCache.good1config.getSwapChips(
                _stepCache.good1currentState.amount0()
            ) >=
                _stepCache.good2config.getSwapChips(
                    _stepCache.good2currentState.amount0()
                )
                ? _stepCache.good2config.getSwapChips(
                    _stepCache.good2currentState.amount0()
                )
                : _stepCache.good1config.getSwapChips(
                    _stepCache.good1currentState.amount0()
                );

            // Calculate the corresponding quantity for the minimum value
            minQuantity = _stepCache.good1currentState.getamount1fromamount0(
                minValue
            );

            if (_stepCache.remainQuantity > minQuantity) {
                // Swap the entire minQuantity
                _stepCache.remainQuantity -= minQuantity;

                // Calculate and add the output quantity
                _stepCache.outputQuantity += _stepCache
                    .good2currentState
                    .getamount1fromamount0(minValue);

                // Update the states of both goods
                _stepCache.good1currentState = subadd(
                    _stepCache.good1currentState,
                    toTTSwapUINT256(minValue, minQuantity)
                );
                _stepCache.good2currentState = addsub(
                    _stepCache.good2currentState,
                    toTTSwapUINT256(
                        minValue,
                        _stepCache.good2currentState.getamount1fromamount0(
                            minValue
                        )
                    )
                );
            } else {
                // Swap the remaining quantity
                minValue = _stepCache.good1currentState.getamount0fromamount1(
                    _stepCache.remainQuantity
                );
                _stepCache.outputQuantity += _stepCache
                    .good2currentState
                    .getamount1fromamount0(minValue);

                // Update the states of both goods
                _stepCache.good1currentState = subadd(
                    _stepCache.good1currentState,
                    toTTSwapUINT256(minValue, _stepCache.remainQuantity)
                );

                _stepCache.good2currentState = addsub(
                    _stepCache.good2currentState,
                    toTTSwapUINT256(
                        minValue,
                        _stepCache.good2currentState.getamount1fromamount0(
                            minValue
                        )
                    )
                );
                _stepCache.remainQuantity = 0;
            }

            // Update the total swap value
            _stepCache.swapvalue += minValue;
        }

        // Adjust fees if there's remaining quantity
        if (_stepCache.remainQuantity > 0) {
            _stepCache.feeQuantity -= _stepCache.good1config.getSellFee(
                _stepCache.remainQuantity
            );

            _stepCache.remainQuantity += _stepCache.good1config.getSellFee(
                _stepCache.remainQuantity
            );
        }
    }

    /**
     * @notice Compute the swap result from good1 to good2
     * @dev Implements a complex swap algorithm considering price limits, fees, and minimum swap amounts
     * @param _stepCache A cache structure containing swap state and configurations
     * @param _tradetimes tradetimes
     */
    function swapCompute2(
        swapCache memory _stepCache,
        uint128 _tradetimes
    ) internal pure {
        // Check if the current price is lower than the limit price, if not, return immediately

        uint128 minValue;
        uint128 minQuantity;
        _tradetimes = _tradetimes - 100;

        // Calculate and deduct the sell fee
        _stepCache.feeQuantity = _stepCache.good1config.getSellFee(
            _stepCache.remainQuantity
        );
        _stepCache.remainQuantity += _stepCache.feeQuantity;

        // Continue swapping while there's remaining quantity and price is favorable
        while (_stepCache.remainQuantity > 0 && _tradetimes > 0) {
            _tradetimes -= 1;
            // Determine the minimum swap value (take the smaller of the two goods)
            minValue = _stepCache.good1config.getSwapChips(
                _stepCache.good1currentState.amount0()
            ) >=
                _stepCache.good2config.getSwapChips(
                    _stepCache.good2currentState.amount0()
                )
                ? _stepCache.good2config.getSwapChips(
                    _stepCache.good2currentState.amount0()
                )
                : _stepCache.good1config.getSwapChips(
                    _stepCache.good1currentState.amount0()
                );

            // Calculate the corresponding quantity for the minimum value
            minQuantity = _stepCache.good1currentState.getamount1fromamount0(
                minValue
            );

            if (_stepCache.remainQuantity > minQuantity) {
                // Swap the entire minQuantity
                _stepCache.remainQuantity -= minQuantity;

                // Calculate and add the output quantity
                _stepCache.outputQuantity += _stepCache
                    .good2currentState
                    .getamount1fromamount0(minValue);

                // Update the states of both goods
                _stepCache.good1currentState = addsub(
                    _stepCache.good1currentState,
                    toTTSwapUINT256(minValue, minQuantity)
                );
                _stepCache.good2currentState = subadd(
                    _stepCache.good2currentState,
                    toTTSwapUINT256(
                        minValue,
                        _stepCache.good2currentState.getamount1fromamount0(
                            minValue
                        )
                    )
                );
            } else {
                // Swap the remaining quantity
                minValue = _stepCache.good1currentState.getamount0fromamount1(
                    _stepCache.remainQuantity
                );
                _stepCache.outputQuantity += _stepCache
                    .good2currentState
                    .getamount1fromamount0(minValue);

                // Update the states of both goods
                _stepCache.good1currentState = addsub(
                    _stepCache.good1currentState,
                    toTTSwapUINT256(minValue, _stepCache.remainQuantity)
                );

                _stepCache.good2currentState = subadd(
                    _stepCache.good2currentState,
                    toTTSwapUINT256(
                        minValue,
                        _stepCache.good2currentState.getamount1fromamount0(
                            minValue
                        )
                    )
                );
                _stepCache.remainQuantity = 0;
            }
            // Update the total swap value
            _stepCache.swapvalue += minValue;
        }
    }

    /**
     * @notice Commit the result of a swap operation to the good's state
     * @dev Updates the current state and fee state of the good after a swap
     * @param _self Storage pointer to the good state
     * @param _swapstate The new state of the good after the swap
     * @param _fee The fee amount collected from the swap
     */
    function swapCommit(
        S_GoodState storage _self,
        uint256 _swapstate,
        uint128 _fee
    ) internal {
        _self.currentState = _swapstate;
        _self.feeQuantityState = add(
            _self.feeQuantityState,
            toTTSwapUINT256(_fee, 0)
        );
    }

    /**
     * @notice Struct to hold the return values of an investment operation
     * @dev Used to store and return the results of investing in a good
     */
    struct S_GoodInvestReturn {
        uint128 actualFeeQuantity; // The actual fee amount charged for the investment
        uint128 constructFeeQuantity; // The construction fee amount (if applicable)
        uint128 actualInvestValue; // The actual value invested after fees
        uint128 actualInvestQuantity; // The actual quantity of goods received for the investment
    }

    /**
     * @notice Invest in a good
     * @dev Calculates fees, updates states, and returns investment results
     * @param _self Storage pointer to the good state
     * @param _invest Amount to invest
     */
    function investGood(
        S_GoodState storage _self,
        uint128 _invest,
        S_GoodInvestReturn memory investResult_
    ) internal {
        // Calculate the investment fee
        investResult_.actualFeeQuantity = _self.goodConfig.getInvestFee(
            _invest
        );
        // Calculate the actual investment quantity after deducting the fee
        investResult_.actualInvestQuantity =
            _invest -
            investResult_.actualFeeQuantity;

        // Calculate the actual investment value based on the current state
        investResult_.actualInvestValue = _self
            .currentState
            .getamount0fromamount1(investResult_.actualInvestQuantity);

        // Calculate the construction fee
        investResult_.constructFeeQuantity = toTTSwapUINT256(
            _self.feeQuantityState.amount0(),
            _self.investState.amount1()
        ).getamount0fromamount1(investResult_.actualInvestQuantity);

        // Update the fee quantity state
        _self.feeQuantityState = add(
            _self.feeQuantityState,
            toTTSwapUINT256(
                investResult_.actualFeeQuantity +
                    investResult_.constructFeeQuantity,
                investResult_.constructFeeQuantity
            )
        );
        // Update the current state with the new investment
        _self.currentState = add(
            _self.currentState,
            toTTSwapUINT256(
                investResult_.actualInvestValue,
                investResult_.actualInvestQuantity
            )
        );
        // Update the invest state with the new investment
        _self.investState = add(
            _self.investState,
            toTTSwapUINT256(
                investResult_.actualInvestValue,
                investResult_.actualInvestQuantity
            )
        );
    }
    /**
     * @notice Struct to hold the return values of a disinvestment operation
     * @dev Used to store and return the results of disinvesting from a good
     */

    struct S_GoodDisinvestReturn {
        uint128 profit; // The profit earned from disinvestment
        uint128 actual_fee; // The actual fee charged for disinvestment
        uint128 actualDisinvestQuantity; // The actual quantity of goods disinvested
    }

    /**
     * @notice Struct to hold the parameters for a disinvestment operation
     * @dev Used to pass multiple parameters to the disinvestGood function
     */
    struct S_GoodDisinvestParam {
        uint128 _goodQuantity; // The quantity of goods to disinvest
        address _gater; // The address of the gater (if applicable)
        address _referral; // The address of the referrer (if applicable)
        uint256 _marketconfig; // The market configuration
        address _marketcreator; // The address of the market creator
    }

    /**
     * @notice Disinvest from a good and potentially its associated value good
     * @dev This function handles the complex process of disinvesting from a good, including fee calculations and state updates
     * @param _self Storage pointer to the main good state
     * @param _valueGoodState Storage pointer to the value good state (if applicable)
     * @param _investProof Storage pointer to the investment proof state
     * @param _params Struct containing disinvestment parameters
     * @return normalGoodResult1_ Struct containing disinvestment results for the main good
     * @return valueGoodResult2_ Struct containing disinvestment results for the value good (if applicable)
     * @return disinvestvalue The total value being disinvested
     */
    function disinvestGood(
        S_GoodState storage _self,
        S_GoodState storage _valueGoodState,
        S_ProofState storage _investProof,
        S_GoodDisinvestParam memory _params
    )
        internal
        returns (
            S_GoodDisinvestReturn memory normalGoodResult1_,
            S_GoodDisinvestReturn memory valueGoodResult2_,
            uint128 disinvestvalue
        )
    {
        // Calculate the disinvestment value based on the investment proof and requested quantity
        disinvestvalue = toTTSwapUINT256(
            _investProof.state.amount0(),
            _investProof.invest.amount1()
        ).getamount0fromamount1(_params._goodQuantity);
        // Ensure disinvestment conditions are met
        if (
            disinvestvalue >
            _self.goodConfig.getDisinvestChips(_self.currentState.amount0()) ||
            _params._goodQuantity >
            _self.goodConfig.getDisinvestChips(_self.currentState.amount1())
        ) revert TTSwapError(31);
        // Calculate initial disinvestment results for the main good
        normalGoodResult1_ = S_GoodDisinvestReturn(
            toTTSwapUINT256(
                _self.feeQuantityState.amount0(),
                _self.investState.amount1()
            ).getamount0fromamount1(_params._goodQuantity),
            toTTSwapUINT256(
                _investProof.invest.amount0(),
                _investProof.invest.amount1()
            ).getamount0fromamount1(_params._goodQuantity),
            _params._goodQuantity
        );

        // Update main good states
        _self.currentState = sub(
            _self.currentState,
            toTTSwapUINT256(
                disinvestvalue,
                normalGoodResult1_.actualDisinvestQuantity
            )
        );

        _self.investState = sub(
            _self.investState,
            toTTSwapUINT256(
                disinvestvalue,
                normalGoodResult1_.actualDisinvestQuantity
            )
        );

        _self.feeQuantityState = sub(
            _self.feeQuantityState,
            toTTSwapUINT256(
                normalGoodResult1_.profit,
                normalGoodResult1_.actual_fee
            )
        );


        // Calculate final profit and fee for main good
        normalGoodResult1_.profit =
            normalGoodResult1_.profit -
            normalGoodResult1_.actual_fee;

        normalGoodResult1_.actual_fee = _self.goodConfig.getDisinvestFee(
            normalGoodResult1_.actualDisinvestQuantity
        );



        // Update fee state for main good if necessary
        if (normalGoodResult1_.actual_fee > 0) {
            _self.feeQuantityState = add(
                _self.feeQuantityState,
                toTTSwapUINT256(normalGoodResult1_.actual_fee, 0)
            );
        }

        // Handle value good disinvestment if applicable
        if (_investProof.valuegood != address(0)) {
            // Calculate disinvestment results for value good
            valueGoodResult2_ = S_GoodDisinvestReturn(
                toTTSwapUINT256(
                    _valueGoodState.feeQuantityState.amount0(),
                    _valueGoodState.investState.amount1()
                ).getamount0fromamount1(disinvestvalue),
                toTTSwapUINT256(
                    _investProof.valueinvest.amount0(),
                    _investProof.valueinvest.amount1()
                ).getamount0fromamount1(disinvestvalue),
                toTTSwapUINT256(
                    _investProof.state.amount0(),
                    _investProof.valueinvest.amount1()
                ).getamount1fromamount0(disinvestvalue)
            );

            // Ensure value good disinvestment conditions are met
            if (
                disinvestvalue >
                _valueGoodState.goodConfig.getDisinvestChips(
                    _valueGoodState.currentState.amount0()
                ) ||
                valueGoodResult2_.actualDisinvestQuantity >
                _valueGoodState.goodConfig.getDisinvestChips(
                    _valueGoodState.currentState.amount1()
                )
            ) revert TTSwapError(32);

            // Update value good states
            _valueGoodState.currentState = sub(
                _valueGoodState.currentState,
                toTTSwapUINT256(
                    disinvestvalue,
                    valueGoodResult2_.actualDisinvestQuantity
                )
            );

            _valueGoodState.investState = sub(
                _valueGoodState.investState,
                toTTSwapUINT256(
                    disinvestvalue,
                    valueGoodResult2_.actualDisinvestQuantity
                )
            );

            _valueGoodState.feeQuantityState = sub(
                _valueGoodState.feeQuantityState,
                toTTSwapUINT256(
                    valueGoodResult2_.profit,
                    valueGoodResult2_.actual_fee
                )
            );

            valueGoodResult2_.profit =
                valueGoodResult2_.profit -
                valueGoodResult2_.actual_fee;

            valueGoodResult2_.actual_fee = _valueGoodState
                .goodConfig
                .getDisinvestFee(valueGoodResult2_.actualDisinvestQuantity);

            if (valueGoodResult2_.actual_fee > 0) {
                _valueGoodState.feeQuantityState = add(
                    _valueGoodState.feeQuantityState,
                    toTTSwapUINT256(valueGoodResult2_.actual_fee, 0)
                );
            }
            allocateFee(
                _valueGoodState,
                valueGoodResult2_.profit,
                _params._marketconfig,
                _params._gater,
                _params._referral,
                _params._marketcreator,
                valueGoodResult2_.actualDisinvestQuantity -
                    valueGoodResult2_.actual_fee
            );
        }
        // Burn the investment proof
        _investProof.burnProof(disinvestvalue);
        // Allocate fees for main good
        allocateFee(
            _self,
            normalGoodResult1_.profit,
            _params._marketconfig,
            _params._gater,
            _params._referral,
            _params._marketcreator,
            normalGoodResult1_.actualDisinvestQuantity -
                normalGoodResult1_.actual_fee
        );
    }

    /**
     * @notice Allocate fees to various parties
     * @dev This function handles the allocation of fees to the market creator, gater, referrer, and liquidity providers
     * @param _self Storage pointer to the good state
     * @param _profit The total profit to be allocated
     * @param _marketconfig The market configuration
     * @param _gater The address of the gater (if applicable)
     * @param _referral The address of the referrer (if applicable)
     * @param _marketcreator The address of the market creator
     * @param _divestQuantity The quantity of goods being divested (if applicable)
     */
    function allocateFee(
        S_GoodState storage _self,
        uint128 _profit,
        uint256 _marketconfig,
        address _gater,
        address _referral,
        address _marketcreator,
        uint128 _divestQuantity
    ) private {
        // Calculate platform fee and deduct it from the profit
        uint128 marketfee = _marketconfig.getPlatFee128(_profit);
        _profit -= marketfee;

        // Calculate individual fees based on market configuration
        uint128 liquidFee = _marketconfig.getLiquidFee(_profit);
        uint128 sellerFee = _marketconfig.getSellerFee(_profit);
        uint128 gaterFee = _marketconfig.getGaterFee(_profit);
        uint128 referFee = _marketconfig.getReferFee(_profit);
        uint128 customerFee = _marketconfig.getCustomerFee(_profit);

        if (_referral == address(0)) {
            // If no referrer, distribute fees differently
            _self.commission[msg.sender] += (liquidFee + _divestQuantity);
            _self.commission[_gater] += sellerFee + customerFee;
            _self.commission[_marketcreator] += (_profit -
                liquidFee -
                sellerFee -
                customerFee +
                marketfee);
        } else {
            // If referrer exists, distribute fees according to roles
            if (_self.owner != _marketcreator) {
                _self.commission[_self.owner] += sellerFee;
            } else {
                marketfee += sellerFee;
            }

            if (_gater != _marketcreator) {
                _self.commission[_gater] += gaterFee;
            } else {
                marketfee += gaterFee;
            }

            if (_referral != _marketcreator) {
                _self.commission[_referral] += referFee;
            } else {
                marketfee += referFee;
            }

            _self.commission[_marketcreator] += marketfee;
            _self.commission[msg.sender] = (liquidFee +
                customerFee +
                _divestQuantity);
        }
    }

    /**
     * @notice Modify the good configuration
     * @dev This function modifies the good configuration by preserving the top 33 bits and updating the rest
     * @param _self Storage pointer to the good state
     * @param _goodconfig The new configuration value to be applied
     */
    function modifyGoodConfig(
        S_GoodState storage _self,
        uint256 _goodconfig
    ) internal {
        _self.goodConfig =
            (_self.goodConfig % (2 ** 229)) +
            (_goodconfig << 229);
    }

    /**
     * @notice fill good
     * @dev Preserves the top 33 bits of the existing config and updates the rest
     * @param _self Storage pointer to the good state
     * @param _fee New configuration value to be applied
     */
    function fillFee(S_GoodState storage _self, uint256 _fee) internal {
        _self.feeQuantityState = add(_self.feeQuantityState ,toTTSwapUINT256(uint128(_fee),0)); 
    }
}
