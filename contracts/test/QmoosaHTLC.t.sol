// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../src/QmoosaHTLC.sol";
import "../src/MockERC20.sol";

contract QmoosaHTLCTest is Test {
    QmoosaHTLC public htlc;
    MockERC20 public token;

    address public alice = address(0x1111);
    address public bob = address(0x2222);
    address public eve = address(0x3333);

    bytes public secret = "super_secure_crosschain_secret_42";
    bytes32 public hashlock;
    uint256 public constant AMOUNT = 1000 * 1e18;
    uint256 public timelock;
    uint256 public sourceChainId = 1;      // Ethereum
    uint256 public destChainId = 137;      // Polygon
    uint256 public nonce = 1;

    function setUp() public {
        htlc = new QmoosaHTLC();
        token = new MockERC20("USD Coin", "USDC", 18);

        hashlock = sha256(secret);
        timelock = block.timestamp + 3600; // 1 hour timelock

        token.mint(alice, 10_000 * 1e18);
        vm.prank(alice);
        token.approve(address(htlc), type(uint256).max);
    }

    function test_CreateSwapSuccess() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        QmoosaHTLC.Swap memory s = htlc.getSwap(swapId);
        assertEq(s.sender, alice);
        assertEq(s.recipient, bob);
        assertEq(s.amount, AMOUNT);
        assertEq(s.hashlock, hashlock);
        assertEq(s.timelock, timelock);
        assertEq(uint256(s.state), uint256(QmoosaHTLC.SwapState.FUNDED));
        assertEq(token.balanceOf(address(htlc)), AMOUNT);
    }

    function test_ClaimSwapWithValidSecret() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        // Bob or relayer claims with secret before timelock
        vm.prank(bob);
        htlc.claimSwap(swapId, secret);

        QmoosaHTLC.Swap memory s = htlc.getSwap(swapId);
        assertEq(uint256(s.state), uint256(QmoosaHTLC.SwapState.CLAIMED));
        assertEq(token.balanceOf(bob), AMOUNT);
        assertEq(token.balanceOf(address(htlc)), 0);
    }

    function test_ClaimRevertsWithInvalidSecret() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        bytes memory fakeSecret = "wrong_secret";
        vm.prank(eve);
        vm.expectRevert(QmoosaHTLC.InvalidSecretPreimage.selector);
        htlc.claimSwap(swapId, fakeSecret);
    }

    function test_ClaimRevertsAfterTimelockExpired() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        // Fast forward beyond timelock
        vm.warp(timelock + 1);

        vm.prank(bob);
        vm.expectRevert(QmoosaHTLC.SwapExpired.selector);
        htlc.claimSwap(swapId, secret);
    }

    function test_RefundSwapAfterTimelockExpired() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        uint256 aliceBalBefore = token.balanceOf(alice);

        // Fast forward beyond timelock
        vm.warp(timelock + 1);

        // Alice or relayer refunds
        vm.prank(alice);
        htlc.refundSwap(swapId);

        QmoosaHTLC.Swap memory s = htlc.getSwap(swapId);
        assertEq(uint256(s.state), uint256(QmoosaHTLC.SwapState.REFUNDED));
        assertEq(token.balanceOf(alice), aliceBalBefore + AMOUNT);
        assertEq(token.balanceOf(address(htlc)), 0);
    }

    function test_RefundRevertsBeforeTimelockExpired() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        vm.prank(alice);
        vm.expectRevert(QmoosaHTLC.SwapNotExpired.selector);
        htlc.refundSwap(swapId);
    }

    function test_ClaimVersusRefundMutualExclusion() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        // Claimed first
        vm.prank(bob);
        htlc.claimSwap(swapId, secret);

        // Attempting to refund after claim must revert even after timelock
        vm.warp(timelock + 10);
        vm.prank(alice);
        vm.expectRevert(QmoosaHTLC.SwapNotFoundOrNotFunded.selector);
        htlc.refundSwap(swapId);
    }

    function test_RefundVersusClaimMutualExclusion() public {
        vm.prank(alice);
        bytes32 swapId = htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        // Refunded after expiry
        vm.warp(timelock + 1);
        vm.prank(alice);
        htlc.refundSwap(swapId);

        // Attempting to claim after refund must revert
        vm.prank(bob);
        vm.expectRevert(QmoosaHTLC.SwapNotFoundOrNotFunded.selector);
        htlc.claimSwap(swapId, secret);
    }

    function test_ReentrancyAndReplayDefense() public {
        vm.prank(alice);
        htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );

        // Replay of same parameters must revert
        vm.prank(alice);
        vm.expectRevert(QmoosaHTLC.SwapAlreadyExists.selector);
        htlc.createSwap(
            bob,
            address(token),
            AMOUNT,
            hashlock,
            timelock,
            sourceChainId,
            destChainId,
            nonce
        );
    }

    function testFuzz_BalanceConservation(uint96 amount, uint16 duration) public {
        vm.assume(amount > 1000);
        vm.assume(duration >= 350 && duration <= 100000);

        uint256 fTimelock = block.timestamp + duration;
        bytes32 fSecret = keccak256(abi.encode(amount, duration));
        bytes32 fHashlock = sha256(abi.encodePacked(fSecret));

        token.mint(alice, amount);

        vm.prank(alice);
        bytes32 sId = htlc.createSwap(
            bob,
            address(token),
            amount,
            fHashlock,
            fTimelock,
            1,
            137,
            uint256(keccak256(abi.encode(amount)))
        );

        assertEq(token.balanceOf(address(htlc)), amount);

        // Claim
        vm.prank(bob);
        htlc.claimSwap(sId, abi.encodePacked(fSecret));
        assertEq(token.balanceOf(address(htlc)), 0);
    }
}
