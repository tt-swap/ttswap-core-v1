// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import {Test, console2} from "forge-std/src/Test.sol";
import {MyToken} from "../src/test/MyToken.sol";
import "../src/TTSwap_Market.sol";
import {BaseSetup} from "./BaseSetup.t.sol";
import { S_ProofKey} from "../src/interfaces/I_TTSwap_Market.sol";
import {L_ProofIdLibrary, L_Proof} from "../src/libraries/L_Proof.sol";
import {L_Good} from "../src/libraries/L_Good.sol";
import {
    L_TTSwapUINT256Library,
    toTTSwapUINT256,
    addsub,
    subadd,
    lowerprice,
    toUint128
} from "../src/libraries/L_TTSwapUINT256.sol";

import {L_GoodConfigLibrary} from "../src/libraries/L_GoodConfig.sol";

import {
    L_TTSwapUINT256Library,
    toTTSwapUINT256,
    addsub,
    subadd,
    lowerprice,
    toUint128
} from "../src/libraries/L_TTSwapUINT256.sol";

contract buyNativeETHNormalGoodPay is BaseSetup {
   
    using L_TTSwapUINT256Library for uint256;
    using L_GoodConfigLibrary for uint256;

    using L_ProofIdLibrary for S_ProofKey;

    address metagood;
    address normalgoodusdt;
    address normalgoodbtc;

    function setUp() public override {
        BaseSetup.setUp();
        initmetagood();
        initnativeethgood();
    }

    function initmetagood() public {
        BaseSetup.setUp();
        vm.startPrank(marketcreator);
        deal(address(usdt), marketcreator, 1000000 * 10 ** 6, false);
        usdt.approve(address(market), 50000 * 10 ** 6 + 1);
        uint256 _goodconfig = (2 ** 255) + 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197;
        market.initMetaGood(address(usdt), toTTSwapUINT256(50000 * 10 ** 6, 50000 * 10 ** 6), _goodconfig, defaultdata);
        metagood = address(usdt);
        vm.stopPrank();
    }

    function initnativeethgood() public {
        vm.startPrank(users[1]);
        deal(users[1], 10 * 10 ** 8);
        deal(address(usdt), users[1], 50000000 * 10 ** 6, false);
        usdt.approve(address(market), 50000000 * 10 ** 6 + 1);
        assertEq(usdt.balanceOf(address(market)), 50000 * 10 ** 6, "befor init erc20 good, balance of market error");
        uint256 normalgoodconfig = 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197;
        market.initGood{value: 100000000}(
            metagood,
            toTTSwapUINT256(1 * 10 ** 8, 63000 * 10 ** 6),
            address(1),
            normalgoodconfig,
            defaultdata,
            defaultdata
        );
        normalgoodbtc = address(1);
        vm.stopPrank();
    }

    function testPayNativeETHGoodWithoutChips() public {
        vm.startPrank(users[1]);
        usdt.approve(address(market), 800000 * 10 ** 6 + 1);
        btc.approve(address(market), 10 * 10 ** 8 + 1);
        assertEq(users[1].balance, 900000000, "before buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49937000000000,
            "before buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            113000000000,
            "before buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            100000000,
            "before buy nativeeth_normalgood:btc address(market) account  balance error"
        );

        market.buyGood{value: 1 * 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 101, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_without_chips_first");
        assertEq(
            usdt.balanceOf(users[1]),
            49943300000000,
            "after buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(users[1].balance, 889986996, "after buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(address(market).balance, 110013004, "after buy nativeeth_normalgood:btc market account  balance error");
        assertEq(
            usdt.balanceOf(address(market)),
            106700000000,
            "after buy nativeeth_normalgood:usdt market account  balance error"
        );

        S_GoodTmpState memory good_ = market.getGoodState(metagood);
        assertEq(
            good_.currentState.amount0(),
            119298110000,
            "after buy nativeeth_normalgood:metagood currentState amount0 error"
        );
        assertEq(
            good_.currentState.amount1(),
            106689290000,
            "after buy nativeeth_normalgood:metagood currentState amount1 error"
        );
        assertEq(
            good_.investState.amount0(),
            112993700000,
            "after buy nativeeth_normalgood:metagood investState amount0 error"
        );
        assertEq(
            good_.investState.amount1(),
            112993700000,
            "after buy nativeeth_normalgood:metagood investState amount1 error"
        );
        assertEq(
            good_.feeQuantityState.amount0(),
            10710000,
            "after buy nativeeth_normalgood:metagood feeQuantityState amount0 error"
        );
        assertEq(
            good_.feeQuantityState.amount1(),
            0,
            "after buy nativeeth_normalgood:metagood feeQuantityState amount1 error"
        );

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_without_chips_second");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_without_chips_three");

        vm.stopPrank();
    }

    function testPayNativeETHGoodWithChips1() public {
        vm.startPrank(users[1]);
        uint256 goodconfig = 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197 + 2 * 2 ** 216 + 3 * 2 ** 206;
        market.updateGoodConfig(normalgoodbtc, goodconfig);

        usdt.approve(address(market), 800000 * 10 ** 6 + 1);
        btc.approve(address(market), 10 * 10 ** 8 + 1);
        assertEq(users[1].balance, 900000000, "before buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49937000000000,
            "before buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            113000000000,
            "before buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            100000000,
            "before buy nativeeth_normalgood:btc address(market) account  balance error"
        );

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_first_1chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_1chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 112, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_12chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_10chips");
        vm.stopPrank();
    }

    function testPayNativeETHGoodWithChipswithRefere() public {
        vm.startPrank(users[1]);
        uint256 goodconfig = 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197 + 2 * 2 ** 216 + 3 * 2 ** 206;
        market.updateGoodConfig(normalgoodbtc, goodconfig);

        usdt.approve(address(market), 800000 * 10 ** 6 + 1);
        btc.approve(address(market), 10 * 10 ** 8 + 1);
        assertEq(users[1].balance, 900000000, "before buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49937000000000,
            "before buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            113000000000,
            "before buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            100000000,
            "before buy nativeeth_normalgood:btc address(market) account  balance error"
        );

        market.buyGood(metagood, normalgoodbtc, 63000000, 1, users[3], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_first_1chips_refere");

        market.buyGood(metagood, normalgoodbtc, 63000000, 1, users[3], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_1chips_refere");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 112, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_12chips_refere");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_10chips_refere");
        vm.stopPrank();
    }

    function testPayNativeETHGoodWithChipsmulticall1() public {
        vm.startPrank(users[1]);
        uint256 goodconfig = 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197 + 2 * 2 ** 216 + 3 * 2 ** 206;
        market.updateGoodConfig(normalgoodbtc, goodconfig);

        usdt.approve(address(market), 800000 * 10 ** 6 + 1);
        btc.approve(address(market), 10 * 10 ** 8 + 1);
        assertEq(users[1].balance, 900000000, "before buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49937000000000,
            "before buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            113000000000,
            "before buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            100000000,
            "before buy nativeeth_normalgood:btc address(market) account  balance error"
        );

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_first_1chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_1chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 112, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_12chips");

        market.buyGood{value: 10 ** 8}(metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata);
        snapLastCall("pay_nativeeth_normal_good_chips_second_10chips");
        vm.stopPrank();

        assertEq(users[1].balance, 875909006, "after buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49949726000000,
            "after buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            100274000000,
            "after buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            124090994,
            "after buy nativeeth_normalgood:btc address(market) account  balance error"
        );
    }

    function testPayNativeETHGoodWithChipsmulticall2() public {
        vm.startPrank(users[1]);
        uint256 goodconfig = 1 * 2 ** 217 + 3 * 2 ** 211 + 5 * 2 ** 204 + 7 * 2 ** 197 + 2 * 2 ** 216 + 3 * 2 ** 206;
        market.updateGoodConfig(normalgoodbtc, goodconfig);

        usdt.approve(address(market), 800000 * 10 ** 6 + 1);
        btc.approve(address(market), 10 * 10 ** 8 + 1);
        assertEq(users[1].balance, 900000000, "before buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49937000000000,
            "before buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            113000000000,
            "before buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            100000000,
            "before buy nativeeth_normalgood:btc address(market) account  balance error"
        );

        bytes[] memory calls = new bytes[](4);
        calls[0] = abi.encodeWithSelector(
            TTSwap_Market(market).buyGood.selector, metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata
        );

        calls[1] = abi.encodeWithSelector(
            TTSwap_Market(market).buyGood.selector, metagood, normalgoodbtc, 63000000, 101, users[1], defaultdata
        );

        calls[2] = abi.encodeWithSelector(
            TTSwap_Market(market).buyGood.selector, metagood, normalgoodbtc, 6300 * 10 ** 6, 112, users[1], defaultdata
        );

        calls[3] = abi.encodeWithSelector(
            TTSwap_Market(market).buyGood.selector, metagood, normalgoodbtc, 6300 * 10 ** 6, 110, users[1], defaultdata
        );

        market.multicall{value: 10 ** 8}(calls);
        snapLastCall("multicall_pay_nativeeth_normal_good_chips_3call");
        vm.stopPrank();

        assertEq(users[1].balance, 875909006, "after buy nativeeth_normalgood:btc users[1] account  balance error");
        assertEq(
            usdt.balanceOf(users[1]),
            49949726000000,
            "after buy nativeeth_normalgood:usdt users[1] account  balance error"
        );
        assertEq(
            usdt.balanceOf(address(market)),
            100274000000,
            "after buy nativeeth_normalgood:usdt address(market) account  balance error"
        );
        assertEq(
            address(market).balance,
            124090994,
            "after buy nativeeth_normalgood:btc address(market) account  balance error"
        );
    }
}
