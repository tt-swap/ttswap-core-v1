// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC20} from "./base/ERC20.sol";
import {I_TTSwap_Market} from "./interfaces/I_TTSwap_Market.sol";
import {I_TTSwap_Token, s_share, s_proof} from "./interfaces/I_TTSwap_Token.sol";
import {L_TTSTokenConfigLibrary} from "./libraries/L_TTSTokenConfig.sol";
import {TTSwapError} from "./libraries/L_Error.sol";
import {toTTSwapUINT256, L_TTSwapUINT256Library, add, sub, mulDiv} from "./libraries/L_TTSwapUINT256.sol";
import {I_TTSwap_Market, S_GoodTmpState} from "./interfaces/I_TTSwap_Market.sol";
import {IDepositContract} from "./interfaces/IDepositContract.sol";
import {IWithdrawContract} from "./interfaces/IWithdrawContract.sol";
import {L_Strings} from "./libraries/L_Strings.sol";
import {L_ETHLibrary} from "./libraries/L_ETH.sol";
import {L_Transient} from "./libraries/L_Transient.sol";
contract TTSwap_StakeETH {
    using L_TTSwapUINT256Library for uint256;
    using L_Strings for address;

    uint256 TotalState; //amount0:totalShare, amount1:totalETHQuantity
    uint256 TotalStake; // amount0:stakingAmount amount1:currentBalance
    address protocolCreator;
    address protocolManager;

    IDepositContract internal constant depositcontract =
        IDepositContract(0x00000000219ab540356cBB839Cbe05303d7705Fa);
    IWithdrawContract internal constant withdrawcontract =
        IWithdrawContract(0x00000961Ef480Eb55e80D19ad83579A64c007002);
    address internal constant eth = address(2);
    bytes32 public immutable withdrawalCenti;
    mapping(address user => uint256 amount) public userStakeState; // amount0() represent share,amount1() represent quanity
    mapping(bytes publickey => uint256 stakeamount) public nodeState; //amount0() represent permit,amount1() stakingamount
    constructor(address _creator) {
        protocolCreator = _creator;
        protocolManager = msg.sender;
        withdrawalCenti = bytes32(
            abi.encodePacked(
                hex"0100000000000000",
                abi.encodePacked(address(this))
            )
        );
    }

    modifier onlyCreator() {
        require(msg.sender == protocolCreator);
        _;
    }

    modifier onlyManager() {
        require(msg.sender == protocolManager);
        _;
    }

    modifier noReentrant() {
        if (L_Transient.get() != address(0)) revert TTSwapError(3);
        L_Transient.set(msg.sender);
        _;
        L_Transient.set(address(0));
    }

    function stakeEth(uint128 _stakeamount) external payable noReentrant {
        L_ETHLibrary.transferFrom(_stakeamount);
        TotalStake = add(TotalStake, toTTSwapUINT256(0, _stakeamount));
        uint128 _stakeshare;
        if (TotalState != 0) {
            _stakeshare = TotalState.getamount0fromamount1(_stakeamount);
            TotalState = add(
                TotalState,
                toTTSwapUINT256(_stakeshare, _stakeamount)
            );
            userStakeState[msg.sender] = add(
                userStakeState[msg.sender],
                toTTSwapUINT256(_stakeshare, _stakeamount)
            );
        } else {
            TotalState = add(
                TotalState,
                toTTSwapUINT256(_stakeamount, _stakeamount)
            );
            userStakeState[msg.sender] = add(
                userStakeState[msg.sender],
                toTTSwapUINT256(_stakeamount, _stakeamount)
            );
        }
    }

    function unstakeEthSome(
        uint128 amount
    ) external noReentrant returns (uint128 reward) {
        internalReward();
        require(TotalStake.amount1() >= amount);
        uint128 unstakeshare = userStakeState[msg.sender].getamount0fromamount1(
            amount
        );
        userStakeState[msg.sender] = sub(
            userStakeState[msg.sender],
            toTTSwapUINT256(unstakeshare, amount)
        );
        reward = TotalState.getamount1fromamount0(unstakeshare);
        TotalState = sub(TotalState, toTTSwapUINT256(unstakeshare, reward));
        TotalStake = sub(TotalStake, toTTSwapUINT256(0, reward));
        reward = reward - amount;
        L_ETHLibrary.transfer(protocolManager, reward / 9);
        reward = reward - reward / 9;
        L_ETHLibrary.transfer(msg.sender, amount + reward);
    }

    function unstakeETHAll()
        external
        noReentrant
        returns (uint128 reward, uint128 amount)
    {
        internalReward();
        uint256 unstakeshare = userStakeState[msg.sender];
        amount = unstakeshare.amount1();
        delete userStakeState[msg.sender];
        reward = TotalState.getamount1fromamount0(unstakeshare.amount0());
        TotalState = sub(
            TotalState,
            toTTSwapUINT256(unstakeshare.amount0(), reward)
        );
        TotalStake = sub(TotalStake, toTTSwapUINT256(0, reward));
        reward = reward - amount;
        L_ETHLibrary.transfer(protocolManager, reward / 9);
        reward = reward - reward / 9;
        L_ETHLibrary.transfer(msg.sender, amount + reward);
    }

    function internalReward() internal {
        if (address(this).balance >= TotalStake.amount1()) {
            uint256 reward = address(this).balance - TotalStake.amount1();
            TotalStake = add(TotalStake, toTTSwapUINT256(0, uint128(reward)));
            TotalState = add(TotalState, toTTSwapUINT256(0, uint128(reward)));
        }
    }

    function syncReward() external noReentrant returns (uint128 reward) {
        internalReward();
        uint256 stakeState = userStakeState[msg.sender];
        reward =
            TotalState.getamount1fromamount0(stakeState.amount0()) -
            stakeState.amount1();
        uint128 share = TotalState.getamount0fromamount1(reward);
        userStakeState[msg.sender] = sub(stakeState, toTTSwapUINT256(share, 0));
        TotalStake = sub(TotalStake, toTTSwapUINT256(0, reward));
        TotalState = sub(TotalState, toTTSwapUINT256(share, reward));
        L_ETHLibrary.transfer(protocolManager, reward / 9);
        reward = reward - reward / 9;
        L_ETHLibrary.transfer(msg.sender, reward);
    }

    function addValidateNode(
        bytes memory _publickey
    ) external noReentrant onlyManager {
        nodeState[_publickey] = toTTSwapUINT256(1, 0);
    }

    function removeValidateNode(
        bytes memory _publicKey
    ) external noReentrant onlyManager {
        nodeState[_publicKey] = toTTSwapUINT256(
            0,
            nodeState[_publicKey].amount1()
        );
    }

    function get_deposit_root() external view returns (bytes32) {
        return depositcontract.get_deposit_root();
    }

    function validator_deposit(
        bytes calldata publickey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        uint128 amount,
        bytes32 deposit_data_root
    ) external noReentrant onlyManager {
        require(TotalStake.amount1() > amount);
        uint256 _nodestate = nodeState[publickey];
        nodeState[publickey] = toTTSwapUINT256(
            _nodestate.amount0(),
            _nodestate.amount1() + amount
        );
        TotalStake = toTTSwapUINT256(
            TotalStake.amount0() + amount,
            TotalStake.amount1() - amount
        );
        require(
            amount % 1 gwei == 0,
            "DepositContract: deposit value not multiple of gwei"
        );
        depositcontract.deposit{value: amount}(
            publickey,
            withdrawalCredentials,
            signature,
            deposit_data_root
        );
    }

    function validatorWithdraw(
        bytes calldata publickey,
        uint64 amount
    ) external noReentrant onlyManager {
        _validatorWithdraw(publickey, amount);
    }

    function _validatorWithdraw(bytes memory pubkey, uint64 amount) private {
        assert(pubkey.length == 48);

        // Read current fee from the contract.
        (bool readOK, bytes memory feeData) = address(withdrawcontract)
            .staticcall("");
        if (!readOK) {
            revert("reading fee failed");
        }
        uint256 fee = uint256(bytes32(feeData));

        // Add the request.
        bytes memory callData = abi.encodePacked(pubkey, amount);
        (bool writeOK, ) = address(withdrawcontract).call{value: fee}(callData);
        if (!writeOK) {
            revert("adding request failed");
        }
    }

    function validatorWithdrawalExit(
        bytes memory pubkey
    ) external noReentrant onlyManager {
        assert(pubkey.length == 48);
        // Read current fee from the contract.
        (bool readOK, bytes memory feeData) = address(withdrawcontract)
            .staticcall("");
        if (!readOK) {
            revert("reading fee failed");
        }
        uint256 fee = uint256(bytes32(feeData));
        // Add the request.
        bytes memory callData = abi.encodePacked(pubkey);
        (bool writeOK, ) = address(withdrawcontract).call{value: fee}(callData);
        if (!writeOK) {
            revert("adding request failed");
        }
    }
    receive() external payable {}
    fallback() external payable {}
}
