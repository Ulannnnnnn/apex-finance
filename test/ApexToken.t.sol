// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ApexToken} from "../src/tokens/ApexToken.sol";

contract ApexTokenTest is Test {
    ApexToken public token;
    address public owner = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    function setUp() public {
        // Деплоим токен от имени owner
        vm.prank(owner);
        token = new ApexToken(owner);
    }

    function test_InitialSupply() public view {
        // Проверяем, что при старте сминчено 10% (10_000_000)
        assertEq(token.totalSupply(), 10_000_000 * 10 ** 18);
        assertEq(token.balanceOf(owner), 10_000_000 * 10 ** 18);
    }

    function test_MintByOwner() public {
        vm.prank(owner);
        token.mint(user1, 1_000 * 10 ** 18);
        assertEq(token.balanceOf(user1), 1_000 * 10 ** 18);
    }

    function test_RevertWhen_MintByNonOwner() public {
        // Явно говорим Foundry, что следующая транзакция ДОЛЖНА завершиться ошибкой Ownable
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));

        vm.prank(user1);
        token.mint(user2, 1_000 * 10 ** 18);
    }

    function test_CannotExceedMaxSupply() public {
        uint256 maxRemaining = token.MAX_SUPPLY() - token.totalSupply();

        vm.prank(owner);
        token.mint(user1, maxRemaining); // Минтим до упора

        // Следующий минт даже на 1 токен должен вызвать реверт
        vm.prank(owner);
        vm.expectRevert("ApexToken: Max supply exceeded");
        token.mint(user1, 1 * 10 ** 18);
    }

    function test_VotingPowerDelegation() public {
        // Без делегирования сила голоса равна 0
        assertEq(token.getVotes(owner), 0);

        // Owner делегирует голоса самому себе
        vm.prank(owner);
        token.delegate(owner);

        // Теперь сила голоса равна его балансу
        assertEq(token.getVotes(owner), token.balanceOf(owner));
    }
}
