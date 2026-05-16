// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ApexToken} from "../src/tokens/ApexToken.sol";

contract ApexTokenTest is Test {
    ApexToken public token;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    function setUp() public {
        vm.prank(owner);
        token = new ApexToken(owner);
    }

    // --- Блок 1: Базовое состояние и Минт (7 тестов) ---

    function test_InitialSupply() public view {
        assertEq(token.totalSupply(), 10_000_000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 10_000_000 * 10 ** 18);
    }

    function test_TokenMetadata() public view {
        assertEq(token.name(), "Apex Finance Token");
        assertEq(token.symbol(), "APEX");
        assertEq(token.decimals(), 18);
    }

    function test_MintByOwner() public {
        vm.prank(owner);
        token.mint(user1, 1_000 * 10 ** 18);
        assertEq(token.balanceOf(user1), 1_000 * 10 ** 18);
    }

    function test_RevertWhen_MintByNonOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        vm.prank(user1);
        token.mint(user2, 1_000 * 10 ** 18);
    }

    function test_CannotExceedMaxSupply() public {
        uint256 maxRemaining = token.MAX_SUPPLY() - token.totalSupply();
        vm.prank(owner);
        token.mint(user1, maxRemaining);

        vm.prank(owner);
        vm.expectRevert("ApexToken: Max supply exceeded");
        token.mint(user1, 1 * 10 ** 18);
    }

    function test_TransferTokens() public {
        vm.prank(owner);
        token.transfer(user1, 500 * 10 ** 18);
        assertEq(token.balanceOf(user1), 500 * 10 ** 18);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.prank(user1);
        vm.expectRevert(); // Баланс user1 равен 0
        token.transfer(user2, 10 * 10 ** 18);
    }

    // --- Блок 2: Голосование и Делегирование (6 тестов) ---

    function test_InitialVotingPowerIsZero() public view {
        assertEq(token.getVotes(owner), 0);
    }

    function test_VotingPowerDelegation() public {
        vm.prank(owner);
        token.delegate(owner);
        assertEq(token.getVotes(owner), token.balanceOf(owner));
    }

    function test_DelegateToAnotherUser() public {
        vm.prank(owner);
        token.delegate(user1);
        assertEq(token.getVotes(user1), token.balanceOf(owner));
        assertEq(token.getVotes(owner), 0);
    }

    function test_VotingPowerChangesOnTransfer() public {
        // Owner делегирует себе
        vm.prank(owner);
        token.delegate(owner);

        // User1 делегирует себе
        vm.prank(user1);
        token.delegate(user1);

        // Переводим токены от owner к user1
        vm.prank(owner);
        token.transfer(user1, 2_000_000 * 10 ** 18);

        // Сила голоса должна измениться пропорционально новым балансам
        assertEq(token.getVotes(owner), 8_000_000 * 10 ** 18);
        assertEq(token.getVotes(user1), 2_000_000 * 10 ** 18);
    }

    function test_TransferDestroysVotingPowerIfNotDelegated() public {
        vm.prank(owner);
        token.delegate(owner);

        // Переводим токены пользователю user2, который никому не делегировал
        vm.prank(owner);
        token.transfer(user2, 1_000 * 10 ** 18);

        // Сила голоса user2 должна остаться 0, а у owner уменьшиться
        assertEq(token.getVotes(user2), 0);
        assertEq(token.getVotes(owner), (10_000_000 - 1_000) * 10 ** 18);
    }

    function test_OwnableTransfer() public {
        vm.prank(owner);
        token.transferOwnership(user1);
        assertEq(token.owner(), user1);
    }
}
